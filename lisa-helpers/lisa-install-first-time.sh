#! /bin/bash

# install LISA on a device. Should work on WSL and elsewhere.
sudo apt-get update -y
# lots of annoying dependencies if you're on WSL
sudo apt-get -y install pkg-config python3 python3-pip libcairo-dev libgirepository1.0-dev libvirt-dev
# install the python pkgs we need to bootstrap
pip install nox toml pycairo

# beware the example-code curl > sudo bash install.
# do it the good way irl.
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt

if ! command -v az;
then
    ./install_az_cli.ubuntu.sh
    assert_success
fi
# check out lisa
git clone https://github.com/microsoft/lisa.git
assert_success
pushd lisa || (echo "pushd lisa failed??" ; exit 1)
# create a .venv for LISA and install the required packages into it
    python3 -m nox -vs dev
    assert_success
    echo "Congrats! LISA is installed. Activating the development .venv in this shell..."
    echo "NOTE: to activate the .venv in the future, run 'source .venv/bin/activate' from the LISA root dir."
# activate the .venv, now `lisa` will be in your path
    assert_success
popd || ( echo "popd failed??"; exit 1)
exit 0
