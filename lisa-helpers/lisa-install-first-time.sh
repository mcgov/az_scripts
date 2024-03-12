sudo apt-get update -y
# lots of annoying dependencies if you're on WSL
sudo apt-get install pkg-config python3 python3-pip libcairo-dev libgirepository1.0-dev libvirt-dev -y
# install the python pkgs we need to bootstrap
pip install nox toml pycairo

# do the shitty az-cli curl->root install lol
# you can do the good way if you want: 
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# check out lisa
git clone https://github.com/microsoft/lisa.git
pushd lisa
# create a .venv for LISA and install the required packages into it
python3 -m nox -vs dev

echo "Congrats! LISA is installed. Activating the development .venv in this shell..."
echo 'NOTE: to activate the .venv in the future, run `source .venv/bin/activate` from the LISA root dir.'
# activate the .venv, now `lisa` will be in your path
source .venv/bin/activate
popd