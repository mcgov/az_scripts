#! /bin/bash

# some utility functions first
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
if [[ -z "`which apt`" ]];  then
  echo "This script only supports Ubuntu 22.04"
  exit 1
fi
# print usage info if no vars are set
if [[ -z "$INSTALL_LINUX_KERNEL" ]] \
&& [[ -z "$INSTALL_RDMA_CORE" ]] \
&& [[ -z "$INSTALL_DPDK" ]] \
&& [[ -z "$RUN_DPDK_QUICK_TEST" ]]; then
    echo 'usage: [ENV_VARS] ./run_mana_setup.sh'
    echo 'ENV_VARS: '
    echo 'INSTALL_LINUX_KERNEL=1'
    echo '- build and install 6.2 kernel for Ubuntu 22.04 (not needed in most cases)'
    echo ''
    echo 'INSTALL_DPDK=1 '
    echo '- build and install DPDK.'
    echo ' DPDK_GIT_SOURCE='...''
    echo ' - Set DPDK git tree to clone'
    echo ' DPDK_GIT_REF='...''
    echo ' - Set branch to use during DPDK build.'
    echo ''
    echo 'INSTALL_RDMA_CORE=1'
    echo ' - build and install rdma-core v46 from source'
    echo ''
    echo 'RUN_DPDK_QUICK_TEST=1'
    echo '- setup netvsc pmd and run dpdk quick test.'
    echo 'note: restart between tests if attempting to run netvsc and failsafe pmd tests.'
    echo '    This script runs the netvsc version, the recommended version for MANA.'
    echo '    see https://learn.microsoft.com/en-us/azure/virtual-network/setup-dpdk-mana'
    echo '    for more information.'
    exit 0
fi

# install dependencies for ubuntuserver 22.04
if [[ -v INSTALL_LINUX_KERNEL ]] \
|| [[ -v INSTALL_RDMA_CORE ]] \
|| [[ -v INSTALL_DPDK ]]; then
    sudo apt update
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -q -y build-essential cmake libudev-dev \
    libnl-3-dev libnl-route-3-dev ninja-build pkg-config \
    valgrind python3-dev cython3 python3-docutils pandoc \
    flex bison libssl-dev \
    libelf-dev python3-pip meson dwarves libnuma-dev libpcap-dev
    assert_success
    pip3 install pyelftools
fi

# Build/install Linux kernel
if [[ -v INSTALL_LINUX_KERNEL ]]; then
    # pick Linux repo and tag to build, 6.4 release has all the vpci and mana bits.
    if [ -z "$LINUIX_GIT_SOURCE" ]; then
        LINUIX_GIT_SOURCE="https://git.launchpad.net/~canonical-kernel/ubuntu/+source/linux-azure/+git/jammy"
    fi
    if [ -z "$LINUX_GIT_REFERENCE" ]; then
        LINUX_GIT_REFERENCE="Ubuntu-azure-6.2-6.2.0-1014.14_22.04.1"
    fi
    git clone $LINUIX_GIT_SOURCE -b $LINUX_GIT_REFERENCE --depth 1
    assert_success
    pushd linux
    yes "" | make oldconfig
    assert_success
    sed -i 's/CONFIG_SYSTEM_REVOCATION_LIST/#CONFIG_SYSTEM_REVOCATION_LIST/g' .config
    sed -i 's/CONFIG_SYSTEM_TRUSTED_KEYS/#CONFIG_SYSTEM_TRUSTED_KEYS/g' .config
    sed -i 's/# CONFIG_MANA_INFINIBAND is not set/CONFIG_MANA_INFINIBAND=m/g' .config
    #check that it's set
    check_and_append .config 'CONFIG_MANA_INFINIBAND=m'
    # build it
    yes "" | make -j 12
    assert_success
    sudo make modules_install
    assert_success
    sudo make install
    assert_success
    popd
fi

# build/install rdma-core 46
if [[ -v INSTALL_RDMA_CORE ]]; then
    wget https://github.com/linux-rdma/rdma-core/releases/download/v46.0/rdma-core-46.0.tar.gz
    tar xzvf rdma-core-46.0.tar.gz
    pushd rdma-core-46.0/
    cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
    sudo make -j 28
    sudo make install
    popd
fi

