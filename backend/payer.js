// Basic simulation of Kaspa pool payout logic
require('dotenv').config();
const { MongoClient } = require("mongodb");

async function distributeRewards() {
  const mongo = new MongoClient(process.env.MONGODB_URI);
  await mongo.connect();
  const db = mongo.db();

  const miners = await db.collection("shares").aggregate([
    { $group: { _id: "$address", total: { $sum: "$difficulty" } } }
  ]).toArray();

  const total = miners.reduce((acc, m) => acc + m.total, 0);
  console.log("Total shares:", total);

  for (const miner of miners) {
    const percent = miner.total / total;
    const reward = percent * 1000; // simulate 1000 KAS block
    const fee = reward * (parseFloat(process.env.FEE_PERCENT) / 100);
    const payout = reward - fee;

    console.log(`Pay ${miner._id} : ${payout.toFixed(2)} KAS`);
    console.log(`Fee: ${fee.toFixed(2)} KAS to ${process.env.FEE_ADDRESS}`);
  }

  await mongo.close();
}
distributeRewards();
