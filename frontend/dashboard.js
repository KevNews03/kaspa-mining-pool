async function loadMiner() {
  const addr = document.getElementById('minerAddress').value.trim();
  if (!addr.startsWith('kaspa:')) {
    return alert('Adresse Kaspa invalide.');
  }
  try {
    const res = await fetch(`/api/miner/${addr}`);
    if (!res.ok) throw new Error('Mineur non trouvÃ©');
    const m = await res.json();
    document.getElementById('miner-hashrate').innerText = m.hashrate + ' H/s';
    document.getElementById('miner-shares').innerText = m.shares;
    document.getElementById('miner-payment').innerText = m.lastPayment || 'â€“';
    document.getElementById('miner-status').innerText = m.active ? 'Active' : 'Inactive';
    document.getElementById('minerSection').classList.remove('d-none');
  } catch (err) {
    alert(err.message || 'Erreur lors du chargement du mineur');
  }
}

// Initialisation
document.getElementById('minerAddress').addEventListener('keypress', function(e) {
  if (e.key === 'Enter') loadMiner();
});

fetchNetwork();
fetchPool();
setInterval(fetchNetwork, 30000);  // Toutes les 30s
setInterval(fetchPool, 10000);