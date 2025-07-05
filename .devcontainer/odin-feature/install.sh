#!/bin/sh
set -e

git clone --branch "dev-2024-12" "https://github.com/odin-lang/Odin.git"

cd Odin

mkdir -p /usr/local/share/odin
cp -r ./base /usr/local/share/odin/
cp -r ./core /usr/local/share/odin/
cp -r ./vendor /usr/local/share/odin/

make release

cp ./odin /usr/local/bin/

echo "Installing SDL2 & SDL2_ttf"
apt update
apt --yes --force-yes install libsdl2-dev libsdl2-ttf-dev
