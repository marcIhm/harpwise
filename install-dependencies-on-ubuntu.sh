#!/usr/bin/bash

# Install dependencies for harp_scale_trainer; the trainer itself needs not installation
# but can rather be started from its directory.
# See tests/installer for a way to test this script in a container

set -v


# install packages one after the other to what they install as dependencies
sudo apt-get install -y wget
sudo apt-get install -y ruby
sudo apt-get install -y figlet
sudo apt-get install -y alsa-utils
sudo echo "Europe/Zurich" > /etc/timezone 
#sudo apt-get install dialog apt-utils
#echo "tzdata    tzdata/Areas    select  Europe" | sudo debconf-set-selections
#echo "tzdata    tzdata/Zones/Europe select  Berlin" | sudo debconf-set-selections
sudo apt-get install --no-install-recommends -y aubio-tools
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
