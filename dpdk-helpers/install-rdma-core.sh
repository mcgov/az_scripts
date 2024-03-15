#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit 1
    fi
}

function check_and_append {
    #check that it's set
    #append if it wasn't present
    if ! grep "$2" < "$1" ; then
        echo "$2" >> "$1"
    fi;
}

if [[ -z "$RDMA_CORE_VERSION" ]]; then
    RDMA_CORE_VERSION="49.1"
fi
wget "https://github.com/linux-rdma/rdma-core/releases/download/v$RDMA_CORE_VERSION/rdma-core-$RDMA_CORE_VERSION.tar.gz"
assert_success
tar xzvf "rdma-core-$RDMA_CORE_VERSION.tar.gz"
assert_success
pushd "rdma-core-$RDMA_CORE_VERSION/" || ( echo "push rdma-core-$RDMA_CORE_VERSION/ failed: $?"; exit 1)
assert_success
cmake -DIN_PLACE=0 -DNO_MAN_PAGES=1 -DCMAKE_INSTALL_PREFIX=/usr
assert_success
sudo make -j 28
assert_success
sudo make install
assert_success
popd || ( echo "popd failed: $?"; exit 1 )

exit 0