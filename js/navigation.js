import { getCurrentUser, signOut } from './auth.js';

export async function renderNavigation() {
  const user = await getCurrentUser();
  if (!user) return;

  const nav = document.getElementById('mainNav');
  const role = user.role;
  const root = window.location.pathname.includes('/admin/') ? '../' : './';

  let links = `
    <li><a href="${root}index.html">Dashboard</a></li>
    <li><a href="${root}equipment.html">Equipment</a></li>
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
      <li><a href="${root}borrowing.html">Borrowing</a></li>
      <li><a href="${root}returns.html">Returns</a></li>
      <li><a href="${root}maintenance.html">Maintenance</a></li>
      <li><a href="${root}my-requests.html">My Requests</a></li>
    `;
  }

  // Administrator: management and audit functions
  if (role === 'admin') {
    links += `
      <li><a href="${root}admin/approvals.html">Approvals</a></li>
      <li><a href="${root}admin/users.html">Manage Users</a></li>
      <li><a href="${root}admin/equipment.html">Manage Equipment</a></li>
      <li><a href="${root}admin/audit-logs.html">Audit Logs</a></li>
      <li><a href="${root}admin/reports.html">Reports</a></li>
    `;
  }

  nav.innerHTML = `
    <ul>${links}</ul>
    <div class="user-info">
      <span class="user-avatar">${(user.full_name || 'U').charAt(0).toUpperCase()}</span>
      <span><strong>${user.full_name || 'User'}</strong><small>${role}</small></span>
      <button id="logoutBtn" class="btn btn-ghost">Sign out</button>
    </div>
  `;

  document.getElementById('logoutBtn').addEventListener('click', async () => {
    await signOut();
    window.location.href = `${root}login.html`;
  });
}