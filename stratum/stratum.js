const net = require('net');
const { v4: uuidv4 } = require('uuid');
const { MongoClient } = require('mongodb');
require('dotenv').config();

const PORT = process.env.STRATUM_PORT || 3333;
const mongo = new MongoClient(process.env.MONGODB_URI);
let db;

mongo.connect().then(() => {
  db = mongo.db();
  console.log("✅ MongoDB connecté (Stratum)");
});

function createFakeJob() {
  const jobId = uuidv4();
  return {
    job_id: jobId,
    blob: "0".repeat(76) + "ff".repeat(8),
    target: "ffff000000000000000000000000000000000000000000000000000000000000"
  };
}

function handleSubmit(address, difficulty = 1) {
  db.collection('miners').updateOne(
    { address },
    {
      $set: { active: true },
      $inc: { shares: 1, hashrate: difficulty }
    },
    { upsert: true }
  );
}

const server = net.createServer((socket) => {
  console.log("⚡ Mineur connecté");
  let minerAddress = "unknown";

  socket.on('data', (data) => {
    const messages = data.toString().trim().split('\n');
    for (const msg of messages) {
      try {
        const req = JSON.parse(msg);
        if (req.method === 'mining.subscribe') {
          socket.write(JSON.stringify({
            id: req.id,
            result: [[["mining.set_difficulty", "1"]], "session-id"],
            error: null
          }) + '\n');
        } else if (req.method === 'mining.authorize') {
          minerAddress = req.params[0];
          socket.write(JSON.stringify({ id: req.id, result: true, error: null }) + '\n');

          const job = createFakeJob();
          socket.write(JSON.stringify({ id: null, method: "mining.set_difficulty", params: [1] }) + '\n');
          socket.write(JSON.stringify({ id: null, method: "mining.job", params: [job.job_id, job.blob, job.target] }) + '\n');
        } else if (req.method === 'mining.submit') {
          handleSubmit(minerAddress, 1);
          socket.write(JSON.stringify({ id: req.id, result: true, error: null }) + '\n');
        }
      } catch (err) {
        console.error("❌ Erreur JSON stratum:", err);
      }
    }
  });

  socket.on('end', () => {
    console.log("🔌 Mineur déconnecté");
  });

  socket.on('error', (err) => {
    console.error("Erreur socket:", err);
  });
});

server.listen(PORT, () => {
  console.log(`✅ Stratum actif sur port ${PORT}`);
});
