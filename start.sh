#!/bin/bash

echo "🚀 Démarrage complet de la Kaspa Mining Pool..."

# Lancement de MongoDB (en arrière-plan si local)
if ! pgrep mongod > /dev/null; then
  echo "🟡 Lancement de MongoDB local..."
  mongod --dbpath ./data --bind_ip 127.0.0.1 --port 27017 > logs/mongo.log 2>&1 &
  sleep 3
else
  echo "✅ MongoDB déjà actif"
fi

# Lancement du backend
echo "🔧 Lancement du backend API..."
cd backend
nohup node server.js > ../logs/backend.log 2>&1 &
cd ..

# Lancement du serveur Stratum
echo "🔧 Lancement du serveur Stratum..."
cd stratum
nohup node stratum.js > ../logs/stratum.log 2>&1 &
cd ..

echo "✅ Tout est lancé !"
echo "🌐 Backend : http://localhost:$PORT"
echo "🔗 Stratum : tcp://localhost:$STRATUM_PORT"