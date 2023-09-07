#! /bin/bash
# Ubuntu 22.04 5.15.0 versions with backported MANA changes did not backport the ERDMA driver.
# Since ERDMA was added in rdma-core v43 and MANA was added in v44, the driver_id field does
# not match up when building rdma-core from source.

# This script is a cursed hack to test DPDK on MANA machines.

# download rdma-core 46
wget https://github.com/linux-rdma/rdma-core/releases/download/v46.0/rdma-core-46.0.tar.gz
assert_success
tar xzvf rdma-core-46.0.tar.gz
assert_success
pushd rdma-core-46.0/
assert_success

# cursed hackey non-fix, just swap the IDs in the enum so the kernel header matches the
# one in the backported kernel when ERDMA is not present.
if [[ -n "$APPLY_UBUNTU_BACKPORT_KERNEL_HACK" ]]; then
    sed -i 's/RDMA_DRIVER_ERDMA/RDMA-DRIVER-MANA/g' ./kernel-headers/rdma/ib_user_ioctl_verbs.h
    sed -i 's/RDMA_DRIVER_MANA/RDMA_DRIVER_ERDMA/g' ./kernel-headers/rdma/ib_user_ioctl_verbs.h
    sed -i 's/RDMA-DRIVER-MANA/RDMA_DRIVER_MANA/g' ./kernel-headers/rdma/ib_user_ioctl_verbs.h
fi
# build and install
cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
assert_success
sudo make -j 28
assert_success
sudo make install
assert_success
popd 

echo "RDMA v46 with swapped driver_id field is installed. Ensure older versions of rdma-core are uninstalled. You may need to rebuild DPDK."
