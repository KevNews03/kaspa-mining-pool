#!/bin/bash
set -e

mkdir -p backend stratum frontend/admin logs data

# .env.example
cat > .env.example <<'EOF'
PORT=3001
STRATUM_PORT=3333
MONGODB_URI=mongodb://localhost:27017/kaspapool
FEE_ADDRESS=kaspa:qp8lnn3qpwjxgjl6x9tjy6qd9zjwe5v70r3kpe9ptglp3fa0expxqzl4nl48f
FEE_PERCENT=0.5
RPC_HOST=127.0.0.1
RPC_PORT=16110
ADMIN_USER=admin
ADMIN_PASS=changeme
EOF

# backend/server.js
cat > backend/server.js <<'EOF'
import dotenv from 'dotenv';
import express from 'express';
import session from 'express-session';
import { MongoClient } from 'mongodb';

dotenv.config();
const app = express();
const port = process.env.PORT || 3001;
const client = new MongoClient(process.env.MONGODB_URI);

app.use(express.json());
app.use(session({
  secret: 'kaspa_pool_secret',
  resave: false,
  saveUninitialized: true,
  cookie: { httpOnly: true, maxAge: 24*60*60*1000 }
}));

await client.connect();
const db = client.db();

app.use(express.static('../frontend'));

app.get('/api/stats', async (req, res) => {
  const stats = await db.collection('pool_stats').findOne({}, { sort: { time: -1 } }) || {};
  res.json({
    hashrate: stats.hashrate || 0,
    miners: stats.miners || 0,
    blocksFound: stats.blocksFound || 0,
    feePercent: parseFloat(process.env.FEE_PERCENT),
    lastPayment: stats.lastPayment || null
  });
});

app.get('/api/network', async (req, res) => {
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(`http://${process.env.RPC_HOST}:${process.env.RPC_PORT}`, {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({ jsonrpc:'2.0', id:1, method:'getNetworkInfo', params:{} })
  });
  const data = await response.json();
  res.json({
    estNetworkHashps: data.result.estNetworkHashps,
    averageBlockTime: data.result.averageBlockTime,
    difficulty: data.result.difficulty,
    blockHeight: data.result.blockBlueScore
  });
});

app.get('/api/miner/:address', async (req, res) => {
  const miner = await db.collection('miners').findOne({ address: req.params.address });
  if (!miner) return res.status(404).send('Miner not found');
  res.json({
    address: miner.address,
    hashrate: miner.hashrate || 0,
    avg24h: miner.avg24h || 0,
    shares: miner.shares || 0,
    pendingBalance: miner.pendingBalance || 0,
    totalPaid: miner.totalPaid || 0,
    lastPayment: miner.lastPayment || null,
    active: miner.active || false
  });
});

function requireAuth(req, res, next) {
  if (!req.session || !req.session.admin) return res.status(401).send('Unauthorized');
  next();
}

app.post('/api/admin/login', async (req, res) => {
  const { username, password } = req.body;
  if (username === process.env.ADMIN_USER && password === process.env.ADMIN_PASS) {
    req.session.admin = true;
    res.json({ success: true });
  } else {
    res.status(401).json({ success: false });
  }
});

app.post('/api/admin/logout', (req, res) => {
  req.session.destroy();
  res.json({ success: true });
});

app.get('/api/admin/stats', requireAuth, async (req, res) => {
  const stats = await db.collection('pool_stats').findOne({}, { sort: { time: -1 } }) || {};
  res.json(stats);
});

app.get('/api/admin/miners', requireAuth, async (req, res) => {
  const miners = await db.collection('miners').find().toArray();
  res.json(miners);
});

app.listen(port, () => console.log(`API listening on http://localhost:${port}`));
EOF

# backend/payer.js
cat > backend/payer.js <<'EOF'
import dotenv from 'dotenv';
import fetch from 'node-fetch';

dotenv.config();
const rpcUrl = `http://${process.env.RPC_HOST}:${process.env.RPC_PORT}`;

async function rpc(method, params={}) {
  const res = await fetch(rpcUrl, {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({ jsonrpc:'2.0', id:1, method, params })
  });
  const { result, error } = await res.json();
  if (error) throw new Error(error.message);
  return result;
}

