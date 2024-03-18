#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit 1
    fi
}

DEBIAN_FRONTEND=noninteractive sudo apt install -q -y build-essential cmake libudev-dev libnl-3-dev libnl-route-3-dev ninja-build pkg-config valgrind python3-dev cython3 python3-docutils pandoc libssl-dev libelf-dev python3-pip meson libnuma-dev libpcap-dev linux-modules-extra-azure
assert_success
pip3 install pyelftools
assert_success

# NOTE: this would be where you build and/or update the Linux kernel.
#       rdma-core and dpdk depend on kernel headers. 

# install rdma-core and dpdk
./util/install-rdma-core.sh
assert_success
./util/install-dpdk.ubuntu.sh
assert_success
exit 0;
