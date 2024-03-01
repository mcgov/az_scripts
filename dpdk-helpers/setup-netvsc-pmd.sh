#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        ./display-maintainer-info.sh
        exit -1
    fi
}

PRIMARY=$1

# $ ip -br link show master eth1 
# > enP30832p0s0     UP             f0:0d:3a:ec:b4:0a <... # truncated
# grab interface name for device bound to primary
echo "Checking for lower interface for $PRIMARY..."
if [[ -e "/sys/class/net/$PRIMARY" ]]; then
    echo "$PRIMARY interface found! proceeding..."
else
    echo "$PRIMARY interface not found in sysfs, check interface name."
    echo "If this is a re-run without rebooting, use the ./rerun-dpdk-testpmd"
    echo "If this is a re-run after a reboot, use pps-dpdk-testpmd.sh"
    echo "If you already did do that, this script is broken."
    ./display-maintainer-info.sh
    exit -1
fi
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
VDEV_ARG_FILE="$PRIMARY.dpdk-eal-vdev.arg"
VF_NOTE_FILE="$PRIMARY.lower.nic"
echo "Writing argument to $VDEV_ARG_FILE..."
echo $VDEV_ARG | tee ./$VDEV_ARG_FILE
echo "Writing association file to $VF_NOTE_FILE"
echo $SECONDARY | tee ./$VF_NOTE_FILE
echo "Setup complete! w00t"