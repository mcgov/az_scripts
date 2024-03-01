#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit -1
    fi
}
FWDMODE="$1" # should be rxonly or txonly
if [[ -z "$FWDMODE" ]]; then
    FWDMODE="txonly"
fi
SEND_IP="$2"   #ip addr of sender (needed on sender only)
RECV_IP="$3"   # ip addr of receiver (needed on sender only)
# Assuming use of eth1 for DPDK in this demo
PRIMARY="eth1"
# $ ip -br link show master eth1 
# > enP30832p0s0     UP             f0:0d:3a:ec:b4:0a <... # truncated
# grab interface name for device bound to primary
echo "Checking for lower interface for eth1..."
SECONDARY="`ip -br link show master $PRIMARY | awk '{ print $1 }'`"
echo "Note: Test expects 2 NICs so if this call fails either:"
echo " - the NIC was already bound to netvsc, restart the node and run this script again."
echo " or:"
echo " - The VM was deployed with 1 NIC. Add another AccelNet enabled NIC."
assert_success

# Get mac address for MANA interface (should match primary)
export MANA_MAC="`ip -br link show master $PRIMARY | awk '{ print $3 }'`"
# $ ethtool -i enP30832p0s0 | grep bus-info
# > bus-info: 7870:00:00.0
# get MANA device bus info to pass to DPDK
export BUS_INFO="`ethtool -i $SECONDARY | grep bus-info | awk '{ print $2 }'`"

# Set MANA interfaces DOWN before starting DPDK
sudo ip link set $PRIMARY down
sudo ip link set $SECONDARY down
## Move synthetic channel to user mode and allow it to be used by NETVSC PMD in DPDK
DEV_UUID=$(basename $(readlink /sys/class/net/$PRIMARY/device))
assert_success
NET_UUID="f8615163-df3e-46c5-913f-f2d2f965ed0e"
echo "loading uio_hv_generic driver..."
sudo modprobe uio_hv_generic
assert_success
echo $NET_UUID | sudo tee -a /sys/bus/vmbus/drivers/uio_hv_generic/new_id
assert_success
echo $DEV_UUID | sudo tee -a /sys/bus/vmbus/drivers/hv_netvsc/unbind
assert_success
echo $DEV_UUID | sudo tee -a /sys/bus/vmbus/drivers/uio_hv_generic/bind
assert_success
VDEV_ARG="--vdev=$BUS_INFO,mac=$MANA_MAC"

if [[ "$FWDMODE" == "rxonly" ]] || [[ -z "$SEND_IP" ]] || [[ -z "$RECV_IP" ]]; then
    SENDER_IP_ARG=""
else
    SENDER_IP_ARG="--tx-ip=\"$SEND_IP,$RECV_IP\""
fi

echo "Running multiple queue test, needs >= 64 cores"
# get core count, calculcate core argument (fwd cores + 1) and # of forwarding cores to use
let CPUCOUNT=`lscpu | grep CPU\(s\): | awk  '{ print $2 }'`
let SIXFOUR=64
if [[ $CPUCOUNT -eq $SIXFOUR ]]; then
    let FWD_CORES=32
elif [[ $CPUCOUNT -gt $SIXFOUR ]]; then
    let FWD_CORES=64
else
    echo "DPDK multi-queue test needs >= 64 cores to run. 64 uses 32 cores and 32 queues, >64 uses 64 cores and 32 queues."
    exit -1
fi
let LAST_CORE=$FWD_CORES+1

RUN_DPDK_CMD="sudo timeout -s INT 120 dpdk-testpmd -l 1-$LAST_CORE $VDEV_ARG -- --forward-mode=$FWDMODE --auto-start --nb-cores=$FWD_CORES  --txd=128 --rxd=128 --txq=32 --rxq=32 --stats 2  $SENDER_IP_ARG"
echo $RUN_DPDK_CMD >> ./rerun-dpdk-testpmd

# MANA multiple queue test (example assumes > 64 cores)
$RUN_DPDK_CMD

echo "NOTE: cat ./rerun-dpdk-testpmd for the testpmd command for future re-runs before rebooting."