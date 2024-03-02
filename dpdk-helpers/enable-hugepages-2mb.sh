#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit -1
    fi
}

echo "Enabling hugepages (2MB)..."
for numa_hugepage in $(ls -1  /sys/devices/system/node/node*/hugepages/hugepages-2048kB/nr_hugepages); do
    HUGEPAGES="`cat $numa_hugepage`"
    if [[ $HUGEPAGES == 1024 ]]; then
        echo "$numa_hugepage is already set to 1024."
    else
        echo "Setting $numa_hugepage to 1024..."
        echo 1024 | sudo tee $numa_hugepage
        assert_success
    fi
done