#! /bin/bash
# SPDX-License-Identifier: MIT
# author: Matthew G. McGovern : github.com/mcgov : matthew@mcgov.dev

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
"$SCRIPT_DIR"/enable-src-debs.sh \
&& DEBIAN_FRONTEND=noninteractive sudo apt-get build-dep -y dpdk-dev rdma-core \
&& DEBIAN_FRONTEND=noninteractive sudo apt install -y linux-modules-extra-azure python3-pyelftools \
|| {
    echo "An error occurred while installing DPDK/rdma-core build dependencies."
    exit 1;
}
exit 0