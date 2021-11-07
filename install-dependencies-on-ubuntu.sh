#!/usr/bin/bash

# Install dependencies for harp_scale_trainer; the trainer itself needs not installation
# vut can rather be started from its directory

set -v

# this script may be tested in a container
docker run -it -v $HOME/harp_scale_trainer:/root/harp_scale_trainer ubuntu bash

# install packages one after the other to what they install as dependencies
apt-get install --no-install-recommends -y sudo
sudo apt-get install --no-install-recommends -y wget
sudo apt-get install --no-install-recommends -y ruby
sudo apt-get install --no-install-recommends -y figlet
sudo apt-get install --no-install-recommends -y alsa-utils
sudo apt-get install --no-install-recommends -y aubio-tools
sudo apt-get install --no-install-recommends -y sox
sudo apt-get install --no-install-recommends -y gnuplot-nox
sudo apt-get install --no-install-recommends -y gcc
sudo apt-get install --no-install-recommends -y make
sudo apt-get install --no-install-recommends -y less
sudo apt-get install --no-install-recommends -y ruby-dev
sudo apt-get install --no-install-recommends -y libffi-dev
sudo gem install sys-proctable

# invoke as a test
./harp_scale_trainer
