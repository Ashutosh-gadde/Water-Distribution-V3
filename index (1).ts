import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const transitions: Record<string, Record<string, string[]>> = {
  submit: { draft: ['officer','admin'] }, approve: { submitted: ['officer','admin'] },
  reject: { submitted: ['officer','admin'] }, publish: { approved: ['officer','admin'] },
  cancel: { draft: ['officer','admin'], submitted: ['officer','admin'], approved: ['officer','admin'], published: ['officer','admin'] },
  start: { published: ['operator'] }, pause: { active: ['operator'] }, resume: { paused: ['operator'] },
  stop: { active: ['operator'] },
};
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!, service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const bearer = req.headers.get('Authorization'); if (!bearer) return json({ error: 'Sign in required' }, 401);
  const authClient = createClient(url, anon, { global: { headers: { Authorization: bearer } } });
  const { data: { user }, error: authError } = await authClient.auth.getUser();
  if (authError || !user) return json({ error: 'Invalid session' }, 401);
  const { data: profile } = await authClient.from('profiles').select('role,active,operator_code').eq('id', user.id).single();
  if (!profile?.active) return json({ error: 'Account disabled' }, 403);
  const { schedule_id, action, reason = '' } = await req.json().catch(() => ({}));
  if (!schedule_id || !transitions[action]) return json({ error: 'Invalid schedule action' }, 400);
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: s, error: fetchError } = await admin.from('distribution_schedules').select('*').eq('id', schedule_id).single();
  if (fetchError || !s) return json({ error: 'Schedule not found' }, 404);
  const permittedRoles = transitions[action][s.status] || [];
  if (!permittedRoles.includes(profile.role)) return json({ error: 'Action not allowed for your role or current status' }, 403);
  if (['reject','cancel'].includes(action) && !String(reason).trim()) return json({ error: 'A reason is required' }, 400);
  if (action === 'start' || action === 'pause' || action === 'resume' || action === 'stop') {
    if (profile.role !== 'operator' || s.operator_id !== user.id) return json({ error: 'Only the assigned operator may perform this action' }, 403);
  }
  const now = new Date();
  const updates: Record<string, unknown> = { updated_by: user.id, updated_at: now.toISOString(), remarks: reason || s.remarks };
  const target = ({ submit:'submitted', approve:'approved', reject:'rejected', publish:'published', cancel:'cancelled', start:'active', pause:'paused', resume:'active', stop: (s.service_date === now.toISOString().slice(0,10) && now.toTimeString().slice(0,5) < s.planned_end ? 'interrupted' : 'completed') } as Record<string, string>)[action];
  updates.status = target;
  if (action === 'start') updates.actual_start = now.toISOString();
  if (action === 'stop') updates.actual_end = now.toISOString();
  // Do not trust browser status. Fetch, authorize, then update; production should also add a DB RPC
  // using row locks to prevent simultaneous transitions under race conditions.
  const { data: updated, error: updateError } = await admin.from('distribution_schedules').update(updates).eq('id', schedule_id).eq('status', s.status).select().single();
  if (updateError || !updated) return json({ error: 'Schedule changed concurrently; reload and try again' }, 409);
  await admin.from('audit_events').insert({ actor_id: user.id, action: `schedule.${action}`, entity_type: 'distribution_schedule', entity_id: schedule_id, details: { from: s.status, to: target, reason: String(reason || '') } });
  return json({ ok: true, schedule: updated });
});
