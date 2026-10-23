-- Apply after 001_initial_schema.sql. Adds GeoJSON Ward_No linkage to the existing schema.
-- Existing zone-based schedules remain supported; ward-based schedules can omit zone_asset_id.

alter table public.distribution_schedules alter column zone_asset_id drop not null;
alter table public.distribution_schedules add column if not exists ward_no text;
alter table public.distribution_schedules add column if not exists schedule_code text;
update public.distribution_schedules set schedule_code = 'SCH-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)) where schedule_code is null;
alter table public.distribution_schedules alter column schedule_code set not null;
create unique index if not exists distribution_schedule_ward_date_unique
  on public.distribution_schedules(ward_no, service_date) where ward_no is not null;
create index if not exists distribution_schedules_ward_date_idx on public.distribution_schedules(ward_no, service_date);

create table if not exists public.complaints (
  id uuid primary key default gen_random_uuid(),
  reference_no text not null unique,
  mobile_number text,
  ward_no text not null,
  complaint_type text not null,
  description text not null,
  status text not null default 'Unresolved' check (status in ('Unresolved','In Progress','Resolved','Closed')),
  officer_remark text,
  latitude double precision,
  longitude double precision,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists complaints_ward_status_created_idx on public.complaints(ward_no, status, created_at desc);

alter table public.distribution_schedules enable row level security;
alter table public.complaints enable row level security;

-- Public schedule display uses published rows; retain existing staff scoped policies from migration 001.
drop policy if exists "ward schedules public read" on public.distribution_schedules;
create policy "ward schedules public read" on public.distribution_schedules
  for select to anon, authenticated using (lower(status) = 'published');

-- Complaint insert is available to citizens. Staff reads/updates must be authenticated.
drop policy if exists "citizen complaint insert" on public.complaints;
create policy "citizen complaint insert" on public.complaints
  for insert to anon, authenticated with check (true);
drop policy if exists "authenticated staff complaint read" on public.complaints;
create policy "authenticated staff complaint read" on public.complaints
  for select to authenticated using (auth.uid() is not null);
drop policy if exists "authenticated staff complaint update" on public.complaints;
create policy "authenticated staff complaint update" on public.complaints
  for update to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

grant select on public.distribution_schedules to anon, authenticated;
grant insert, update on public.distribution_schedules to authenticated;
grant insert on public.complaints to anon, authenticated;
grant select, update on public.complaints to authenticated;

-- SECURITY NOTE: These are starter policies, not final municipal production policy.
-- Restrict complaint reads/updates to officer/admin roles and enable reference+phone-based
-- citizen status retrieval through a secure RPC before production. Never expose service_role.
