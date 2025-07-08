# ⛏️ Kaspa Mining Pool

Un projet **open-source** pour lancer votre propre pool de minage Kaspa, complet et prêt à l’emploi :

- ✅ Serveur **Stratum TCP** (lolMiner, KS0, etc.)  
- ✅ Backend **Node.js + Express + MongoDB**  
- ✅ Système de **paiement automatique** (simulation) avec fee configurable  
- ✅ **Dashboard** dynamique pour mineurs et admin  
- ✅ **Configuration** centralisée via `.env`  
- ✅ Scripts d’**installation** et de **démarrage**

---
## 📁 Structure du projet

kaspa-mining-pool/
├── backend/          
│   ├── server.js         # API REST (stats pool, stats mineurs)
│   ├── payer.js          # Script de paiement automatique (simulation + fee)
│   └── package.json      # Dépendances backend (express, mongodb, dotenv…)
│
├── stratum/          
│   ├── stratum.js        # Serveur Stratum TCP (subscribe, authorize, submit)
│   └── package.json      # Dépendances Stratum (uuid, mongodb, dotenv…)
│
├── frontend/         
│   ├── index.html        # Dashboard public (pool + réseau + miner lookup)
│   ├── dashboard.js      # JS dynamique (Chart.js + fetch API)
│   ├── style.css         # Styles dark / responsive
│   └── admin/            
│       ├── index.html    # Panel admin (login + stats)
│       └── admin.js      # JS auth + fetch API
│
├── .env.example          # Modèle de configuration (ports, MongoDB, fee…)
├── install.sh            # Installe Node.js, MongoDB & dépendances
├── start.sh              # Démarre MongoDB, backend & Stratum (logs)
└── README.md             # Documentation complète (installation, usage…)

---

## ⚙️ Prérequis

- **Node.js** ≥ v18  
- **MongoDB** (local ou distante)  
- **Git** (pour cloner)  
- (Optionnel) **lolMiner**, **IceRiver KS0**, etc. pour tester

---

## 🚀 Installation & déploiement

1. **Cloner le dépôt**  
   ```bash
   git clone https://github.com/KevNews03/kaspa-mining-pool.git
   cd kaspa-mining-pool

2. Copier la config

cp .env.example .env
# puis ajuster .env (URI Mongo, ports, adresse fee, identifiants admin…)


3. Installer les dépendances

chmod +x install.sh start.sh
./install.sh


4. Lancer la pool

./start.sh

MongoDB démarrera (local/data)

Le backend API sera disponible sur http://localhost:3001

Le serveur Stratum écoutera sur tcp://localhost:3333





---

🧪 Tester avec un mineur

lolMiner --coin KASPA --pool localhost:3333 --user kaspa:<TON_ADRESSE_WALLET>.worker1

Ensuite, ouvrez votre navigateur sur http://localhost:3001 :

Dashboard → stats globales & réseau

Entrer votre adresse → vos performances (hashrate, shares, derniers paiements)



---

🔧 Endpoints API

GET /api/network
Renvoie { difficulty, blockHeight, estNetworkHashps, selectedTipHash }

GET /api/stats
Renvoie { hashrate, miners, blocksFound, lastPayment }

GET /api/miner/:address
Renvoie { address, hashrate, shares, lastPayment, active }



---

⚙️ Configuration (.env)

PORT=3001
STRATUM_PORT=3333
MONGODB_URI=mongodb://127.0.0.1:27017/kaspa_pool
FEE_ADDRESS=kaspa:qp8lnn3qpwjxgjl6x9tjy6qd9zjwe5v70r3kpe9ptglp3fa0expxqzl4nl48f
FEE_PERCENT=0.9
RPC_HOST=127.0.0.1
RPC_PORT=16110
ADMIN_USER=admin
ADMIN_PASS=changeme


---

📄 Paiement & fee

Le script backend/payer.js :

se connecte à MongoDB

calcule une « reward » simulée par rapport au hashrate

applique la fee configurée

met à jour la date du dernier paiement


Vous pouvez automatiser son exécution via un cron (ex. */10 * * * * node payer.js).


---

📜 Licence

MIT © KevNews03
Basé sur la communauté Kaspa. Contributions bienvenues !


---

Bonne chance et bons hash ! ⛏️
