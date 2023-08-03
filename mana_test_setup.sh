#! /bin/bash

# Script to install dependencies and setup an Azure VM with MANA for DPDK
# requires a MANA compatible kernel, rdma-core, and dpdk
# This script is for ubuntu server 22.04

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
sudo apt update
DEBIAN_FRONTEND=noninteractive sudo apt-get install -q -y build-essential cmake libudev-dev \
libnl-3-dev libnl-route-3-dev ninja-build pkg-config \
valgrind python3-dev cython3 python3-docutils pandoc \
flex bison libssl-dev \
libelf-dev python3-pip meson dwarves libnuma-dev libpcap-dev
assert_success

pip3 install pyelftools

# pick Linux repo and tag to build, 6.4 release has all the vpci and mana bits.
if [ -z "$LINUIX_GIT_SOURCE" ]; then
    LINUIX_GIT_SOURCE="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
fi
if [ -z "$LINUX_GIT_REFERENCE" ]; then
    LINUX_GIT_REFERENCE="v6.4"
fi

# Build/install Linux kernel
git clone $LINUIX_GIT_SOURCE -b $LINUX_GIT_REFERENCE --depth 1
assert_success
pushd linux
#git checkout v6.2-rc2
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

# build/install rdma-core 44
wget https://github.com/linux-rdma/rdma-core/releases/download/v46.0/rdma-core-46.0.tar.gz
assert_success
tar xzvf rdma-core-46.0.tar.gz
assert_success
pushd rdma-core-46.0/
assert_success
# cursed not-for-production rdma-core installation from source YMMV
cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
assert_success
sudo make -j 28
assert_success
sudo make install
assert_success
popd 

if [ -z "$DPDK_GIT_SOURCE" ]; then
    DPDK_GIT_SOURCE="https://github.com/DPDK/dpdk.git"
fi;
if [ -z "$DPDK_GIT_REF" ]; then
    DPDK_GIT_REF="v23.07-rc3"
fi
# build / install dpdk 22.11  (already will be in lisa working dir)
git clone $DPDK_GIT_SOURCE
assert_success
pushd dpdk
git checkout $DPDK_GIT_REF
assert_success
meson build -Dexamples=l3fwd
assert_success

cd build
ninja
assert_success
sudo ninja install
assert_success
popd

echo 'ib_uverbs' | sudo tee -a /etc/modules
echo 'mana_ib' | sudo tee -a /etc/modules

echo "SETUP AND BUILD COMPLETE"

## run manually to genericize if creating an azure sig image
# sudo -s
# waagent deprovision+user 
#### asks for 'y' ^
# shutdown now
