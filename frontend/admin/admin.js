async function login(e) {
  e.preventDefault();
  const username = document.getElementById("user").value;
  const password = document.getElementById("pass").value;

  const res = await fetch("/api/admin/login", {
    method: "POST",
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password })
  });

  const msg = await res.text();
  document.getElementById("result").innerText = res.ok ? "Success!" : "Access denied.";
}
