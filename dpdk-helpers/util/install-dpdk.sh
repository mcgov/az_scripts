#! /bin/bash
# SPDX-License-Identifier: MIT
# author: Matthew G. McGovern : github.com/mcgov : matthew@mcgov.dev

[[ "$1" == "--help" ]] && cat << EOF
Usage: $0
NOTES: 
    Run this in the DPDK source directory.
EOF

# build dpdk with max_lcores bumped to 192 cores for E192ids_v6.
# skipping this build option with cause weird cursed failures at runtime.
# feel free to create a bash array of other DPDK build args before running this to add other args.
meson setup -Dmax_lcores=192 "${BUILD_TYPE_ARG[@]}" "${DPDK_BUILD_ARGS[@]}" build \
|| { echo  "meson setup failed!"; exit 1; }

cd build \
|| { echo "cd build failed: $?"; exit 1; }

ninja \
|| { echo "ninja build failed!"; exit 1; }

sudo ninja install \
|| { echo "ninja install failed!"; exit 1; }

exit 0