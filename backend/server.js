require('dotenv').config();
const express = require('express');
const { MongoClient } = require('mongodb');
const app = express();
const port = process.env.PORT || 3001;

app.use(express.json());

const mongo = new MongoClient(process.env.MONGODB_URI);
let db;

// Connexion MongoDB
mongo.connect().then(() => {
  db = mongo.db();
  console.log("✅ MongoDB connecté");
});

// Route API : statistiques globales du pool
app.get('/api/stats', async (req, res) => {
  try {
    const stats = await db.collection("pool_stats").findOne({}, { sort: { time: -1 } }) || {};
    res.json({
      hashrate: stats.hashrate || 0,
      miners: stats.miners || 0,
      blocksFound: stats.blocksFound || 0,
      lastPayment: stats.lastPayment || null
    });
  } catch (e) {
    res.status(500).send("Erreur serveur");
  }
});

// Route API : statistiques spécifiques d’un mineur
app.get('/api/miner/:address', async (req, res) => {
  try {
    const addr = req.params.address;
    const miner = await db.collection("miners").findOne({ address: addr });
    if (!miner) return res.status(404).send("Mineur non trouvé");
    res.json({
      address: miner.address,
      hashrate: miner.hashrate || 0,
      shares: miner.shares || 0,
      lastPayment: miner.lastPayment || null,
      active: miner.active || false
    });
  } catch (e) {
    res.status(500).send("Erreur serveur");
  }
});

app.listen(port, () => {
  console.log(`✅ API Backend en écoute sur http://localhost:${port}`);
});