#!/usr/bin/bash

set -v

sudo apt install -y ruby
sudo apt install -y figlet
sudo apt install -y toilet
# The option --preserve-env below is needed (why ?) to test this script within a container
sudo --preserve-env=DEBIAN_FRONTEND apt-get install -y aubio-tools
sudo apt install -y sox
sudo apt install -y libsox-fmt-mp3 
