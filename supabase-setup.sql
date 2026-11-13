-- GSXP Lead Capture: Supabase setup
-- Paste this whole file into Supabase > SQL Editor > New query > Run.
-- It is safe to run more than once, and it also upgrades the earlier version.

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  captured_by text,
  captured_by_user uuid default auth.uid(),
  event text,
  name text,
  company text,
  rating text,
  interests text[] not null default '{}',
  notes text,
  badge_id text,
  qr text,
  photo_path text,
  status text not null default 'toscan',
  scan_source text,
  scanned_at timestamptz
);

alter table public.leads add column if not exists scanned_by text;
alter table public.leads add column if not exists exported_at timestamptz;
alter table public.leads alter column status set default 'toscan';

-- Server-side "last changed" time, so phones with wrong clocks can't cause conflicts
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists leads_set_updated_at on public.leads;
create trigger leads_set_updated_at before update on public.leads
  for each row execute function public.set_updated_at();

-- Only signed-in team members can touch the data
alter table public.leads enable row level security;

drop policy if exists "team read" on public.leads;
drop policy if exists "team insert" on public.leads;
drop policy if exists "team update" on public.leads;
drop policy if exists "team delete" on public.leads;
create policy "team read"   on public.leads for select to authenticated using (true);
create policy "team insert" on public.leads for insert to authenticated with check (true);
create policy "team update" on public.leads for update to authenticated using (true);
create policy "team delete" on public.leads for delete to authenticated using (true);

-- Live updates between phones
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'leads'
  ) then
    alter publication supabase_realtime add table public.leads;
  end if;
end $$;

-- Private bucket for badge photos
insert into storage.buckets (id, name, public)
values ('badge-photos', 'badge-photos', false)
on conflict (id) do nothing;

drop policy if exists "team upload photos" on storage.objects;
drop policy if exists "team view photos" on storage.objects;
drop policy if exists "team update photos" on storage.objects;
drop policy if exists "team delete photos" on storage.objects;
create policy "team upload photos" on storage.objects for insert to authenticated with check (bucket_id = 'badge-photos');
create policy "team view photos"   on storage.objects for select to authenticated using (bucket_id = 'badge-photos');
create policy "team update photos" on storage.objects for update to authenticated using (bucket_id = 'badge-photos');
create policy "team delete photos" on storage.objects for delete to authenticated using (bucket_id = 'badge-photos');
