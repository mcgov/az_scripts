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

if [ -z "$DPDK_GIT_SOURCE" ]; then
    DPDK_GIT_SOURCE="https://github.com/DPDK/dpdk.git"
fi;
if [ -z "$DPDK_GIT_REF" ]; then
    DPDK_GIT_REF="v23.11"
fi
git clone $DPDK_GIT_SOURCE
assert_success
pushd dpdk
git checkout $DPDK_GIT_REF
meson setup -Dexamples=l3fwd -Denable_drivers=net/mana,*/mlx*,bux/vmbus,net/*netvsc,net/ring,net/virtio,net/bonding,bus/auxiliary,common/* -Denable_apps=app/test-pmd build
assert_success
cd build
ninja
assert_success
sudo ninja install
assert_success
popd

exit 0