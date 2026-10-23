# Water Network Data & Distribution Portal — implementation scaffold

This package contains a deployment-oriented starter based on the uploaded HTML. It preserves the original file as `legacy-demo.html` for reference and provides a new authenticated shell at `index.html`, Supabase client modules, PostGIS/RLS migration, and two Edge Functions.

**This is a scaffold, not a live/production-ready portal.** No Supabase project, GitHub repository, real GIS dataset, DNS/domain, or credentials were available to configure or test. Do not publish operationally sensitive water-network coordinates until the Municipal Corporation approves the public/private data split and access policy.

## What changed from the uploaded HTML

The original HTML has a schematic SVG map, abstract demo geometry, browser `localStorage` persistence, a role-switch dropdown that is only a preview, and a browser-only audit log. Those cannot be made secure by hiding buttons. The new starter:

- Replaces role switching with Supabase email/password authentication and a profile-backed role.
- Uses Leaflet with an OpenStreetMap basemap and PostGIS-backed GeoJSON via the `get_map_features()` RPC.
- Adds a dedicated water-meter table and meter register; meter customer/connection fields live in a separate restricted table.
- Adds dashboard, GIS map, assets, meters, schedules, and admin account-invitation screens.
- Adds database row-level security (RLS), a server-side account invitation Edge Function, a server-side schedule-transition Edge Function, and a server-side audit table.
- Keeps the English/Marathi toggle and similar dashboard/map/register/schedule concepts. The original full HTML remains as `legacy-demo.html` and should not be exposed as the production entry page.

The new shell does not yet reproduce every legacy schedule conflict rule or every legacy table/translation. Treat it as the first integration increment and complete the acceptance checklist before operational use.

## Files

- `index.html` — new entry page; no role selector and no browser localStorage for operational records.
- `legacy-demo.html` — original uploaded HTML, preserved for reference only. Do not use as production entry point.
- `src/config.js` — public Supabase URL/key and map extent placeholders.
- `src/backend.js` — auth, profile, data queries, Edge Function calls.
- `src/map.js` — Leaflet basemap and PostGIS GeoJSON rendering.
- `supabase/migrations/001_initial_schema.sql` — PostGIS tables, meter support, role helper, RLS policies and GeoJSON RPC.
- `supabase/functions/admin-create-user/index.ts` — admin-authorized email invitation; service-role key remains server-side.
- `supabase/functions/schedule-action/index.ts` — server-authorized schedule transitions and audit logging.

## 1. Existing GitHub repository

1. Back up the current branch and download/export the current live site if any.
2. Copy `index.html`, `src/`, and `supabase/` into the **existing repository root**. Keep `legacy-demo.html` in a non-public archive branch if the original contains sensitive/demo material; if kept in the public repository, remember any HTML file can be opened directly.
3. In `src/config.js`, set `SUPABASE_URL` and the Supabase **publishable/anon key**. The publishable/anon key is intended for browser use; it is not an authorization mechanism. RLS is mandatory.
4. Do not put the database password, Supabase `service_role` key, access tokens, private map-provider keys, or any customer data in HTML, JS, repository files, GitHub Pages settings, or screenshots.
5. Ensure GitHub Pages is configured for the existing branch/folder or GitHub Actions deployment that the repository already uses. If it publishes from `/docs`, put the files there and adjust relative module paths if needed. Use HTTPS.

GitHub Pages serves static files only. It cannot securely run a server or keep server-side secrets. Supabase Edge Functions provide the server-side endpoints.

## 2. Supabase dashboard configuration

