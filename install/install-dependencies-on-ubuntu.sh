#!/usr/bin/bash

set -v

sudo apt-get install -y ruby
sudo apt-get install -y figlet
sudo apt-get install -y alsa-utils
# The option --preserve-end below is needed to test this script within a container
sudo --preserve-env=DEBIAN_FRONTEND apt-get install -y aubio-tools
sudo apt-get install -y sox
sudo apt-get install -y libsox-fmt-mp3 
sudo apt-get install -y gnuplot-nox
sudo apt-get install -y gcc
sudo apt-get install -y make
sudo apt-get install -y less
sudo apt-get install -y ruby-dev
sudo apt-get install -y libffi
sudo apt-get install -y libffi-dev
sudo gem install sys-proctable
