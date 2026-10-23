-- Latur Water Network Portal: Supabase/PostGIS initial schema
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;
do $$ begin create type public.app_role as enum ('citizen','operator','officer','admin'); exception when duplicate_object then null; end $$;
do $$ begin create type public.asset_verification as enum ('draft','under_review','verified','rejected'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '', role public.app_role not null default 'citizen',
 operator_code text unique, active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,display_name,role) values(new.id,coalesce(new.raw_user_meta_data->>'display_name',''),'citizen') on conflict(id) do nothing; return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create or replace function public.current_app_role() returns public.app_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid() and active=true $$;

create table if not exists public.network_assets (
 id uuid primary key default gen_random_uuid(), asset_code text not null unique,
 asset_type text not null check(asset_type in ('ward','zone','pipeline','valve','tank','pump','hydrant','other')),
 name text not null, geom extensions.geometry(Geometry,4326) not null, properties jsonb not null default '{}'::jsonb,
 verification public.asset_verification not null default 'draft', public_visible boolean not null default false,
 created_by uuid references auth.users(id), updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check ((asset_type in ('ward','zone') and extensions.geometrytype(geom) in ('POLYGON','MULTIPOLYGON')) or
 (asset_type='pipeline' and extensions.geometrytype(geom) in ('LINESTRING','MULTILINESTRING')) or
 (asset_type in ('valve','tank','pump','hydrant','other') and extensions.geometrytype(geom) in ('POINT','MULTIPOINT')))
);
create index if not exists network_assets_geom_gix on public.network_assets using gist(geom);
create index if not exists network_assets_type_idx on public.network_assets(asset_type);

