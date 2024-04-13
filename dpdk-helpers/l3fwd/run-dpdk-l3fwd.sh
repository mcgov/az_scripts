#! /bin/bash

DPDK_APP_PATH="$1"
DPDK_APP_EXEC="$DPDK_APP_PATH/dpdk-l3fwd"
DPDK_RULES_V4="$DPDK_APP_PATH/rules_v4"
DPDK_RULES_V6="$DPDK_APP_PATH/rules_v6"

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit 1
    fi
}

echo "preparing for netvsc pmd use"

# Assuming use of eth1 and eth2
VDEV_ARG=""
MAC_INFO=""

sudo modprobe uio_hv_generic
assert_success

NET_UUID="f8615163-df3e-46c5-913f-f2d2f965ed0e"
echo "$NET_UUID" | sudo tee /sys/bus/vmbus/drivers/uio_hv_generic/new_id

if [ -e ./vdev_arg ]; then
    VDEV_ARG=$( cat ./vdev_arg )
else
    for nic in eth1 eth2;
    do
        # $ ip -br link show master eth1 
        # > enP30832p0s0     UP             f0:0d:3a:ec:b4:0a <... # truncated
        # grab interface name for device bound to primary
        SECONDARY=$(ip -br link show master "$nic" | awk '{ print $1 }')
        # Get mac address for MANA interface (should match primary)
        MANA_MAC=$(ip -br link show master "$nic" | awk '{ print $3 }')
        # $ ethtool -i enP30832p0s0 | grep bus-info
        # > bus-info: 7870:00:00.0
        # get MANA device bus info to pass to DPDK
        DEVICE_INFO=$(ethtool -i "$SECONDARY")
        BUS_INFO_RAW=$(echo "$DEVICE_INFO" | grep bus-info)
        BUS_INFO=$(echo "$BUS_INFO_RAW" | awk '{ print $2 }')

        ## Move synthetic channel to user mode and allow it to be used by NETVSC PMD in DPDK
        NIC_DEV=$(readlink /sys/class/net/"$nic"/device)
        DEV_UUID=$(basename "$NIC_DEV")
        echo "$DEV_UUID" | sudo tee /sys/bus/vmbus/drivers/hv_netvsc/unbind
        echo "$DEV_UUID" | sudo tee /sys/bus/vmbus/drivers/uio_hv_generic/bind
        if [[ -z "$MAC_INFO" ]]; then
            MAC_INFO="mac=$MANA_MAC"
        else
            MAC_INFO="$MAC_INFO,mac=$MANA_MAC"
        fi
        # Set MANA interfaces DOWN before starting DPDK
        sudo ip link set "$SECONDARY" down
        VDEV_ARG="--vdev=$BUS_INFO,$MAC_INFO"
        echo "$VDEV_ARG" > ./vdev_arg
    done
fi

echo "Use $VDEV_ARG for l3fwd EAL argument"
# TODO: wrong command
((LAST_CORE=1))
QUEUE_CONFIG=""
for q in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do 
    if [[ -z "$QUEUE_CONFIG" ]]; then
        QUEUE_CONFIG="(2,$q,$LAST_CORE),(3,$q,$LAST_CORE)";
    else
        QUEUE_CONFIG="$QUEUE_CONFIG,(2,$q,$LAST_CORE),(3,$q,$LAST_CORE)";
    fi
    ((LAST_CORE=LAST_CORE+1))
done



# much fun figuring out these escaping rules
pushd "$DPDK_APP_PATH" || (echo "could not pushd"; exit 1)

echo "Running multiple queue fwd test, needs >= 32 cores"
echo "sudo timeout 1200 $DPDK_APP_EXEC --log-level eal,debug --log-level mana,debug --log-level netvsc,debug -l 1-17 $VDEV_ARG -- -p 0xC  --lookup=lpm --config='$QUEUE_CONFIG' --rule_ipv4=$DPDK_RULES_V4  --rule_ipv6=$DPDK_RULES_V6 --mode=poll --parse-ptype" > rerun_dpdk.log
sudo timeout 1200 $DPDK_APP_EXEC --log-level eal,debug --log-level mana,debug --log-level netvsc,debug -l 1-17 $VDEV_ARG -- -p 0xC  --lookup=lpm --config='$QUEUE_CONFIG' --rule_ipv4=$DPDK_RULES_V4  --rule_ipv6=$DPDK_RULES_V6 --mode=poll --parse-ptype


echo "Launched nohup: $?"
echo $(sudo cat ./nohup.out)
echo $(sudo cat $HOME/nohup.out)
echo $(sudo cat /root/nohup.out)
echo $(sudo cat $(pwd)/nohup.out)
echo "$(pwd)"
ls "$(pwd)/"
echo $(sudo find / -name nohup.out)
echo $(sudo find /tmp -name nohup.out)
echo $(sudo find /var -name nohup.out)
echo $(sudo pidof nohup)
popd || ( echo "could not popd"; exit 1)
exit 0