# build / install dpdk 22.11  (already will be in lisa working dir)
if [[ -v INSTALL_DPDK ]]; then
    if [ -z "$DPDK_GIT_SOURCE" ]; then
        DPDK_GIT_SOURCE="https://github.com/DPDK/dpdk.git"
    fi;
    if [ -z "$DPDK_GIT_REF" ]; then
        DPDK_GIT_REF="v23.07-rc3"
    fi
    git clone $DPDK_GIT_SOURCE
    assert_success
    pushd dpdk
    git checkout $DPDK_GIT_REF
    meson build -Dexamples=l3fwd
    assert_success
    cd build
    ninja
    assert_success
    sudo ninja install
    assert_success
    popd
fi
# make modules reload on boot
if [[ -v INSTALL_RDMA_CORE ]]; then
    echo 'ib_uverbs' | sudo tee -a /etc/modules
fi

if [[ -v INSTALL_LINUX_KERNEL ]]; then
    echo 'mana_ib' | sudo tee -a /etc/modules
fi

# proclaim success
if [[ -v INSTALL_LINUX_KERNEL ]] \
|| [[ -v INSTALL_RDMA_CORE ]] \
|| [[ -v INSTALL_DPDK ]]; then
    echo "SETUP AND BUILD COMPLETE"
fi

# check for pci devices with ID:
#   vendor: Microsoft Corporation (1414)
#   class:  Ethernet Controller (0200)
#   device: Microsft Azure Network Adapter VF (00ba)
if [[ -n "`lspci -d 1414:00ba:0200`" ]]; then
    echo "MANA device is available."
    USE_MANA=1
else
    echo "MANA was not detected."
fi

# run a dpdk test
if [[ -v RUN_DPDK_QUICK_TEST ]]; then
    # Enable 2MB hugepages.
    echo "Enabling hugepages (2MB)..."
    echo 1024 | sudo tee /sys/devices/system/node/node*/hugepages/hugepages-2048kB/nr_hugepages
    
    if [[ -z "$BUS_INFO" ]] || [[ -z "$MANA_MAC" ]]; then
        # Assuming use of eth1 for DPDK in this demo
        PRIMARY="eth1"
        # $ ip -br link show master eth1 
        # > enP30832p0s0     UP             f0:0d:3a:ec:b4:0a <... # truncated
        # grab interface name for device bound to primary
        SECONDARY="`ip -br link show master $PRIMARY | awk '{ print $1 }'`"
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
        if [[ -z "`lsmod | grep uio_hv_generic`" ]]; then
            DEV_UUID=$(basename $(readlink /sys/class/net/$PRIMARY/device))
            NET_UUID="f8615163-df3e-46c5-913f-f2d2f965ed0e"
            sudo modprobe uio_hv_generic
            echo $NET_UUID > /sys/bus/vmbus/drivers/uio_hv_generic/new_id
            echo $DEV_UUID > /sys/bus/vmbus/drivers/hv_netvsc/unbind
            echo $DEV_UUID > /sys/bus/vmbus/drivers/uio_hv_generic/bind
        fi
    fi
    if [[ -v USE_MANA ]]; then
        VDEV_ARG="--vdev=$BUS_INFO,mac=$MANA_MAC"
    else
        VDEV_ARG="--vdev=$BUS_INFO"
    fi
    echo "running single queue test, needs 2 cores"
    echo sudo dpdk-testpmd -l 1-3 $VDEV_ARG -- --forward-mode=txonly --auto-start --txd=128 --rxd=128 --stats 2
    # MANA single queue test
    sudo timeout -s INT  10  dpdk-testpmd -l 1-3 $VDEV_ARG -- --forward-mode=txonly --auto-start --txd=128 --rxd=128 --stats 2
    
    sleep 2
    echo "Running multiple queue test, needs >= 8 cores"
    echo sudo dpdk-testpmd -l 1-9 $VDEV_ARG -- --forward-mode=txonly --auto-start --nb-cores=8  --txd=128 --rxd=128 --txq=4 --rxq=4 --stats 2
    # MANA multiple queue test (example assumes > 9 cores)
    sudo timeout -s INT 10 dpdk-testpmd -l 1-9 $VDEV_ARG -- --forward-mode=txonly --auto-start --nb-cores=8  --txd=128 --rxd=128 --txq=4 --rxq=4 --stats 2
fi
## run manually before creating a sig image
# sudo -s
# waagent deprovision+user 
#### asks for 'y' ^
# shutdown now
