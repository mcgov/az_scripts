#! /bin/bash

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

export DEBIAN_FRONTEND=noninteractive
# install dependencies for building dpdk and rdma-core
sudo apt update
DEBIAN_FRONTEND=noninteractive sudo apt install -q -y build-essential cmake libudev-dev libnl-3-dev libnl-route-3-dev ninja-build pkg-config valgrind python3-dev cython3 python3-docutils pandoc libssl-dev libelf-dev python3-pip meson libnuma-dev libpcap-dev linux-modules-extra-azure
assert_success
pip3 install pyelftools
assert_success

# NOTE: this would be where you build and/or update the Linux kernel.
#       rdma-core and dpdk depend on kernel headers. 

# install rdma-core and dpdk
bash ./install-rdma-core.sh
assert_success
bash ./install-dpdk.ubuntu.sh
assert_success

# set required drivers to load automatically
echo 'ib_uverbs' | sudo tee -a /etc/modules
echo 'mana_ib' | sudo tee -a /etc/modules

# check for pci devices with ID:
#   vendor: Microsoft Corporation (1414)
#   class:  Ethernet Controller (0200)
#   device: Microsft Azure Network Adapter VF (00ba)
if [[ -n "`lspci -d 1414:00ba:0200`" ]]; then
    echo "MANA device is available."
    export USE_MANA=1
    echo "checking for existence of mana driver (might need to install kernel or linux-modules-extra)"
    sudo modprobe mana_ib
    assert_success
else
    echo "MANA was not detected."
fi

echo "Enabling hugepages (2MB)..."
for numa_hugepage in $(ls -1  /sys/devices/system/node/node*/hugepages/hugepages-2048kB/nr_hugepages); do
    echo 1024 | sudo tee $numa_hugepage
    assert_success
done

echo "Test setup is complete! Run ./pps-dpdk-testpmd-send.sh"