create table if not exists public.water_meters (
 id uuid primary key default gen_random_uuid(), meter_code text not null unique, asset_code text unique,
 geom extensions.geometry(Point,4326) not null,
 meter_type text not null default 'mechanical' check(meter_type in ('mechanical','smart','bulk','other')),
 status text not null default 'active' check(status in ('active','inactive','faulty','removed','unknown')),
 install_date date, last_reading numeric(14,3), last_reading_at timestamptz,
 public_visible boolean not null default false, notes text not null default '',
 created_by uuid references auth.users(id), updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists water_meters_geom_gix on public.water_meters using gist(geom);
-- Keep customer/connection identifiers separate from general meter records.
create table if not exists public.water_meter_private (
 meter_id uuid primary key references public.water_meters(id) on delete cascade,
 connection_number text, customer_name text, service_address text, phone text,
 notes_private text not null default '', updated_at timestamptz not null default now()
);

create table if not exists public.distribution_schedules (
 id uuid primary key default gen_random_uuid(), schedule_code text not null unique,
 zone_asset_id uuid not null references public.network_assets(id), service_date date not null,
 planned_start time not null, planned_end time not null, operator_id uuid references public.profiles(id),
 status text not null default 'draft' check(status in ('draft','submitted','approved','published','active','paused','completed','interrupted','cancelled','rejected')),
 actual_start timestamptz, actual_end timestamptz, remarks text not null default '',
 created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check(planned_end>planned_start)
);
create index if not exists schedules_date_status_idx on public.distribution_schedules(service_date,status);
create table if not exists public.schedule_valves (
 schedule_id uuid not null references public.distribution_schedules(id) on delete cascade,
 valve_asset_id uuid not null references public.network_assets(id), primary key(schedule_id,valve_asset_id)
);
create table if not exists public.audit_events (
 id bigint generated always as identity primary key, actor_id uuid references auth.users(id), action text not null,
 entity_type text not null, entity_id text not null, details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default now()
);
create index if not exists audit_events_occurred_idx on public.audit_events(occurred_at desc);

alter table public.profiles enable row level security;
alter table public.network_assets enable row level security;
alter table public.water_meters enable row level security;
alter table public.water_meter_private enable row level security;
alter table public.distribution_schedules enable row level security;
alter table public.schedule_valves enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_read_self_or_admin on public.profiles for select to authenticated using(id=auth.uid() or public.current_app_role()='admin');
create policy profiles_admin_update on public.profiles for update to authenticated using(public.current_app_role()='admin') with check(public.current_app_role()='admin');
create policy assets_select_scoped on public.network_assets for select to anon,authenticated using(
 (auth.uid() is not null and public.current_app_role() in ('operator','officer','admin')) or
 (public_visible=true and verification='verified' and asset_type in ('ward','zone')));
create policy assets_insert_staff on public.network_assets for insert to authenticated with check(public.current_app_role() in ('officer','admin') and created_by=auth.uid());
create policy assets_update_staff on public.network_assets for update to authenticated using(public.current_app_role() in ('officer','admin')) with check(public.current_app_role() in ('officer','admin'));
create policy assets_delete_admin on public.network_assets for delete to authenticated using(public.current_app_role()='admin');

create policy meters_select_scoped on public.water_meters for select to anon,authenticated using(
 (auth.uid() is not null and public.current_app_role() in ('operator','officer','admin')) or
 (public_visible=true and public.current_app_role()='citizen'));
create policy meters_insert_staff on public.water_meters for insert to authenticated with check(public.current_app_role() in ('officer','admin') and created_by=auth.uid());
create policy meters_update_staff on public.water_meters for update to authenticated using(public.current_app_role() in ('operator','officer','admin')) with check(public.current_app_role() in ('operator','officer','admin'));
create policy meters_delete_admin on public.water_meters for delete to authenticated using(public.current_app_role()='admin');
create policy meter_private_staff_read on public.water_meter_private for select to authenticated using(public.current_app_role() in ('officer','admin'));
create policy meter_private_officer_write on public.water_meter_private for all to authenticated using(public.current_app_role() in ('officer','admin')) with check(public.current_app_role() in ('officer','admin'));

create policy schedules_select_scoped on public.distribution_schedules for select to anon,authenticated using(status='published' or (auth.uid() is not null and public.current_app_role() in ('operator','officer','admin')));
create policy schedules_insert_staff on public.distribution_schedules for insert to authenticated with check(public.current_app_role() in ('officer','admin') and created_by=auth.uid());
-- Schedule state transitions must go through the Edge Function; direct browser updates are revoked below.
create policy schedules_delete_admin on public.distribution_schedules for delete to authenticated using(public.current_app_role()='admin');
create policy schedule_valves_select_scoped on public.schedule_valves for select to anon,authenticated using(exists(select 1 from public.distribution_schedules s where s.id=schedule_id and (s.status='published' or (auth.uid() is not null and public.current_app_role() in ('operator','officer','admin')))));
create policy schedule_valves_staff_write on public.schedule_valves for all to authenticated using(public.current_app_role() in ('officer','admin')) with check(public.current_app_role() in ('officer','admin'));
create policy audit_read_officer_admin on public.audit_events for select to authenticated using(public.current_app_role() in ('officer','admin'));
revoke insert,update,delete on public.audit_events from anon,authenticated;
revoke update,delete on public.distribution_schedules from anon,authenticated;

-- RLS-filtered GeoJSON FeatureCollection. Citizens see only explicitly public verified ward/zone geometry.
create or replace function public.get_map_features() returns jsonb language sql stable security invoker set search_path=public,extensions as $$
 with features as (
   select jsonb_build_object('type','Feature','id',a.id,'geometry',extensions.ST_AsGeoJSON(a.geom)::jsonb,
     'properties',jsonb_build_object('id',a.asset_code,'type',a.asset_type,'name',a.name,'verified',a.verification,'properties',a.properties)) as feature
   from public.network_assets a
   union all
   select jsonb_build_object('type','Feature','id',m.id,'geometry',extensions.ST_AsGeoJSON(m.geom)::jsonb,
     'properties',jsonb_build_object('id',m.meter_code,'type','water_meter','name',m.meter_code,'verified','verified',
       'properties',jsonb_build_object('meter_type',m.meter_type,'status',m.status,'last_reading',m.last_reading,'last_reading_at',m.last_reading_at))) as feature
   from public.water_meters m
 )
 select jsonb_build_object('type','FeatureCollection','features',coalesce(jsonb_agg(feature),'[]'::jsonb)) from features;
$$;
grant execute on function public.get_map_features() to anon,authenticated;

-- Explicit table grants; RLS policies above remain the row-level authorization boundary.
grant select on public.profiles to authenticated;
grant update on public.profiles to authenticated;
grant select on public.network_assets to anon, authenticated;
grant insert, update, delete on public.network_assets to authenticated;
grant select on public.water_meters to anon, authenticated;
grant insert, update, delete on public.water_meters to authenticated;
grant select, insert, update, delete on public.water_meter_private to authenticated;
grant select on public.distribution_schedules to anon, authenticated;
grant insert on public.distribution_schedules to authenticated;
grant select, insert, update, delete on public.schedule_valves to authenticated;
grant select on public.audit_events to authenticated;
