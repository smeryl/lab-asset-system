import { supabase } from './supabaseClient.js';
import { getCurrentUser } from './auth.js';

// Create a borrowing request
export async function createBorrowingRequest(equipmentId, notes = '') {
  const user = await getCurrentUser();
  if (!user) throw new Error('Not authenticated');

  // Check business rule BR-A4-01: Only available equipment
  const { data: equipment, error: eqError } = await supabase
    .from('equipment')
    .select('status')
    .eq('id', equipmentId)
    .single();

  if (eqError) throw eqError;
  if (equipment.status !== 'available') {
    throw new Error('Equipment is not available for borrowing');
  }

  const { data, error } = await supabase
    .from('borrowing_requests')
    .insert({
      requester_id: user.id,
      equipment_id: equipmentId,
      status: 'pending',
      notes: notes
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Approve a request (Admin only)
export async function approveRequest(requestId) {
  const user = await getCurrentUser();
  if (user.role !== 'admin') throw new Error('Only administrators can approve requests');

  const { data, error } = await supabase
    .from('borrowing_requests')
    .update({
      status: 'approved',
      approval_date: new Date().toISOString(),
      approver_id: user.id
    })
    .eq('id', requestId)
    .eq('status', 'pending')  // Only pending can be approved
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Reject a request (Admin only)
export async function rejectRequest(requestId) {
  const user = await getCurrentUser();
  if (user.role !== 'admin') throw new Error('Only administrators can reject requests');

  const { data, error } = await supabase
    .from('borrowing_requests')
    .update({
      status: 'rejected',
      approval_date: new Date().toISOString(),
      approver_id: user.id
    })
    .eq('id', requestId)
    .eq('status', 'pending')
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Release equipment (Staff only, BR-A4-04)
export async function releaseEquipment(requestId) {
  const user = await getCurrentUser();
  if (!['staff', 'admin'].includes(user.role)) {
    throw new Error('Only staff or administrators can release equipment');
  }

  // Verify request is approved (BR-A4-04)
  const { data: request, error: fetchError } = await supabase
    .from('borrowing_requests')
    .select('status')
    .eq('id', requestId)
    .single();

  if (fetchError) throw fetchError;
  if (request.status !== 'approved') {
    throw new Error('Only approved requests can be released');
  }

  const { data, error } = await supabase
    .from('borrowing_requests')
    .update({
      status: 'released',
      release_date: new Date().toISOString()
    })
    .eq('id', requestId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Process return (Staff only, BR-A4-08)
export async function processReturn(requestId, isDamaged = false) {
  const user = await getCurrentUser();
  if (!['staff', 'admin'].includes(user.role)) {
    throw new Error('Only staff or administrators can process returns');
  }

  // Verify request is released or overdue (BR-A4-08)
  const { data: request, error: fetchError } = await supabase
    .from('borrowing_requests')
    .select('status')
    .eq('id', requestId)
    .single();

  if (fetchError) throw fetchError;
  if (!['released', 'overdue'].includes(request.status)) {
    throw new Error('Returned transactions cannot be processed twice');
  }

  const { data, error } = await supabase
    .from('borrowing_requests')
    .update({
      status: 'returned',
      return_date: new Date().toISOString()
    })
    .eq('id', requestId)
    .select()
    .single();

  if (error) throw error;

  // If damaged, update equipment status to damaged (BR-A4-06)
  if (isDamaged) {
    await supabase
      .from('equipment')
      .update({ status: 'damaged' })
      .eq('id', request.equipment_id);
  }

  return data;
}