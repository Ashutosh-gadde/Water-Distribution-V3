import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

export async function getMyProfile() {
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!user) return null;
  const { data, error } = await supabase.from('profiles')
    .select('id,display_name,role,operator_code,active').eq('id', user.id).single();
  if (error) throw error;
  if (!data.active) throw new Error('This account has been disabled.');
  return { ...data, email: user.email };
}

export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  const profile = await getMyProfile();
  if (!profile) throw new Error('No application profile found. Contact the administrator.');
  return profile;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function loadMapFeatures() {
  const { data, error } = await supabase.rpc('get_map_features');
  if (error) throw error;
  return data;
}

export async function loadDashboard() {
  // RLS applies to all counts; citizen counts will reflect only rows they can read.
  const [assets, meters, schedules] = await Promise.all([
    supabase.from('network_assets').select('id,asset_type,verification', { count: 'exact', head: true }),
    supabase.from('water_meters').select('id', { count: 'exact', head: true }),
    supabase.from('distribution_schedules').select('id,status,service_date', { count: 'exact' })
  ]);
  for (const r of [assets, meters, schedules]) if (r.error) throw r.error;
  return { assets: assets.count ?? 0, meters: meters.count ?? 0, schedules: schedules.data ?? [] };
}

export async function listAssets() {
  const { data, error } = await supabase.from('network_assets')
    .select('id,asset_code,asset_type,name,properties,verification,public_visible,updated_at')
    .order('asset_type').order('asset_code').limit(5000);
  if (error) throw error;
  return data;
}

export async function listMeters() {
  // Deliberately do not select customer identifiers from water_meter_private.
  const { data, error } = await supabase.from('water_meters')
    .select('id,meter_code,asset_code,meter_type,status,install_date,last_reading,last_reading_at,notes,updated_at')
    .order('meter_code').limit(5000);
  if (error) throw error;
  return data;
}

export async function listSchedules() {
  const { data, error } = await supabase.from('distribution_schedules')
    .select('id,schedule_code,zone_asset_id,service_date,planned_start,planned_end,status,actual_start,actual_end,remarks')
    .order('service_date', { ascending: false }).limit(1000);
  if (error) throw error;
  return data;
}

export async function adminCreateUser({ email, display_name, role, operator_code }) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('Sign in as an administrator first.');
  const response = await fetch(`${SUPABASE_URL}/functions/v1/admin-create-user`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
    body: JSON.stringify({ email, display_name, role, operator_code })
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || 'Could not create account.');
  return body;
}

export async function runScheduleAction({ schedule_id, action, reason = '' }) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('Please sign in again.');
  const response = await fetch(`${SUPABASE_URL}/functions/v1/schedule-action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
    body: JSON.stringify({ schedule_id, action, reason })
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || 'Schedule action failed.');
  return body;
}

// Canonical ward boundaries are maintained in Supabase Storage (gis-data/Ward_Map.geojson).
export async function loadWardBoundaries() {
  const { data, error } = await supabase.storage.from('gis-data').download('Ward_Map.geojson');
  if (error) throw error;
  if (!data) throw new Error('Ward_Map.geojson was not returned by Supabase Storage.');
  const geojson = JSON.parse(await data.text());
  if (geojson.type !== 'FeatureCollection' || !Array.isArray(geojson.features)) {
    throw new Error('Ward_Map.geojson is not a valid GeoJSON FeatureCollection.');
  }
  const wards = [...new Set(geojson.features
    .map(feature => feature?.properties?.Ward_No)
    .filter(value => value !== null && value !== undefined && String(value).trim() !== '')
    .map(value => /^\\d+$/.test(String(value).trim())
      ? `Ward ${String(value).trim().padStart(2, '0')}`
      : `Ward ${String(value).trim()}`))]
    .sort((a, b) => {
      const na = Number(a.replace(/^Ward /, ''));
      const nb = Number(b.replace(/^Ward /, ''));
      return Number.isFinite(na) && Number.isFinite(nb)
        ? na - nb
        : a.localeCompare(b, undefined, { numeric: true });
    });
  return { geojson, wards };
}
