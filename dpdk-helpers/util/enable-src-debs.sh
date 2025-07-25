#! /bin/bash
# SPDX-License-Identifier: MIT
# author: Matthew G. McGovern : github.com/mcgov : matthew@mcgov.dev

source /etc/os-release

[[ "$ID" == ubuntu ]] || {
    echo "Error: $0 should be run on ubuntu systems only.";
    exit 1;
}

# enable repos for source debs 
# allows installation of dependencies with `apt build-dep`
if [[ -f /etc/apt/ubuntu.sources ]]; then
    # enable deb and deb-src in 24.04 ubuntu.sources file
    sudo sed -i 's/Types\: deb$/Types: deb deb-src/' /etc/apt/ubuntu.sources \
    || { echo "Failed to modify /etc/apt/ubuntu.sources"; exit 1; }
elif [[ -f /etc/apt/sources.list ]] || ! [[ -f /etc/apt/ubuntu.sources ]]; then
    # enable deb-src selectively in sources.list for the older ubuntu releases
    source /etc/os-release
    echo "deb-src http://azure.archive.ubuntu.com/ubuntu/ $UBUNTU_CODENAME main restricted" \
    | sudo tee -a /etc/apt/sources.list \
    || { echo "Failed to add deb-src line to /etc/apt/sources.list"; exit 1; }
    echo "deb-src http://azure.archive.ubuntu.com/ubuntu/ $UBUNTU_CODENAME-updates main restricted" \
    | sudo tee -a /etc/apt/sources.list \
    || { echo "Failed to add deb-src line to /etc/apt/sources.list"; exit 1; }
    # doing this selectively instead of enabling all deb-src lines
fi

# apt update to pick up the src-deb changes.
sudo DEBIAN_FRONTEND=noninteractive apt update -y \
|| { echo "Failed to update apt sources to enable build-deps"; exit 1; }

exit 0