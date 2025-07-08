require('dotenv').config();
const { MongoClient } = require('mongodb');

async function processPayments() {
  const mongo = new MongoClient(process.env.MONGODB_URI);
  await mongo.connect();
  const db = mongo.db();

  const miners = await db.collection("miners").find({}).toArray();

  for (const miner of miners) {
    const reward = (miner.hashrate || 0) * 0.0001; // Simulé
    const fee = reward * (parseFloat(process.env.FEE_PERCENT) / 100);
    const payout = reward - fee;

    console.log(`💸 Paiement à ${miner.address}: ${payout.toFixed(4)} KAS (fee: ${fee.toFixed(4)})`);

    // Met à jour la date du dernier paiement
    await db.collection("miners").updateOne(
      { address: miner.address },
      { $set: { lastPayment: new Date() } }
    );
  }

  console.log("✅ Paiements simulés terminés");
  await mongo.close();
}

processPayments();