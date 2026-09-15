import { getCurrentUser, signOut } from './auth.js';

export async function renderNavigation() {
  const user = await getCurrentUser();
  if (!user) return;

  const nav = document.getElementById('mainNav');
  const role = user.role;
  const root = window.location.pathname.includes('/admin/') ? '../' : './';

  const dashboards = {
    requester: 'requester-dashboard.html',
    staff: 'staff-dashboard.html',
    admin: 'admin/index.html'
  };
  const dashboard = `${root}${dashboards[role] || 'index.html'}`;
  let links = `<li><a href="${dashboard}">Dashboard</a></li>`;

  if (role === 'requester') {
    links += `
      <li><a href="${root}equipment.html">Available Equipment</a></li>
      <li><a href="${root}request-equipment.html">Request Equipment</a></li>
      <li><a href="${root}my-requests.html">My Requests</a></li>`;
  } else if (role === 'staff') {
    links += `
      <li><a href="${root}borrowing.html">Borrowing</a></li>
      <li><a href="${root}returns.html">Returns</a></li>
      <li><a href="${root}maintenance.html">Maintenance</a></li>`;
  } else if (role === 'admin') {
    links += `
      <li><a href="${root}admin/approvals.html">Approvals</a></li>
      <li><a href="${root}admin/equipment.html">Assets</a></li>
      <li><a href="${root}admin/users.html">Users</a></li>
      <li><a href="${root}admin/reports.html">Reports</a></li>
      <li><a href="${root}admin/audit-logs.html">Audit Logs</a></li>`;
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