1. Create/open the approved Supabase project and note its Project URL and publishable/anon key.
2. In **SQL Editor**, run `supabase/migrations/001_initial_schema.sql` once in a non-production test project first. Review extension/schema privileges if your project uses a non-default PostGIS installation schema.
3. In **Authentication → URL Configuration**, add the exact GitHub Pages URL to Site URL / Redirect URLs, for example `https://ORG.github.io/REPOSITORY/`. Add any approved custom domain separately.
4. In **Authentication → Providers**, enable Email. Configure email confirmations and SMTP sender settings according to municipal policy. Test invite delivery before inviting staff.
5. In **Project Settings → API**, copy the project URL and publishable/anon key to `src/config.js`. Never copy the service-role key into frontend code.
6. Deploy both functions using the Supabase CLI from this repository:

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase functions deploy admin-create-user
   supabase functions deploy schedule-action
   ```

   The functions read Supabase environment variables supplied by the Supabase runtime. If your CLI/project configuration requires explicit function secrets, set them with `supabase secrets set ...` from a secure terminal, never in Git.
7. Create the first admin account through Supabase Auth (Dashboard → Authentication → Users → Add user, or invite your approved admin email). Once that user has accepted the invitation and a profile exists, promote that **specific UUID** using SQL Editor:

   ```sql
   update public.profiles
   set role = 'admin', active = true, display_name = 'Portal Administrator'
   where id = 'REPLACE_WITH_APPROVED_AUTH_USER_UUID';
   ```

   Do not guess the UUID and do not promote an email without verifying the account identity. There should be very few administrators.
8. Test the admin invitation workflow by creating an operator/officer account. The Edge Function permits only an authenticated active admin; users cannot self-select their role.

## 3. Real GIS data import

Do not import the uploaded HTML's demo coordinates as real data. Prepare approved GIS layers first.

Recommended staging workflow for SHP/GPKG/DWG-derived data:

1. In QGIS, validate geometry and IDs; repair invalid geometries; remove duplicates; confirm asset types and field mapping; preserve source IDs in a field such as `asset_code`.
2. Reproject/export map layers to **EPSG:4326** for the browser-facing map. Retain a source CRS / original file separately for engineering work. Ensure coordinates are longitude/latitude, not projected easting/northing.
3. Use a restricted secure workstation and a direct PostgreSQL connection/connection string stored only in a temporary environment variable or local password file (never in Git) to load layers into staging tables with `ogr2ogr`. Example shape:

   ```bash
   ogr2ogr -f PostgreSQL "$PG_CONN" approved_pipelines.gpkg \
     -nln staging_pipelines -lco GEOMETRY_NAME=geom -t_srs EPSG:4326
   ```

   `PG_CONN` means your locally configured connection string; do not replace it with a committed literal containing a password. Repeat for each source layer using a distinct staging table.
4. Review the staging table's actual column names and geometry type, then map into `network_assets(asset_code, asset_type, name, geom, properties, verification, public_visible, created_by)` using a reviewed SQL `INSERT ... SELECT`. Mark records `verified` only after formal QA. Keep `public_visible=false` by default. The exact mapping SQL depends on your source field names and is intentionally not guessed here.
5. Import water meters into `water_meters` with unique `meter_code` and valid Point geometry. Put connection/customer/phone details only in `water_meter_private`; never place these fields in `properties`, map popup JSON, or public GeoJSON.
6. Populate `distribution_schedules` and `schedule_valves` only after matching zone and valve IDs. Test data in a staging project before production.
7. Confirm spatial extent, SRID, geometry validity, counts by asset type, duplicate IDs, missing attributes, and several known locations against QGIS before allowing use.

For small GeoJSON datasets, a controlled staging import is still preferred over a public browser-side upload. Do not expose database credentials in an upload script.

## 4. GitHub Pages deployment

1. Commit only frontend files and SQL/Edge Function source after code review. No `.env`, database credentials, real customer records, private exports, or service-role key.
2. Push to the existing repository's configured deployment branch. GitHub Pages will publish `index.html` and static modules.
3. Open the exact Pages URL over HTTPS. Test sign-in, session refresh, sign-out, map, tables, and invitation flows.
4. Browser console/network errors should be checked. A blank map commonly means placeholder Supabase settings, failed RPC, wrong Pages base path, blocked tile requests, or RLS denied rows.
5. Confirm the map tile provider's usage policy and attribution. OpenStreetMap standard tiles are not a guaranteed unlimited production tile service; for sustained municipal use, select an approved provider or self-hosted tiles.

## 5. Role and data policy (baseline)

- **Citizen:** only published schedules and explicitly public, verified ward/zone boundaries; no exact pipeline/valve layer by default.
- **Operator:** assigned operational workflow and staff GIS access; do not expose customer identifiers.
- **Officer:** review/approve/publish schedules and maintain GIS/meter records.
- **Administrator:** user invitations, account disablement and administration.
- **Audit:** audit events are read-only to clients; trusted Edge Functions write events. Do not add client-side INSERT/UPDATE/DELETE policies to the audit table.

This baseline is deliberately restrictive. Confirm it with Latur Municipal Corporation before go-live. Public visibility is controlled by both RLS and `public_visible`; never rely on the frontend to hide a layer.

## 6. Required acceptance tests before go-live

- [ ] Unauthenticated user cannot see private asset geometry or staff schedules.
- [ ] Citizen cannot query pipeline, valve, meter customer data, private schedules or audit records directly through REST/RPC.
- [ ] Operator cannot invite users, approve/publish schedules, edit GIS asset verification, or view private meter/customer details.
- [ ] Operator cannot start a schedule assigned to another operator.
- [ ] Only admin can invite accounts; invited accounts cannot choose or elevate their own role.
- [ ] Schedule state changes are only possible through the Edge Function; direct table UPDATE is denied.
- [ ] Audit events record actor, action, entity and timestamp; authenticated clients cannot alter/delete them.
- [ ] Real meter geometry and status appear correctly on the staff map and meter register; private customer fields never appear in map payloads.
- [ ] GIS CRS, extent, counts, topology/validity and ID uniqueness are checked against the source data.
- [ ] Test English/Marathi text, narrow-screen layout, auth expiry, password reset/invite links and failed-network behavior.
- [ ] Backups, recovery, access review, logging/retention, SMTP, privacy notice, and municipal approval are documented.

## Important implementation gaps to close

This scaffold provides the schema and primary auth/data flow, but the first production release still needs a review pass for schedule conflict detection (overlapping operator assignments and shared valves), exact operating-window rules, full asset/meter create-edit forms, bulk GIS import validation, pagination for large datasets, and complete English/Marathi parity for all original screens. Implement schedule transition validation in the Edge Function/transactional database function, not in browser-only JavaScript. Do not treat this initial package as a security certification.


## Ward boundary GeoJSON (Supabase Storage)

The deployed static `index.html` application and the modular `src/map.js` map now load the official ward boundary file from the Supabase Storage object:

- Bucket: `gis-data`
- Object: `Ward_Map.geojson`
- Ward number attribute: `Ward_No`

Ward numbers are normalized (numeric values receive a `Ward ` prefix and two-digit padding) and deduplicated/sorted from the GeoJSON. The citizen complaint ward selector is populated from that canonical list; the map displays the same ward labels and exposes a `ward-data-loaded` browser event for other ward-aware components.

**Storage access requirement:** the current legacy HTML staff login reads a custom `users` table and does not establish a Supabase Auth session. Therefore, if that deployed login is retained, this browser download works reliably only when the object is publicly readable. For a private bucket, migrate staff login to Supabase Auth and configure Storage `SELECT` policies for authorized users (or provide a server-generated signed URL). Do not put a service-role key in the frontend.

On GitHub Pages, commit/push the updated repository and allow the Pages deployment workflow to finish. Confirm that the exact object path is `gis-data/Ward_Map.geojson` (Storage object names are case-sensitive).

## Ward-derived scheduling and complaint data (upgrade 002)

The management schedule selector is populated from the unique `Ward_No` values in the Storage object `gis-data/Ward_Map.geojson`; it no longer uses Gandhi Nagar / Ward 01 sample labels. Public schedule cards read from `distribution_schedules`. Complaint creation inserts into `complaints`, and complaint records are fetched from Supabase and split into unresolved/resolved views. Officer actions can mark complaints In Progress or Resolved.

Before deploying this revision, run `supabase/migrations/002_ward_schedules_complaints.sql` in the Supabase SQL Editor. Confirm Storage access for `gis-data/Ward_Map.geojson`. The migration policies are starter policies; tighten complaint privacy and role/ward-specific authorization before production use. Never add a service-role key to frontend code.
