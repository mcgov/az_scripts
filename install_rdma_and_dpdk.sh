#! /bin/bash

# Script to install dependencies and setup an Azure VM with MANA for DPDK
# requires a MANA compatible kernel, rdma-core, and dpdk
# This script is for ubuntu server 22.04 and RHEL >= 8.4
# Assumes ubuntu 22.04 using 6.2 kernel.

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

# NOTE for ubuntu 22.04:
# linux-azure and linux-modules-extra-azure installs 6.2
# for 5.15.0-1045 use linux-azure-lts-22.04 and linux-modules-extra-azure-22.04
# 6.2 doesn't require anything special other than rdma-core >=v44 and dpdk > 22.11
# 5.15.0-1045 has MANA backported but not ERDMA from rdma-core v43
# this throws off the driver_id fields and requires some tinkering for now (fix coming soon)
# note the special steps in the rdma-core installation path below.
# TLDR use 6.2 kernel in linux-azure and linux-modules-extra-azure

# hackey os detection, not for production.
# tested on 22.04 and RHEL 8.6/9.2
if [[ -n `which apt` ]]; then
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -q -y build-essential cmake libudev-dev \
    libnl-3-dev libnl-route-3-dev ninja-build pkg-config \
    valgrind python3-dev cython3 python3-docutils pandoc \
    flex bison libssl-dev \
    libelf-dev python3-pip meson dwarves libnuma-dev libpcap-dev \
    linux-azure linux-modules-extra-azure
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
else
    echo "unsupported os, exiting..."
    exit -1;
fi


# build/install rdma-core 46
# rdma-core installation from source YMMV
if [[ -z "$SKIP_RDMA_INSTALL" ]]; then
    wget https://github.com/linux-rdma/rdma-core/releases/download/v46.0/rdma-core-46.0.tar.gz
    assert_success
    tar xzvf rdma-core-46.0.tar.gz
    assert_success
    pushd rdma-core-46.0/
    assert_success
    cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
    assert_success
    sudo make -j 28
    assert_success
    sudo make install
    assert_success
    popd 
fi

if [[ -z "$DPDK_GIT_SOURCE" ]]; then
    DPDK_GIT_SOURCE="https://github.com/DPDK/dpdk.git"
fi;
if [[ -z "$DPDK_GIT_REF" ]]; then
    DPDK_GIT_REF="v23.07"
fi

if [[ -z "$SKIP_DPDK_INSTALL" ]]; then
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
fi
## run manually to genericize if creating an azure sig image
# sudo -s
# waagent deprovision+user 
#### asks for 'y' ^
# shutdown now
