import { supabase } from './supabaseClient.js';

// Get current user profile with role
export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', user.id)
    .single();

  if (error) {
    console.error('Error fetching user profile:', error);
    return null;
  }
  return profile;
}

// Sign in
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw error;
  return data;
}

// Sign up (with role selection — for demo purposes; in production, admin assigns roles)
export async function signUp(email, password, fullName, role = 'requester') {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName, role: role }
    }
  });
  if (error) throw error;
  return data;
}

// Sign out
export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

// Listen for auth state changes
export function onAuthStateChange(callback) {
  supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session);
  });
}

// Protect a page: redirect to login if not authenticated
export async function requireAuth() {
  const user = await getCurrentUser();
  if (!user) {
    window.location.href = 'login.html';
    return null;
  }
  return user;
}

// Check if user has a specific role
export function hasRole(user, allowedRoles) {
  if (!user) return false;
  return allowedRoles.includes(user.role);
}