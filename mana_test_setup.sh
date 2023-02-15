#! /bin/bash
sudo apt update
sudo apt-get install -y git tar meson cmake gcc libudev-dev libnl-3-dev libnl-route-3-dev ninja-build pkg-config valgrind python3-dev cython3 python3-docutils pandoc build-essential flex bison libssl-dev unzip libelf-dev python3-pip
pip3 install pyelftools


# Build/install 6.2-rc2
#git clone  https://github.com/longlimsft/linux.git
#https://github.com/torvalds/linux.git

# or use longs rdma-fix branch for now
git clone --branch rdma-fix https://github.com/longlimsft/linux.git
pushd linux

#wget https://github.com/longlimsft/linux/archive/refs/heads/rdma-fix.zip
#unzip rdma-fix.zip
#pushd linux-rdma-fix

#git checkout v6.2-rc2
yes "" | make oldconfig
sed -i 's/CONFIG_SYSTEM_REVOCATION_LIST/#CONFIG_SYSTEM_REVOCATION_LIST/g' .config
sed -i 's/CONFIG_SYSTEM_TRUSTED_KEYS/#CONFIG_SYSTEM_TRUSTED_KEYS/g' .config
sed -i 's/# CONFIG_MANA_INFINIBAND is not set/CONFIG_MANA_INFINIBAND=m/g' .config
yes "" | make -j 12
sudo make modules_install
sudo make install
popd

# build/install rdma-core 44
wget https://github.com/linux-rdma/rdma-core/releases/download/v44.0/rdma-core-44.0.tar.gz
tar xzvf rdma-core-44.0.tar.gz
pushd rdma-core-44.0/
cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
sudo make -j 12
sudo make install
popd 


# build / install dpdk 22.11  (already will be in lisa working dir)
git clone https://github.com/DPDK/dpdk.git
pushd dpdk
sed -i "s/'af_packet',/'af_packet',\n        'mana',/g" drivers/net/meson.build
meson  build 
cd build
ninja
sudo ninja install
popd

echo 'ib_uverbs' | sudo tee -a /etc/modules
echo 'mana_ib' | sudo tee -a /etc/modules
echo 'mana' | sudo tee -a /etc/modules

sudo reboot

# NOTE: commands to setup and test DPDK

# setup hugepages, set eth1 down, and run dpdk
ip link set eth1 down
echo '1024' | sudo tee  /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
echo '1' | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages

# NOTE: dpdk mana pmd requires these libs to be loaded

ADDRESS=$(readlink /sys/class/net/eth1/lower_*/device)
ADDRESS=$(basename ${ADDRESS})
sudo dpdk-testpmd -l 2,3 -n 4 --proc-type=primary --vdev="$ADDRESS" -a "${ADDRESS}" -- --forward-mode=txonly -a --stats 1 --port-topology=chained --txd=64 --rxd=64 --txq=1 --rxq=1
