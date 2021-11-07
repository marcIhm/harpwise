#!/usr/bin/bash

# Install dependencies for harp_scale_trainer; the trainer itself needs not installation
# vut can rather be started from its directory

set -v

# this script may be tested in a container
docker run -it -v $HOME/harp_scale_trainer:/root/harp_scale_trainer ubuntu bash

# install packages one after the other to what they install as dependencies
sudo apt-get install -y wget
sudo apt-get install -y ruby
sudo apt-get install -y figlet
sudo apt-get install -y alsa-utils
sudo apt-get install -y aubio-tools
sudo apt-get install -y sox
sudo apt-get install -y gnuplot-nox
sudo apt-get install -y gcc
sudo apt-get install -y make
sudo apt-get install -y less
sudo apt-get install -y ruby-dev
sudo apt-get install -y libffi
sudo apt-get install -y libffi-dev
sudo gem install sys-proctable
cp /var/lib/gems/2.7.0/extensions/x86_64-linux/2.7.0/ffi-1.15.4/mkmf.log .

# invoke as a test
./harp_scale_trainer