async function processPayments() {
  const dbClient = new (await import('mongodb')).MongoClient(process.env.MONGODB_URI);
  await dbClient.connect();
  const db = dbClient.db();
  const miners = await db.collection('miners').find({ active: true }).toArray();
  const feePercent = parseFloat(process.env.FEE_PERCENT);

  for (const m of miners) {
    if ((m.pendingBalance || 0) >= 1) {
      const amount = m.pendingBalance;
      const fee = amount * feePercent / 100;
      const payout = amount - fee;
      console.log(`[PAYMENT] Send ${payout} KAS to ${m.address}, fee ${fee} (total: ${amount})`);
      const tx = await rpc('generateTransaction', { toAddress: m.address, amount: payout });
      await rpc('submitTransaction', { serializedTransaction: tx });
      await db.collection('miners').updateOne(
        { address: m.address },
        { $set: { pendingBalance: 0, lastPayment: new Date() }, $inc: { totalPaid: payout } }
      );
    }
  }
  await dbClient.close();
}

processPayments().catch(console.error);
EOF

# backend/package.json
cat > backend/package.json <<'EOF'
{
  "type": "module",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "dotenv": "^16.0.3",
    "express": "^4.18.2",
    "mongodb": "^5.6.0",
    "node-fetch": "^3.3.2",
    "express-session": "^1.17.3"
  }
}
EOF

# stratum/stratum.js
cat > stratum/stratum.js <<'EOF'
import dotenv from 'dotenv';
import net from 'net';
import { v4 as uuidv4 } from 'uuid';
import fetch from 'node-fetch';

dotenv.config();
const PORT = process.env.STRATUM_PORT || 3333;
const rpcUrl = `http://${process.env.RPC_HOST}:${process.env.RPC_PORT}`;

async function rpc(method, params={}) {
  const res = await fetch(rpcUrl, {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})
  });
  const { result, error } = await res.json();
  if (error) throw new Error(error.message);
  return result;
}

const server = net.createServer(socket => {
  let minerAddr = '';
  socket.on('data', async data => {
    for (const msg of data.toString().split('\n')) {
      if (!msg) continue;
      const req = JSON.parse(msg);
      if (req.method === 'mining.subscribe') {
        socket.write(JSON.stringify({id:req.id,result:[[["mining.set_difficulty","1"]],"sess"],error:null})+'\n');
      } else if (req.method === 'mining.authorize') {
        minerAddr = req.params[0];
        socket.write(JSON.stringify({id:req.id,result:true,error:null})+'\n');
        const tmpl = await rpc('getBlockTemplate',{});
        socket.write(JSON.stringify({id:null,method:'mining.notify',params:[
          uuidv4(), tmpl.blockTemplateBlob, tmpl.networkTarget
        ]})+'\n');
      } else if (req.method === 'mining.submit') {
        const submit = await rpc('submitBlock',{blockHex:req.params[2]});
        socket.write(JSON.stringify({id:req.id,result:submit,error:null})+'\n');
      }
    }
  });
});
server.listen(PORT,()=>console.log(`Stratum on ${PORT}`));
EOF

# stratum/package.json
cat > stratum/package.json <<'EOF'
{
  "type": "module",
  "scripts": { "start": "node stratum.js" },
  "dependencies": {
    "dotenv": "^16.0.3",
    "node-fetch": "^3.3.2",
    "uuid": "^9.0.0"
  }
}
EOF

# frontend/index.html
cat > frontend/index.html <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8"/>
  <title>Kaspa Pool & Network Dashboard</title>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet"/>
  <script src="https://kit.fontawesome.com/a2e0e6f9b4.js" crossorigin="anonymous"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <link rel="stylesheet" href="style.css"/>
