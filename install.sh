#!/bin/bash

echo "🔧 Installation de la Pool Kaspa en cours..."

apt update && apt upgrade -y
apt install -y git curl build-essential unzip

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

apt install -y mongodb
systemctl enable mongodb
systemctl start mongodb

cd /opt
git clone https://github.com/KevNews03/kaspa-mining-pool.git
cd kaspa-mining-pool

cd backend && npm install
cd ../stratum && npm install
cd ../frontend

echo "✅ Installation terminée"
