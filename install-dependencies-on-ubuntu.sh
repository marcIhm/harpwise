#!/usr/bin/bash

# Install dependencies for harp_scale_trainer; the trainer itself needs no installation
# but should rather be started directly from its directory.
# See tests/installer for a way to test this script in a container

set -v

# install packages one after the other to what they install as dependencies
sudo apt-get install -y wget
sudo apt-get install -y ruby
sudo apt-get install -y figlet
sudo apt-get install -y alsa-utils
# The option --preserve-end below is needed to test this script within a container
sudo --preserve-env=DEBIAN_FRONTEND apt-get install -y aubio-tools
sudo apt-get install -y sox
sudo apt-get install -y gnuplot-nox
sudo apt-get install -y gcc
sudo apt-get install -y make
sudo apt-get install -y less
sudo apt-get install -y ruby-dev
sudo apt-get install -y libffi
sudo apt-get install -y libffi-dev
sudo gem install sys-proctable
