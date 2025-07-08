#!/bin/bash

echo "🚀 Démarrage de la Pool Kaspa..."

systemctl start mongodb

cd /opt/kaspa-mining-pool/backend
nohup node server.js > backend.log 2>&1 &

cd ../stratum
nohup node stratum.js > stratum.log 2>&1 &

echo "✅ Pool lancée"
