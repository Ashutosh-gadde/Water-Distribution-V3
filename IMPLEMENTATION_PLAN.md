# Implementation plan

## Phase 0 — preserve and assess
- Keep the uploaded HTML as `legacy-demo.html` for reference.
- Confirm the existing GitHub repository, Pages source, project owner, and whether the repository must remain public.
- Classify GIS layers into public-safe boundaries versus restricted operational network layers; classify meter/customer data separately.

## Phase 1 — secure platform foundation
- Create Supabase staging project; enable PostGIS and email authentication.
- Apply schema/RLS migration; provision one verified administrator.
- Deploy account-invitation and schedule-action Edge Functions.
- Add only Supabase URL + publishable/anon key to frontend config.

## Phase 2 — import and verify GIS
- Normalize approved source layers in QGIS; validate IDs, geometry types, CRS and topology.
- Import to staging tables, map into `network_assets`, and separately import `water_meters`.
- Keep customer data in `water_meter_private`; keep public visibility false until reviewed.
- Verify map features via the RLS-filtered RPC from anon, citizen, operator and officer sessions.

## Phase 3 — connect existing workflows
- Keep dashboard, GIS map, asset register, water meter register, public schedule view, and English/Marathi switch.
- Migrate schedule creation and all state transitions to server-authorized code.
- Add conflict detection for operator time overlap/shared valves and the legacy operating window rules.
- Replace localStorage records and role-preview dropdown completely; do not use the old page for production.

## Phase 4 — deployment and hardening
- Push reviewed static files to existing GitHub repository and confirm Pages base path.
- Verify Auth redirect URLs, email templates, function deployment, tile provider, and CSP/dependency pinning.
- Test direct REST/RPC attempts per role, not just what buttons show.
- Add monitoring, backups, access review, data retention, operational runbook and rollback procedure.

## Phase 5 — acceptance
- Conduct joint review with GIS, water supply operations, IT/security, and authorized municipal data owner.
- Compare sample real-world locations/IDs with QGIS and field records.
- Approve public visibility and role matrix in writing before enabling production access.
