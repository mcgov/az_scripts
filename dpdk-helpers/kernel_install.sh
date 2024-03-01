#! /bin/bash

# Script to install dependencies and setup an Azure VM with MANA for DPDK
# requires a MANA compatible kernel, rdma-core, and dpdk
# This script is for ubuntu server 22.04 and RHEL >= 8.4

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

echo "STOP: did you update the kernel to latest? for ubuntu install and upgrade:"
echo "linux-azure linux-modules-extra-azure"
sleep 10

# NOTE for ubuntu 22.04:
# linux-azure and linux-modules-extra-azure installs 6.2
# for 5.15.0-1045 use linux-azure-lts-22.04 and linux-modules-extra-azure-22.04
# 6.2 doesn't require anything special other than rdma-core >=v44 and dpdk > 22.11
# 5.15.0-1045 has MANA backported but not ERDMA from rdma-core v43
# this throws off the driver_id fields and requires some tinkering for now.
# note the special steps in the rdma-core installation path below.

# hackey os detection, not for production.
# tested on 22.04 and RHEL 8.6/9.2
if [[ -n `which apt` ]]; then
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -q -y \
    build-essential cmake libudev-dev \
    libnl-3-dev libnl-route-3-dev pkg-config \
    valgrind python3-dev cython3 python3-docutils pandoc \
    flex bison libssl-dev \
    libelf-dev python3-pip dwarves libnuma-dev libpcap-dev
    assert_success
elif [[ -n `which yum` ]]; then
    sudo yum update
    sudo yum -y groupinstall "Development Tools"
    sudo yum install -y cmake gcc libudev-devel \
     libnl3-devel pkg-config \
     valgrind python3-devel python3-docutils \
     flex bison openssl-devel unzip dwarves \
     elfutils-devel python3-pip meson dwarves libpcap-devel \
     tar wget dos2unix psmisc kernel-devel-$(uname -r) \
     librdmacm-devel libmnl-devel kernel-modules-extra numactl-devel \
     kernel-headers elfutils-libelf-devel meson ninja-build libbpf-devel
     assert_success
else
    echo "unsupported os, exiting..."
    exit -1;
fi

pip3 install pyelftools

# pick Linux repo and tag to build, 6.4 release has all the vpci and mana bits.
if [[ -z "$LINUIX_GIT_SOURCE" ]]; then
    LINUIX_GIT_SOURCE="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
fi
if [[ -z "$LINUX_GIT_REFERENCE" ]]; then
    LINUX_GIT_REFERENCE="v6.4"
fi

# Build/install Linux kernel
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

# build it and hope `make -j` doesn't kill your ssh
yes "" | make -j
assert_success
sudo make modules_install
assert_success
sudo make install
assert_success
popd


## NOTE: run manually to genericize if creating an azure sig image
# sudo -s
# NOTE: sudo -s first so you can shutdown after. Your user gets wiped during deprovisioning
# waagent deprovision+user 
#### asks for 'y' ^
# shutdown now
