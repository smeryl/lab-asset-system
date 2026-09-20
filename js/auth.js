import { supabase } from './supabaseClient.js';

let cachedUser = null;

// Works out whether we are inside /admin/ so relative links stay correct.
export function rootPath() {
  return window.location.pathname.includes('/admin/') ? '../' : './';
}

// Get the signed-in user PLUS their profile row (which holds the role).
export async function getCurrentUser({ force = false } = {}) {
  if (cachedUser && !force) return cachedUser;

  const { data: { session } } = await supabase.auth.getSession();
  if (!session || !session.user) return null;

  const authUser = session.user;

  const { data: profile, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', authUser.id)
    .maybeSingle();          // maybeSingle() does NOT throw when 0 rows come back

  if (error) {
    console.error('[auth] Could not read profile:', error.message);
    return null;
  }

  // Self-heal: the account exists in auth.users but has no profile row yet.
  // This happens to every account created before the signup trigger existed.
  if (!profile) {
    console.warn('[auth] No profile row found — creating one now.');
    const { data: created, error: insertError } = await supabase
      .from('users')
      .insert({
        id: authUser.id,
        email: authUser.email,
        full_name: authUser.user_metadata?.full_name || authUser.email.split('@')[0],
        role: authUser.user_metadata?.role || 'requester'
      })
      .select()
      .single();

    if (insertError) {
      console.error('[auth] Could not create profile:', insertError.message);
      return null;
    }
    cachedUser = created;
    return cachedUser;
  }

  cachedUser = profile;
  return cachedUser;
}

export async function signIn(email, password) {
  cachedUser = null;
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signUp(email, password, fullName, role = 'requester') {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName, role } }
  });
  if (error) throw error;
  return data;
}

export async function signOut() {
  cachedUser = null;
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export function onAuthStateChange(callback) {
  supabase.auth.onAuthStateChange((event, session) => {
    cachedUser = null;
    callback(event, session);
  });
}

// Redirect to login when not signed in.
export async function requireAuth() {
  const user = await getCurrentUser();
  if (!user) {
    window.location.href = `${rootPath()}login.html`;
    return null;
  }
  return user;
}

export function hasRole(user, allowedRoles) {
  if (!user) return false;
  return allowedRoles.includes(user.role);
}

// Guard a page in one line: `const user = await requireRole(['admin']);`
export async function requireRole(allowedRoles) {
  const user = await requireAuth();
  if (!user) return null;
  if (!hasRole(user, allowedRoles)) {
    document.body.innerHTML = `
      <main class="loading-page">
        <h1>Access Denied</h1>
        <p>Your role (<strong>${user.role}</strong>) cannot open this page.</p>
        <p><a href="${rootPath()}index.html">Return to your dashboard</a></p>
      </main>`;
    return null;
  }
  return user;
}
