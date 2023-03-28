#! /bin/bash

#"marketplace_image:canonical 0001-com-ubuntu-server-jammy 22_04-lts latest"

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
# install dependencies for ubuntuserver 22.04
sudo apt update
DEBIAN_FRONTEND=noninteractive sudo apt-get install -q -y build-essential cmake gcc libudev-dev \
libnl-3-dev libnl-route-3-dev ninja-build pkg-config \
valgrind python3-dev cython3 python3-docutils pandoc \
build-essential flex bison libssl-dev unzip \
libelf-dev python3-pip meson dwarves

assert_success

pip3 install pyelftools
if [ -z "$GIT_SOURCE" ]; then
    GIT_SOURCE="https://github.com/longlimsft/linux.git"
fi
if [ -z "$GIT_REFERENCE" ]; then
    GIT_REFERENCE="rdma-fix"
fi
# Build/install 6.2-rc2
git clone $GIT_SOURCE -b $GIT_REFERENCE --depth 1
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
#build it
yes "" | make -j 12
assert_success
sudo make modules_install
assert_success
sudo make install
assert_success
popd

# build/install rdma-core 44
wget https://github.com/linux-rdma/rdma-core/releases/download/v44.0/rdma-core-44.0.tar.gz
assert_success
tar xzvf rdma-core-44.0.tar.gz
assert_success
pushd rdma-core-44.0/
assert_success
cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
assert_success
sudo make -j 12
assert_success
sudo make install
assert_success
popd 

if [ -z "$DPDK_GIT_SOURCE" ]; then
    DPDK_GIT_SOURCE="https://github.com/longlimsft/dpdk.git"
fi;
if [ -z "$DPDK_GIT_REF" ]; then
    DPDK_GIT_REF="longli/submit_patch_cpu_cycles"
fi
# build / install dpdk 22.11  (already will be in lisa working dir)
git clone $DPDK_GIT_SOURCE
assert_success
pushd dpdk
git checkout $DPDK_GIT_REF
assert_success

# # uncomment for dpdk branches that don't have mana enabled. 
# # Long's already have it, upstream might not.
# sed -i "s/'af_packet',/'af_packet',\n        'mana',/g" drivers/net/meson.build

meson build 
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
yes 'y' | sudo waagent deprovision+user
# $disks =  az disk list --resource-group $rg | ConvertFrom-Json
# az sig image-version list-shared 
# az sig image-version create --resource-group $rg --gallery-name $gallery --gallery-image-definition $image --gallery-image-version $version --os-snapshot $disks[0].id
