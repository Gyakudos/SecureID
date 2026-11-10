-- SecureID zero-knowledge vault sync.
--
-- Run this once in the Supabase SQL editor for your project.
-- The table stores only the already-encrypted vault envelope. The master
-- password and the derived key never reach the server.

create table if not exists public.vaults (
  user_id uuid primary key references auth.users (id) on delete cascade,
  vault_id text not null,
  envelope text not null,
  content_hash text not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

alter table public.vaults enable row level security;

drop policy if exists "vaults_select_own" on public.vaults;
drop policy if exists "vaults_insert_own" on public.vaults;
drop policy if exists "vaults_update_own" on public.vaults;
drop policy if exists "vaults_delete_own" on public.vaults;

create policy "vaults_select_own"
  on public.vaults
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "vaults_insert_own"
  on public.vaults
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "vaults_update_own"
  on public.vaults
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "vaults_delete_own"
  on public.vaults
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- Optional: keep updated_at honest even if a client forgets to send it.
create or replace function public.touch_vault_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists vaults_touch_updated_at on public.vaults;
create trigger vaults_touch_updated_at
  before update on public.vaults
  for each row
  execute function public.touch_vault_updated_at();

-- Devices that have signed in to the same account.
--
-- This table is only a directory: it stores a random device id, a display
-- name, the platform and timestamps. It never stores vault contents or keys.
create table if not exists public.devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id text not null,
  name text not null default 'SecureID device',
  platform text not null default 'unknown',
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.devices enable row level security;

drop policy if exists "devices_select_own" on public.devices;
drop policy if exists "devices_insert_own" on public.devices;
drop policy if exists "devices_update_own" on public.devices;
drop policy if exists "devices_delete_own" on public.devices;

create policy "devices_select_own"
  on public.devices
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "devices_insert_own"
  on public.devices
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "devices_update_own"
  on public.devices
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "devices_delete_own"
  on public.devices
  for delete
  to authenticated
  using (auth.uid() = user_id);

create index if not exists devices_user_last_seen_idx
  on public.devices (user_id, last_seen desc);
