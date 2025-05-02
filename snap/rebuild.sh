set -v
rsync -av /home/ihm/git/harpwise . --exclude .git
cp /home/ihm/git/harpwise/snap/snapcraft.yaml .
rm harpwise_*_amd64.snap
sudo snap remove harpwise
snapcraft clean ; snapcraft
sudo snap install harpwise_*_amd64.snap --devmode
