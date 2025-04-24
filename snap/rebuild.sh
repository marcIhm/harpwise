set -v
rsync -av /home/ihm/harpwise . --exclude .git
cp /home/ihm/harpwise/snap/snapcraft.yaml .
rm harpwise_*_amd64.snap
sudo snap remove harpwise
snapcraft clean ; snapcraft
sudo snap install harpwise_*_amd64.snap --devmode
