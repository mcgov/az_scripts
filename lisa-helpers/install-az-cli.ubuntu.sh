#! /bin/bash

function assert_success {
    if [ $? -ne 0 ]; then
        echo "Last call failed! Exiting..."
        exit 1
    fi
}
# install azcli according to instructions at:
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
# exit code asserting added.

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
sudo mkdir -p /etc/apt/keyrings
MSFT_KEY_ARMORED=$(curl -sLS https://packages.microsoft.com/keys/microsoft.asc)
assert_success
MSFT_KEY_DEARMORED=$( echo "$MSFT_KEY_ARMORED" | gpg --dearmor)
assert_success
echo "$MSFT_KEY_DEARMORED" | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
assert_success
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
assert_success

GET_DIST=$(lsb_release -cs)
assert_success
GET_ARCH=$(dpkg --print-architecture)
assert_success
echo "deb [arch=$GET_ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $GET_DIST main" |
    sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
assert_success
sudo apt-get update
assert_success
sudo apt-get install azure-cli
assert_success
exit 0;