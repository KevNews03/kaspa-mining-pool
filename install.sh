#!/bin/bash

echo "📦 Installation de la Kaspa Mining Pool..."

# Backend
echo "📁 Installation des dépendances backend..."
cd backend
npm install
cd ..

# Stratum
echo "📁 Installation des dépendances stratum..."
cd stratum
npm install
cd ..

# Création des dossiers de logs et data
echo "📁 Préparation des dossiers..."
mkdir -p logs
mkdir -p data

echo "✅ Installation terminée."
echo "💡 Tu peux maintenant lancer la pool avec : ./start.sh"