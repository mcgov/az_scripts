#! /bin/bash
# author: mamcgove @microsoft.com

# run a packet-per-second test with dpdk-testpmd.
# this script sets up a test using the netvsc pmd
# you can use the same script to start a sender and receiver on two VMs
# `pps-dpdk-testpmd.sh rxonly` on the receiver
# `pps-dpdk-testpmd.sh txonly $SENDER_IP,$RECEIVER_IP` on the sender


function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit 1
    fi
}

## Parse Arguments
FWDMODE="$1" # should be rxonly or txonly
if [[ -z "$FWDMODE" ]]; then
    FWDMODE="txonly"
fi
SEND_IP="$2"   #ip addr of sender (needed on sender only)
RECV_IP="$3"   # ip addr of receiver (needed on sender only)
# Assuming use of eth1 for DPDK in this demo

if [[ "$FWDMODE" == "rxonly" ]] || [[ -z "$SEND_IP" ]] || [[ -z "$RECV_IP" ]]; then
    SENDER_IP_ARG=""
else
    SENDER_IP_ARG="--tx-ip=\"$SEND_IP,$RECV_IP\""
fi

## Check number of cores is >= 64
echo "Running multiple queue test, needs >= 64 cores"
# get core count, calculcate core argument (fwd cores + 1) and # of forwarding cores to use
((CPUCOUNT=$(lscpu | grep -P '^CPU\(s\):\s+[0-9]+' | awk  '{ print $2 }')))
((SIXFOUR=64))
if [[ $CPUCOUNT -eq $SIXFOUR ]]; then
    ((FWD_CORES=32))
elif [[ $CPUCOUNT -gt $SIXFOUR ]]; then
    ((FWD_CORES=64))
else
    echo "DPDK multi-queue test needs >= 64 cores to run. 64 uses 32 cores and 32 queues, >64 uses 64 cores and 32 queues."
    exit 1
fi
((LAST_CORE=FWD_CORES+1))

## Set up DPDK netvsc pmd for eth1
PRIMARY="eth1"
echo "running netvsc pmd setup. Must re-run "
if [[ -e "/sys/class/net/$PRIMARY" ]]; then
    ./setup-netvsc-pmd.sh eth1
    assert_success
else
    echo "eth1 not found, assuming re-run and attempt to set lower down..."
    # otherwise, this is a re-run, attempt to set the lower interface down.
    LOWER=$(cat ./$PRIMARY.lower.nic)
    if [[ -z "$LOWER" ]]; then
        echo "Note file: ./$PRIMARY.lower.nic not found. Setup is broken."
        ./display-maintainer-info.sh
        exit 1
    fi
    ip link set "$LOWER" down
fi

# Setup should place an argument file with the stuff needed to run testpmd
# Or, it's already there.
if [[ -f "./$PRIMARY.dpdk-eal-vdev.arg" ]]; then
    VDEV_ARG=$(cat ./$PRIMARY.dpdk-eal-vdev.arg)
else
    echo "There was a problem fetching the DPDK EAL vdev argument for $PRIMARY"
    ./display-maintainer-info.sh
    exit 1
fi

## Enable hugepages before starting testpmd
./enable-hugepages-2mb.sh

# log the testpmd command for future re-runs
RUN_DPDK_CMD="sudo timeout -s INT 120 dpdk-testpmd -l 1-$LAST_CORE $VDEV_ARG -- --forward-mode=$FWDMODE --auto-start --nb-cores=$FWD_CORES  --txd=128 --rxd=128 --txq=32 --rxq=32 --stats 2  $SENDER_IP_ARG"
echo "$RUN_DPDK_CMD" | tee -a ./rerun-dpdk-testpmd

## Start MANA multiple queue test (example assumes > 64 cores)
sudo timeout -s INT 120 dpdk-testpmd -l "1-$LAST_CORE" "$VDEV_ARG" -- --forward-mode="$FWDMODE" --auto-start --nb-cores="$FWD_CORES"  --txd=128 --rxd=128 --txq=32 --rxq=32 --stats 2  "$SENDER_IP_ARG"

echo "Run complete!"
exit 0;
