#!/bin/bash
set -e

if command -v lazydocker >/dev/null 2>&1; then
    echo "Lazydocker è già installato. Versione: $(lazydocker --version)"
    exit 0
fi

LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
DOWNLOAD_URL="https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"

curl -Lo lazydocker.tar.gz "$DOWNLOAD_URL" || { echo "Errore durante il download di lazydocker.tar.gz"; exit 1; }

mkdir -p lazydocker-temp
tar xf lazydocker.tar.gz -C lazydocker-temp || { echo "Errore durante l'estrazione di lazydocker.tar.gz"; exit 1; }

sudo mv lazydocker-temp/lazydocker /usr/local/bin
rm -rf lazydocker.tar.gz lazydocker-temp

echo "Lazydocker installato con successo. Versione: $(lazydocker --version)"