</head>
<body>
  <div class="container py-4">
    <h1 class="text-center mb-4">Kaspa Pool & Network Dashboard</h1>
    <div class="mb-5">
      <h2 class="section-title"><i class="fas fa-network-wired fa-fw"></i> Réseau Kaspa</h2>
      <div class="row gy-3">
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-tachometer-alt fa-fw"></i> Hashrate</h6><div id="net-hashrate" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-stopwatch fa-fw"></i> Temps Bloc</h6><div id="net-blocktime" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-lock fa-fw"></i> Difficulté</h6><div id="net-difficulty" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-layer-group fa-fw"></i> Hauteur</h6><div id="net-height" class="metric">–</div></div></div>
      </div>
    </div>
    <div class="mb-5">
      <h2 class="section-title"><i class="fas fa-hashtag fa-fw"></i> Pool Mining</h2>
      <div class="row gy-3">
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-share-alt fa-fw"></i> Hashrate Pool</h6><div id="pool-hashrate" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-users fa-fw"></i> Mineurs</h6><div id="pool-miners" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-cube fa-fw"></i> Blocs</h6><div id="pool-blocks" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-coins fa-fw"></i> Fee</h6><div id="pool-fee" class="metric">–</div></div></div>
      </div>
      <canvas id="poolChart" class="mt-4" height="100"></canvas>
    </div>
    <div class="mb-5 text-center">
      <input id="minerAddress" class="form-control d-inline-block w-50" placeholder="kaspa:... Votre adresse"/>
      <button onclick="loadMiner()" class="btn btn-primary ms-2"><i class="fas fa-search"></i> Rechercher</button>
    </div>
    <div id="minerSection" class="d-none">
      <h2 class="section-title"><i class="fas fa-user fa-fw"></i> Vos Statistiques</h2>
      <div class="row gy-3">
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-tachometer-alt fa-fw"></i> Hashrate</h6><div id="miner-hashrate" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-chart-line fa-fw"></i> Moy. 24h</h6><div id="miner-avg24" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-file-alt fa-fw"></i> Shares</h6><div id="miner-shares" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-coins fa-fw"></i> En attente</h6><div id="miner-pending" class="metric">–</div></div></div>
      </div>
      <div class="row gy-3 mt-4">
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-chart-bar fa-fw"></i> Total payé</h6><div id="miner-paid" class="metric">–</div></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 text-center"><h6><i class="fas fa-history fa-fw"></i> Dern. paiement</h6><div id="miner-lastpay" class="metric">–</div></div></div>
      </div>
    </div>
  </div>
  <script>
    const poolCtx = document.getElementById('poolChart').getContext('2d');
    const poolChart = new Chart(poolCtx, { type:'line', data:{ labels:Array(20).fill(''), datasets:[{ label:'Pool Hashrate', data:Array(20).fill(0), borderColor:'#00ffff', borderWidth:2 }] }, options:{ scales:{ y:{ beginAtZero:true } } } });
    async function fetchNetwork() {
      const res = await fetch('/api/network'); const d = await res.json();
      document.getElementById('net-hashrate').innerText = d.estNetworkHashps + ' H/s';
      document.getElementById('net-blocktime').innerText = d.averageBlockTime + ' s';
      document.getElementById('net-difficulty').innerText = d.difficulty;
      document.getElementById('net-height').innerText = d.blockHeight;
    }
    async function fetchPool() {
      const res = await fetch('/api/stats'); const p = await res.json();
      document.getElementById('pool-hashrate').innerText = p.hashrate + ' H/s';
      document.getElementById('pool-miners').innerText = p.miners;
      document.getElementById('pool-blocks').innerText = p.blocksFound;
      document.getElementById('pool-fee').innerText = p.feePercent + ' %';
      poolChart.data.datasets[0].data.push(p.hashrate); poolChart.data.datasets[0].data.shift(); poolChart.update();
    }
    async function loadMiner() {
      const addr = document.getElementById('minerAddress').value.trim();
      if (!addr.startsWith('kaspa:')) return alert('Adresse Kaspa invalide');
      const res = await fetch(`/api/miner/${addr}`);
      if (!res.ok) return alert('Mineur non trouvé');
      const m = await res.json();
      document.getElementById('miner-hashrate').innerText = m.hashrate + ' H/s';
      document.getElementById('miner-avg24').innerText = m.avg24h + ' H/s';
      document.getElementById('miner-shares').innerText = m.shares;
      document.getElementById('miner-pending').innerText = m.pendingBalance + ' KAS';
      document.getElementById('miner-paid').innerText = m.totalPaid + ' KAS';
      document.getElementById('miner-lastpay').innerText = m.lastPayment || '–';
      document.getElementById('minerSection').classList.remove('d-none');
    }
    fetchNetwork(); fetchPool(); setInterval(fetchNetwork,30000); setInterval(fetchPool,10000);
  </script>
</body>
</html>
EOF

