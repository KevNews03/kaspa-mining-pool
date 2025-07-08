require('dotenv').config();
const { MongoClient } = require('mongodb');

const mongo = new MongoClient(process.env.MONGODB_URI);

async function processPayments() {
  await mongo.connect();
  const db = mongo.db();

  const FEE = parseFloat(process.env.FEE_PERCENT || "0.9");

  const miners = await db.collection("miners").find({ active: true }).toArray();

  for (const miner of miners) {
    const reward = (miner.hashrate || 0) * 0.0001; // Simulé : 0.0001 KAS/H/s
    const fee = reward * FEE / 100;
    const payout = reward - fee;

    console.log(`💸 Paiement simulé à ${miner.address}:`);
    console.log(`    → Reward: ${reward.toFixed(6)} KAS`);
    console.log(`    → Fee (${FEE}%): ${fee.toFixed(6)} KAS`);
    console.log(`    → Payout: ${payout.toFixed(6)} KAS`);

    await db.collection("miners").updateOne(
      { address: miner.address },
      { $set: { lastPayment: new Date() } }
    );
  }

  await mongo.close();
  console.log("✅ Paiements simulés terminés");
}

processPayments();