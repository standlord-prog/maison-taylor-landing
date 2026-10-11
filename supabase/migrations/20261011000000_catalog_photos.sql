-- Maison Taylor: catalog photos, first server stage.
-- A brand orders a "piece" (one garment), uploads source photos, we make 8 shots,
-- every change to a shot is a new version, the brand edits through edit requests.

create extension if not exists pgcrypto;

-- ---------- people ----------

-- Our own team (operators). Added by hand in the SQL editor.
create table public.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where user_id = auth.uid());
$$;

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  site_url text,
  created_at timestamptz not null default now()
);

create table public.brand_members (
  brand_id uuid not null references public.brands (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (brand_id, user_id)
);
create index on public.brand_members (user_id);

create or replace function public.is_member(b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.brand_members where brand_id = b and user_id = auth.uid());
$$;

-- ---------- pieces, photos, shots, versions ----------

create type public.piece_status as enum (
  'draft',      -- brand is still adding photos
  'submitted',  -- brand pressed "Make 8 shots", waiting for us
  'in_work',    -- we are generating
  'ready',      -- shots passed checks and are visible to the brand
  'approved'    -- brand approved all 8
);

create table public.pieces (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references public.brands (id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 200),
  product_url text,
  status public.piece_status not null default 'draft',
  styling jsonb not null default '{}'::jsonb,   -- model, shoes, bag, background picked for the brand
  note text not null default '',                -- what the brand wants us to know
  created_by uuid references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  ready_at timestamptz
);
create index on public.pieces (brand_id, created_at desc);
create index on public.pieces (status);

create table public.source_photos (
  id uuid primary key default gen_random_uuid(),
  piece_id uuid not null references public.pieces (id) on delete cascade,
  storage_path text not null unique,            -- bucket "sources": <brand>/<piece>/<file>
  kind text not null default 'front' check (kind in ('front', 'back', 'detail', 'other')),
  created_at timestamptz not null default now()
);
create index on public.source_photos (piece_id);

-- The 8 shots, in the order buyers look.
create table public.shot_angles (
  n smallint primary key,
  name text not null
);
insert into public.shot_angles (n, name) values
  (1, 'Front'), (2, 'Three-quarter'), (3, 'Side'), (4, 'Back'),
  (5, 'In motion'), (6, 'Full look'), (7, 'No model'), (8, 'Close-up');

create table public.shots (
  id uuid primary key default gen_random_uuid(),
  piece_id uuid not null references public.pieces (id) on delete cascade,
  n smallint not null references public.shot_angles (n),
  current_version_id uuid,
  approved_at timestamptz,
  unique (piece_id, n)
);

create table public.shot_versions (
  id uuid primary key default gen_random_uuid(),
  shot_id uuid not null references public.shots (id) on delete cascade,
  v integer not null,
  storage_path text not null unique,            -- bucket "shots": <brand>/<piece>/<n>/v<v>.jpg
  made_by text not null default 'generator' check (made_by in ('generator', 'program', 'manual')),
  edit_request_id uuid,
  checks jsonb not null default '{}'::jsonb,    -- results of background, skin, color, head checks
  check_passed boolean,
  visible_to_brand boolean not null default false,
  created_by uuid references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now(),
  unique (shot_id, v)
);
alter table public.shots
  add constraint shots_current_version_fk foreign key (current_version_id)
  references public.shot_versions (id) on delete set null;

-- ---------- edits ----------

create type public.edit_kind as enum (
  'mismatch',      -- doesn't match the piece: free reshoot (our mistake)
  'background',    -- background on the whole set: free, done by a program
  'tone',          -- shade of the piece: free, done by a program
  'spot_remove',   -- remove an object in a circled spot: $0.50
  'spot_replace',  -- replace an object in a circled spot: $0.50
  'redo'           -- reshoot your way, 2 versions: $2
);

create type public.edit_status as enum ('new', 'in_work', 'done', 'rejected');

create table public.edit_requests (
  id uuid primary key default gen_random_uuid(),
  shot_id uuid not null references public.shots (id) on delete cascade,
  kind public.edit_kind not null,
  issues text[] not null default '{}',          -- ticked items: pockets, buttons, color...
  spot jsonb,                                   -- {"x":0.42,"y":0.31,"r":0.08}, share of width/height
  text text not null default '',
  options jsonb not null default '{}'::jsonb,   -- background color, tone direction, pose, crop...
  price_cents integer not null default 0,
  status public.edit_status not null default 'new',
  answer text not null default '',              -- our note back to the brand
  created_by uuid references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now(),
  done_at timestamptz
);
create index on public.edit_requests (status, created_at);
create index on public.edit_requests (shot_id);
alter table public.shot_versions
  add constraint shot_versions_edit_fk foreign key (edit_request_id)
  references public.edit_requests (id) on delete set null;

-- Price list for edits, in cents. The brand sees the price on the button before pressing it.
create or replace function public.edit_price(k public.edit_kind) returns integer
language sql immutable as $$
  select case k
    when 'mismatch' then 0 when 'background' then 0 when 'tone' then 0
    when 'spot_remove' then 50 when 'spot_replace' then 50
    when 'redo' then 200 end;
$$;

-- ---------- helpers ----------

create or replace function public.piece_brand(p uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select brand_id from public.pieces where id = p;
$$;

create or replace function public.shot_brand(s uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select pc.brand_id from public.shots sh join public.pieces pc on pc.id = sh.piece_id where sh.id = s;
$$;

-- ---------- actions (called from the site) ----------

-- First visit: make a brand and become its owner.
create or replace function public.create_brand(brand_name text, url text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into brands (name, site_url) values (trim(brand_name), nullif(trim(url), '')) returning id into b;
  insert into brand_members (brand_id, user_id, role) values (b, auth.uid(), 'owner');
  return b;
end $$;

-- Brand pressed "Make 8 shots": needs at least one photo; creates the 8 shot slots.
create or replace function public.submit_piece(p uuid) returns void
language plpgsql security definer set search_path = public as $$
declare st piece_status;
begin
  select status into st from pieces where id = p for update;
  if st is null or not (is_member(piece_brand(p)) or is_staff()) then raise exception 'Piece not found'; end if;
  if st <> 'draft' then raise exception 'This piece is already sent'; end if;
  if not exists (select 1 from source_photos where piece_id = p) then raise exception 'Add at least one photo of the piece'; end if;
  update pieces set status = 'submitted', submitted_at = now() where id = p;
  insert into shots (piece_id, n) select p, n from shot_angles on conflict do nothing;
end $$;

-- Brand asks for an edit on one shot. The price comes from the price list, never from the browser.
create or replace function public.request_edit(
  s uuid, k public.edit_kind, issues text[] default '{}', spot jsonb default null,
  txt text default '', opts jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare r uuid; st piece_status;
begin
  select pc.status into st from shots sh join pieces pc on pc.id = sh.piece_id where sh.id = s;
  if st is null or not is_member(shot_brand(s)) then raise exception 'Shot not found'; end if;
  if st not in ('ready', 'approved') then raise exception 'Shots are not ready yet'; end if;
  if k = 'mismatch' and coalesce(array_length(issues, 1), 0) = 0 and coalesce(trim(txt), '') = '' then
    raise exception 'Tick what is off with the piece';
  end if;
  if k in ('spot_remove', 'spot_replace') and spot is null then raise exception 'Tap the spot on the shot'; end if;
  insert into edit_requests (shot_id, kind, issues, spot, text, options, price_cents)
  values (s, k, coalesce(issues, '{}'), spot, coalesce(txt, ''), coalesce(opts, '{}'::jsonb), edit_price(k))
  returning id into r;
  return r;
end $$;

-- Go back to any earlier version: always free.
create or replace function public.use_version(s uuid, ver uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_member(shot_brand(s)) or is_staff()) then raise exception 'Shot not found'; end if;
  if not exists (select 1 from shot_versions where id = ver and shot_id = s and (visible_to_brand or is_staff())) then
    raise exception 'Version not found';
  end if;
  update shots set current_version_id = ver where id = s;
end $$;

create or replace function public.approve_shot(s uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p uuid;
begin
  if not is_member(shot_brand(s)) then raise exception 'Shot not found'; end if;
  update shots set approved_at = now() where id = s and current_version_id is not null returning piece_id into p;
  if p is null then raise exception 'This shot has no picture yet'; end if;
  if not exists (select 1 from shots where piece_id = p and approved_at is null) then
    update pieces set status = 'approved' where id = p;
  end if;
end $$;

-- Ours: a new version of a shot was uploaded to storage. Becomes current; visible once checks pass.
create or replace function public.add_version(
  s uuid, path text, maker text default 'generator', req uuid default null,
  check_result jsonb default '{}'::jsonb, passed boolean default null, show boolean default false
) returns uuid
language plpgsql security definer set search_path = public as $$
declare nv integer; vid uuid;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  select coalesce(max(v), 0) + 1 into nv from shot_versions where shot_id = s;
  insert into shot_versions (shot_id, v, storage_path, made_by, edit_request_id, checks, check_passed, visible_to_brand)
  values (s, nv, path, maker, req, coalesce(check_result, '{}'::jsonb), passed, show)
  returning id into vid;
  update shots set current_version_id = vid, approved_at = null where id = s;
  if req is not null then
    update edit_requests set status = 'done', done_at = now() where id = req;
  end if;
  return vid;
end $$;

-- Ours: show the whole set to the brand.
create or replace function public.publish_piece(p uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  update shot_versions sv set visible_to_brand = true
    from shots sh where sh.id = sv.shot_id and sh.piece_id = p and sv.id = sh.current_version_id;
  update pieces set status = 'ready', ready_at = coalesce(ready_at, now()) where id = p and status in ('submitted', 'in_work');
end $$;

-- ---------- row level security ----------

alter table public.staff enable row level security;
alter table public.brands enable row level security;
alter table public.brand_members enable row level security;
alter table public.pieces enable row level security;
alter table public.source_photos enable row level security;
alter table public.shot_angles enable row level security;
alter table public.shots enable row level security;
alter table public.shot_versions enable row level security;
alter table public.edit_requests enable row level security;

create policy staff_self on public.staff for select using (user_id = auth.uid());

create policy brands_read on public.brands for select using (is_member(id) or is_staff());
create policy brands_edit on public.brands for update using (is_member(id)) with check (is_member(id));

create policy members_read on public.brand_members for select using (is_member(brand_id) or is_staff());

create policy angles_read on public.shot_angles for select using (true);

create policy pieces_read on public.pieces for select using (is_member(brand_id) or is_staff());
create policy pieces_add on public.pieces for insert with check (is_member(brand_id) and status = 'draft');
create policy pieces_edit_draft on public.pieces for update
  using (is_member(brand_id) and status = 'draft') with check (is_member(brand_id) and status = 'draft');
create policy pieces_staff on public.pieces for update using (is_staff()) with check (is_staff());
create policy pieces_delete_draft on public.pieces for delete using (is_member(brand_id) and status = 'draft');

create policy sources_read on public.source_photos for select using (is_member(piece_brand(piece_id)) or is_staff());
create policy sources_add on public.source_photos for insert
  with check (is_member(piece_brand(piece_id)) and (select status from public.pieces where id = piece_id) = 'draft');
create policy sources_delete on public.source_photos for delete
  using (is_member(piece_brand(piece_id)) and (select status from public.pieces where id = piece_id) = 'draft');

create policy shots_read on public.shots for select using (is_member(piece_brand(piece_id)) or is_staff());

create policy versions_read on public.shot_versions for select
  using (is_staff() or (visible_to_brand and is_member(shot_brand(shot_id))));
create policy versions_staff on public.shot_versions for update using (is_staff()) with check (is_staff());

create policy edits_read on public.edit_requests for select using (is_member(shot_brand(shot_id)) or is_staff());
create policy edits_staff on public.edit_requests for update using (is_staff()) with check (is_staff());

-- Everything that changes state goes through the functions above.
revoke all on function public.add_version(uuid, text, text, uuid, jsonb, boolean, boolean) from public, anon;
revoke all on function public.publish_piece(uuid) from public, anon;
revoke all on function public.create_brand(text, text) from public, anon;
revoke all on function public.submit_piece(uuid) from public, anon;
revoke all on function public.request_edit(uuid, public.edit_kind, text[], jsonb, text, jsonb) from public, anon;
revoke all on function public.use_version(uuid, uuid) from public, anon;
revoke all on function public.approve_shot(uuid) from public, anon;
grant execute on function public.add_version(uuid, text, text, uuid, jsonb, boolean, boolean) to authenticated;
grant execute on function public.publish_piece(uuid) to authenticated;
grant execute on function public.create_brand(text, text) to authenticated;
grant execute on function public.submit_piece(uuid) to authenticated;
grant execute on function public.request_edit(uuid, public.edit_kind, text[], jsonb, text, jsonb) to authenticated;
grant execute on function public.use_version(uuid, uuid) to authenticated;
grant execute on function public.approve_shot(uuid) to authenticated;

-- ---------- file storage ----------
-- sources: photos the brand uploads.  <brand_id>/<piece_id>/<file>
-- shots:   our shots and all versions. <brand_id>/<piece_id>/<n>/v<v>.jpg
-- Both private; the site reads them through short-lived signed links.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('sources', 'sources', false, 25 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp', 'image/heic']),
  ('shots', 'shots', false, 25 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.path_brand(path text) returns uuid
language sql immutable as $$
  select case when split_part(path, '/', 1) ~ '^[0-9a-f-]{36}$' then split_part(path, '/', 1)::uuid end;
$$;

create policy sources_files_read on storage.objects for select
  using (bucket_id = 'sources' and (public.is_member(public.path_brand(name)) or public.is_staff()));
create policy sources_files_add on storage.objects for insert
  with check (bucket_id = 'sources' and public.is_member(public.path_brand(name)));
create policy sources_files_delete on storage.objects for delete
  using (bucket_id = 'sources' and public.is_member(public.path_brand(name)));

-- Brand reads a shot file only if that version is visible to it.
create policy shots_files_read on storage.objects for select
  using (bucket_id = 'shots' and (public.is_staff() or exists (
    select 1 from public.shot_versions sv
    where sv.storage_path = objects.name and sv.visible_to_brand and public.is_member(public.path_brand(objects.name)))));
create policy shots_files_staff on storage.objects for insert
  with check (bucket_id = 'shots' and public.is_staff());
