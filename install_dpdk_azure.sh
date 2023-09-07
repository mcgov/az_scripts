#! /bin/bash

source ./common.sh

# build / install dpdk from source on ubuntu 22.04

if [[ -z "$DPDK_GIT_SOURCE" ]]; then
    DPDK_GIT_SOURCE="https://github.com/DPDK/dpdk.git"
fi;
if [[ -z "$DPDK_GIT_REF" ]]; then
    DPDK_GIT_REF="v23.07-rc3"
fi
DEBIAN_FRONTEND=noninteractive sudo apt update
DEBIAN_FRONTEND=noninteractive sudo apt-get install -q -y build-essential cmake libudev-dev \
libnl-3-dev libnl-route-3-dev ninja-build pkg-config \
valgrind python3-dev cython3 python3-docutils pandoc \
libssl-dev libelf-dev python3-pip meson libnuma-dev libpcap-dev
assert_success
    
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
