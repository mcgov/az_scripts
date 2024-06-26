#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit 1
    fi
}

function check_and_append {
    #check that it's set
    #append if it wasn't present
    if ! grep "$2" < "$1" ; then
        echo "$2" >> "$1"
    fi;
}
export DEBIAN_FRONTEND=noninteractive

# install dependencies for building dpdk and rdma-core

if [[ "$1" == "--use-package-manager"  ]]; then
    sudo apt update
    DEBIAN_FRONTEND=noninteractive sudo apt install -y -q dpdk rdma-core linux-modules-extra-azure
elif [[ "$1" == "--help" ]]; then
    cat ./.print-usage-note.txt
    exit 0
else
    sudo apt update
    ./util/run-dpdk-rdma-source-install.sh
fi

# set required drivers to load automatically
echo 'ib_uverbs' | sudo tee -a /etc/modules
echo 'mana_ib' | sudo tee -a /etc/modules

# check for pci devices with ID:
#   vendor: Microsoft Corporation (1414)
#   class:  Ethernet Controller (0200)
#   device: Microsft Azure Network Adapter VF (00ba)
if lspci -d 1414:00ba:0200; then
    echo "MANA device is available."
    export USE_MANA=1
    echo "checking for existence of mana driver (might need to install kernel or linux-modules-extra)"
    if !  sudo modprobe mana_ib; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y linux-modules-extra-azure
    fi
    sudo modprobe mana_ib
    assert_success
    
else
    echo "MANA was not detected."
fi

./util/enable-hugepages-2mb.sh

echo "Test setup is complete! Run ./run-pps-dpdk-testpmd.sh"