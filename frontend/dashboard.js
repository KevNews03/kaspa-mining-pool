async function fetchStats() {
  const res = await fetch('/api/stats');
  const data = await res.json();

  document.getElementById('hashrate').innerText = data.hashrate + ' H/s';
  document.getElementById('miners').innerText = data.miners;
  document.getElementById('blocks').innerText = data.blocksFound;
  document.getElementById('payment').innerText = data.lastPayment || "N/A";

  updateChart(data.hashrate);
}

let chart;
function updateChart(currentHashrate) {
  if (!chart) {
    const ctx = document.getElementById('hashrateChart').getContext('2d');
    chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: Array(10).fill(''),
        datasets: [{
          label: 'Hashrate',
          data: Array(10).fill(currentHashrate),
          borderColor: 'rgba(0, 255, 255, 0.7)',
          borderWidth: 2
        }]
      },
      options: {
        scales: { y: { beginAtZero: true } }
      }
    });
  } else {
    chart.data.datasets[0].data.push(currentHashrate);
    chart.data.datasets[0].data.shift();
    chart.update();
  }
}

setInterval(fetchStats, 10000);
fetchStats();
