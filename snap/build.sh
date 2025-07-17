set -v
cd ~/hw-snap
rsync -av /home/ihm/git/harpwise . --exclude .git
erb /home/ihm/git/harpwise/snap/snapcraft.yaml.erb >./snapcraft.yaml
rm harpwise_*_amd64.snap
sudo snap remove harpwise
snapcraft clean ; snapcraft
sudo snap install harpwise_*_amd64.snap --devmode

echo "When satisified, then do:"
echo
echo "snapcraft upload --release=latest/stable harpwise_*_amd64.snap"
echo
