#! /bin/bash
DPDK_APP_PATH=$1
DPDK_PORT_CONFIG=$2

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit -1
    fi
}

function check_and_append {
    #check that it's set
    cat $1 | grep "$2"
    #append if it wasn't present
    if [ $? -ne 0 ]; then
        echo "$2" >> $1
    fi;
}

echo "preparing for netvsc pmd use"

# Assuming use of eth1 and eth2
VDEV_ARG=""
MAC_INFO=""

modprobe uio_hv_generic
assert_success
NET_UUID="f8615163-df3e-46c5-913f-f2d2f965ed0e"
echo $NET_UUID > /sys/bus/vmbus/drivers/uio_hv_generic/new_id

for nic in eth1 eth2;
do
    # $ ip -br link show master eth1 
    # > enP30832p0s0     UP             f0:0d:3a:ec:b4:0a <... # truncated
    # grab interface name for device bound to primary
    SECONDARY="`ip -br link show master $nic | awk '{ print $1 }'`"
    # Get mac address for MANA interface (should match primary)
    export MANA_MAC="`ip -br link show master $nic | awk '{ print $3 }'`"
    # $ ethtool -i enP30832p0s0 | grep bus-info
    # > bus-info: 7870:00:00.0
    # get MANA device bus info to pass to DPDK
    export BUS_INFO="`ethtool -i $SECONDARY | grep bus-info | awk '{ print $2 }'`"

    # Set MANA interfaces DOWN before starting DPDK
    sudo ip link set $nic down
    sudo ip link set $nic down
    ## Move synthetic channel to user mode and allow it to be used by NETVSC PMD in DPDK
    DEV_UUID=$(basename $(readlink /sys/class/net/$nic/device))
    echo $DEV_UUID > /sys/bus/vmbus/drivers/hv_netvsc/unbind
    echo $DEV_UUID > /sys/bus/vmbus/drivers/uio_hv_generic/bind
    if [[ -z "$MAC_INFO" ]]; then
        MAC_INFO="mac=$MANA_MAC"
    else
        MAC_INFO="$MAC_INFO,mac=$MANA_MAC"
    fi
done

VDEV_ARG="--vdev=$BUS_INFO,$MAC_INFO"

echo "Use $VDEV_ARG for l3fwd EAL argument"
# TODO: wrong command

echo "Running multiple queue test, needs >= 8 cores"
DPDK_COMMAND="sudo timeout 300 $DPDK_APP_PATH -l 1-17 $VDEV_ARG -- -p 0xC  --lookup=lpm --config=\"$DPDK_PORT_CONFIG\" --rule_ipv4=rules_v4  --rule_ipv6=rules_v6 --mode=poll --parse-ptype"
echo $DPDK_COMMAND >> rerun_l3fwd
$DPDK_COMMAND