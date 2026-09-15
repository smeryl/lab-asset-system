import { supabase } from './supabaseClient.js';

// Fetch audit logs (Admin only)
export async function fetchAuditLogs(filters = {}) {
  let query = supabase
    .from('audit_logs')
    .select(`
      id,
      action,
      module,
      record_id,
      description,
      created_at,
      user:users!user_id (full_name, email, role)
    `)
    .order('created_at', { ascending: false });

  if (filters.module) {
    query = query.eq('module', filters.module);
  }
  if (filters.action) {
    query = query.eq('action', filters.action);
  }
  if (filters.limit) {
    query = query.limit(filters.limit);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data;
}