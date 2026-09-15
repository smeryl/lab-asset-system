import { getCurrentUser, hasRole, signOut } from './auth.js';

export async function renderNavigation() {
  const user = await getCurrentUser();
  if (!user) return;

  const nav = document.getElementById('mainNav');
  const role = user.role;

  let links = `
    <li><a href="index.html">Dashboard</a></li>
    <li><a href="equipment.html">Equipment</a></li>
  `;

  // Requester / Viewer: request and history only
  if (role === 'requester') {
    links += `
      <li><a href="my-requests.html">My Requests</a></li>
      <li><a href="request-equipment.html">Request Equipment</a></li>
    `;
  }

  // Laboratory Staff: operational functions
  if (role === 'staff') {
    links += `
      <li><a href="borrowing.html">Borrowing</a></li>
      <li><a href="returns.html">Returns</a></li>
      <li><a href="maintenance.html">Maintenance</a></li>
      <li><a href="my-requests.html">My Requests</a></li>
    `;
  }

  // Administrator: management and audit functions
  if (role === 'admin') {
    links += `
      <li><a href="admin/approvals.html">Approvals</a></li>
      <li><a href="admin/users.html">Manage Users</a></li>
      <li><a href="admin/equipment.html">Manage Equipment</a></li>
      <li><a href="admin/audit-logs.html">Audit Logs</a></li>
      <li><a href="admin/reports.html">Reports</a></li>
    `;
  }

  nav.innerHTML = `
    <ul>${links}</ul>
    <div class="user-info">
      <span>${user.full_name} (${role})</span>
      <button id="logoutBtn">Logout</button>
    </div>
  `;

  document.getElementById('logoutBtn').addEventListener('click', async () => {
    await signOut();
    window.location.href = 'login.html';
  });
}