# frontend/style.css
cat > frontend/style.css <<'EOF'
body { background: #10161d; color: #e0e0e0; }
.card { background: #161b22; border: none; border-radius: 18px; box-shadow: 0 4px 20px #0004; }
.metric { font-size: 1.5rem; font-weight: 600; letter-spacing: 1px.metric { font-size: 1.5rem; font-weight: 600; letter-spacing: 1px; }
.section-title { color: #50fa7b; }
input, button, .form-control { background: #232b36 !important; color: #e0e0e0 !important; border: 1px solid #2c3440 !important; }
input:focus, button:focus { outline: 2px solid #50fa7b !important; }
.btn-primary { background: #50fa7b; color: #121212; border: none; }
.btn-primary:hover { background: #40c060; }
a { color: #7bdaf3; }
a:hover { text-decoration: underline; color: #40c0ff; }
::-webkit-scrollbar { width: 10px; background: #161b22; }
::-webkit-scrollbar-thumb { background: #232b36; border-radius: 6px; }
@media (max-width: 768px) {
  .container { padding: 0 8px; }
  .metric { font-size: 1.2rem; }
}
EOF

# frontend/admin/index.html
cat > frontend/admin/index.html <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8"/>
  <title>Admin Kaspa Pool</title>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <link href="../style.css" rel="stylesheet"/>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet"/>
</head>
<body class="bg-dark text-light">
<div class="container py-5">
  <h2 class="mb-4">Admin Pool Kaspa</h2>
  <div id="loginSection">
    <form onsubmit="login(event)" class="mb-3">
      <input id="user" class="form-control mb-2" placeholder="Utilisateur"/>
      <input id="pass" type="password" class="form-control mb-2" placeholder="Mot de passe"/>
      <button class="btn btn-primary w-100">Connexion</button>
    </form>
    <div id="msg" class="text-danger mb-3"></div>
  </div>
  <div id="adminSection" style="display:none">
    <button onclick="logout()" class="btn btn-secondary float-end mb-3">Déconnexion</button>
    <h3>Statistiques Pool</h3>
    <div id="stats" class="mb-4"></div>
    <h3>Mineurs actifs</h3>
    <table class="table table-dark table-sm table-striped" id="minersTable">
      <thead><tr><th>Adresse</th><th>Hashrate</th><th>Shares</th><th>Solde</th><th>Dern. Paiement</th></tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>
<script src="admin.js"></script>
</body>
</html>
EOF

# frontend/admin/admin.js
cat > frontend/admin/admin.js <<'EOF'
async function login(e){
  e.preventDefault();
  const res = await fetch('/api/admin/login', {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({username:document.getElementById('user').value,password:document.getElementById('pass').value})
  });
  if (res.ok) {
    document.getElementById('loginSection').style.display = 'none';
    document.getElementById('adminSection').style.display = '';
    loadAdmin();
  } else {
    document.getElementById('msg').innerText = "Mauvais identifiant ou mot de passe";
  }
}
async function loadAdmin(){
  // Stats pool
  const stats = await fetch('/api/admin/stats').then(r=>r.json());
  document.getElementById('stats').innerHTML = `
    <b>Hashrate:</b> ${stats.hashrate || 0} H/s &nbsp; 
    <b>Mineurs:</b> ${stats.miners || 0} &nbsp;
    <b>Blocs:</b> ${stats.blocksFound || 0} &nbsp; 
    <b>Dern. Paiement:</b> ${stats.lastPayment || '-'}
  `;
  // Liste mineurs
  const miners = await fetch('/api/admin/miners').then(r=>r.json());
  const tbody = document.querySelector('#minersTable tbody');
  tbody.innerHTML = "";
  miners.forEach(m => {
    tbody.innerHTML += `<tr>
      <td>${m.address}</td>
      <td>${m.hashrate || 0}</td>
      <td>${m.shares || 0}</td>
      <td>${m.pendingBalance || 0} KAS</td>
      <td>${m.lastPayment || '-'}</td>
    </tr>`;
  });
}
async function logout(){
  await fetch('/api/admin/logout', {method:'POST'});
  document.getElementById('adminSection').style.display = 'none';
  document.getElementById('loginSection').style.display = '';
}
EOF

# install.sh
cat > install.sh <<'EOF'
#!/bin/bash
set -e
cd backend && npm install && cd ..
cd stratum && npm install && cd ..
EOF
chmod +x install.sh

# start.sh
cat > start.sh <<'EOF'
#!/bin/bash
set -e
mongod --dbpath ./data --fork --logpath logs/mongo.log
cd backend && nohup npm start > ../logs/backend.log 2>&1 & cd ..
cd stratum && nohup npm start > ../logs/stratum.log 2>&1 & cd ..
echo "Pool, API, et Stratum lancés."
EOF
chmod +x start.sh

# README.md
cat > README.md <<'EOF'
# Kaspa Mining Pool

## Prérequis
- Node.js v18+
- MongoDB
- kaspad (RPC sur 127.0.0.1:16110)

## Installation
1. `cp .env.example .env` et configure.
2. `chmod +x install.sh start.sh`
3. `./install.sh`
4. `mkdir -p data logs`
5. `./start.sh`
6. Visite `http://IP:3001/`

## Paiement automatique
- Modifier la crontab pour :

0 * * * * cd /chemin/vers/backend && node payer.js

- Paiement automatique toutes les heures si balance ≥ 1 KAS.

## Sécurité
- Modifier ADMIN_USER et ADMIN_PASS dans `.env` !

## Support
Contact : kevnews03 ou GPT, tout est open-source.
EOF

echo "✅ Pool Kaspa générée avec succès ! Installe, configure, puis ./start.sh 🚀"
