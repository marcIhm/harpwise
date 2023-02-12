#!/usr/bin/bash

set -v

sudo apt-get install -y ruby
sudo apt-get install -y figlet
sudo apt-get install -y toilet
sudo apt-get install -y alsa-utils
# The option --preserve-end below is needed to test this script within a container
sudo --preserve-env=DEBIAN_FRONTEND apt-get install -y aubio-tools
sudo apt-get install -y sox
sudo apt-get install -y libsox-fmt-mp3 
sudo apt-get install -y gnuplot-nox
