#!/usr/bin/bash

set -v

sudo apt-get install -y ruby
sudo apt-get install -y figlet
sudo apt-get install -y toilet
# The option --preserve-env below is needed (why ?) to test this script within a container
sudo --preserve-env=DEBIAN_FRONTEND apt-get install -y aubio-tools
sudo apt-get install -y sox
sudo apt-get install -y libsox-fmt-mp3 
