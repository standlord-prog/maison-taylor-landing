-- Maison Taylor: our image library for generation.
-- Models (women, men), shoes, bags, jewelry and other styling pieces, backgrounds.
-- Each item has several reference images (full length, face, back...).
-- A brand's style card says which items it uses and on which shots.
-- Every shot version records which reference images and which instruction made it.

create type public.library_kind as enum (
  'model', 'shoes', 'bag', 'jewelry', 'belt', 'hat', 'eyewear',
  'top', 'bottom', 'outerwear', 'socks', 'background', 'prop'
);

create type public.library_status as enum (
  'draft',     -- uploaded, not yet checked by us
  'approved',  -- can be used in generation
  'retired'    -- kept for history (old versions point to it), not offered any more
);

create table public.library_items (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9_-]{1,60}$'),  -- e.g. model-maya, shoes-white-sneakers
  kind public.library_kind not null,
  name text not null,                           -- shown to brands: "Maya", "White leather sneakers"
  gender text check (gender in ('female', 'male', 'unisex')),
  brand_id uuid references public.brands (id) on delete cascade,  -- null: ours, shared; set: a brand's own accessory
  status public.library_status not null default 'draft',
  -- Model: height_cm, size, age_range, hair, skin, head_to_height (keep 0.12-0.135), build.
  -- Accessory: color, material, style, logo_free.
  -- Background: lightness L, tint, kind (studio, interior, outdoor).
  attrs jsonb not null default '{}'::jsonb,
  tags text[] not null default '{}',            -- style words: minimal, sporty, vintage, streetwear, premium
  known_issues text not null default '',        -- what the generator gets wrong with this item
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.library_items (kind, status);
create index on public.library_items (brand_id);
create index on public.library_items using gin (tags);

create type public.library_image_role as enum (
  'full_front', 'full_back', 'full_side', 'three_quarter', 'face', 'hair_back',  -- models
  'product', 'on_body', 'detail', 'flat',                                       -- accessories and clothes
  'plate'                                                                       -- background sample
);

create table public.library_images (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.library_items (id) on delete cascade,
  role public.library_image_role not null,
  storage_path text not null unique,            -- bucket "library": shared/<item>/<file> or <brand>/<item>/<file>
  is_primary boolean not null default false,    -- the picture brands see when choosing
  width integer, height integer,
  measures jsonb not null default '{}'::jsonb,  -- head_to_height, background L, color Lab...
  created_at timestamptz not null default now()
);
create index on public.library_images (item_id, role);
create unique index library_images_one_primary on public.library_images (item_id) where is_primary;

-- The brand's style card: which model and styling pieces it uses, on which shots.
create table public.brand_style (
  brand_id uuid primary key references public.brands (id) on delete cascade,
  background_item_id uuid references public.library_items (id),
  look_background_item_id uuid references public.library_items (id),  -- shot 6 may use a scene
  avoid text not null default '',               -- "no gloss, no bright colors, no logos"
  notes text not null default '',
  updated_at timestamptz not null default now()
);

create table public.brand_library (
  brand_id uuid not null references public.brands (id) on delete cascade,
  item_id uuid not null references public.library_items (id),
  role text not null,                           -- main_model, second_model, shoes, look_shoes, bag, jewelry...
  shots smallint[] not null default '{1,2,3,4,5,6,7,8}',  -- e.g. bag only on {6}
  for_gender text check (for_gender in ('female', 'male', 'unisex')),  -- brands that sell both
  primary key (brand_id, item_id, role)
);

-- What a particular piece was styled with (copied from the style card when sent, can be swapped).
create table public.piece_library (
  piece_id uuid not null references public.pieces (id) on delete cascade,
  item_id uuid not null references public.library_items (id),
  role text not null,
  shots smallint[] not null default '{1,2,3,4,5,6,7,8}',
  primary key (piece_id, item_id, role)
);

-- How each version was made: so a bad shot can be traced to a model, an image or an instruction.
alter table public.shot_versions
  add column generator text not null default '',          -- nano_banana_pro, seedream_4_5, program:fon_rovno
  add column prompt text not null default '',
  add column ref_images uuid[] not null default '{}',      -- library_images used
  add column ref_sources uuid[] not null default '{}';     -- source_photos used

-- Errors found on shots, the same columns as our error log, so rules can be learned from them.
create table public.shot_issues (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.shot_versions (id) on delete cascade,
  what text not null,                           -- "extra buttons on the bodice"
  found_by text not null,                       -- foncheck, skincheck, color, head, eyes, brand
  critical boolean not null default false,      -- piece doesn't match, other person, broken figure
  outcome text not null default 'open' check (outcome in ('open', 'reshot', 'fixed_by_program', 'kept', 'removed')),
  cause text not null default '',
  library_item_id uuid references public.library_items (id),  -- when the cause is a library item (e.g. a model's big head)
  created_at timestamptz not null default now()
);
create index on public.shot_issues (library_item_id);

-- When a piece is sent, copy the brand's style card onto it.
create or replace function public.copy_style_to_piece() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'submitted' and old.status = 'draft' then
    insert into piece_library (piece_id, item_id, role, shots)
    select new.id, bl.item_id, bl.role, bl.shots from brand_library bl
    join library_items li on li.id = bl.item_id and li.status = 'approved'
    where bl.brand_id = new.brand_id
    on conflict do nothing;
  end if;
  return new;
end $$;
create trigger pieces_copy_style after update of status on public.pieces
  for each row execute function public.copy_style_to_piece();

-- Brand swaps one styling item on its card (only for approved items it may see).
create or replace function public.set_brand_item(b uuid, r text, item uuid, shot_list smallint[] default '{1,2,3,4,5,6,7,8}')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_member(b) or is_staff()) then raise exception 'Brand not found'; end if;
  if not exists (select 1 from library_items where id = item and status = 'approved' and (brand_id is null or brand_id = b)) then
    raise exception 'This item is not available';
  end if;
  delete from brand_library where brand_id = b and role = r;
  insert into brand_library (brand_id, item_id, role, shots) values (b, item, r, shot_list);
end $$;
revoke all on function public.set_brand_item(uuid, text, uuid, smallint[]) from public, anon;
grant execute on function public.set_brand_item(uuid, text, uuid, smallint[]) to authenticated;

-- ---------- row level security ----------

alter table public.library_items enable row level security;
alter table public.library_images enable row level security;
alter table public.brand_style enable row level security;
alter table public.brand_library enable row level security;
alter table public.piece_library enable row level security;
alter table public.shot_issues enable row level security;

-- Brands see our approved items and their own; we see and change everything.
create policy lib_read on public.library_items for select using (
  is_staff() or (status = 'approved' and brand_id is null) or (brand_id is not null and is_member(brand_id)));
create policy lib_staff on public.library_items for all using (is_staff()) with check (is_staff());
-- A brand may add its own accessory; we check and approve it.
create policy lib_brand_add on public.library_items for insert
  with check (brand_id is not null and is_member(brand_id) and status = 'draft' and kind <> 'model');

create policy libimg_read on public.library_images for select using (
  exists (select 1 from public.library_items li where li.id = item_id and (
    is_staff() or (li.status = 'approved' and li.brand_id is null) or (li.brand_id is not null and is_member(li.brand_id)))));
create policy libimg_staff on public.library_images for all using (is_staff()) with check (is_staff());
create policy libimg_brand_add on public.library_images for insert with check (
  exists (select 1 from public.library_items li where li.id = item_id and li.brand_id is not null
          and is_member(li.brand_id) and li.status = 'draft'));

create policy style_read on public.brand_style for select using (is_member(brand_id) or is_staff());
create policy style_edit on public.brand_style for all using (is_member(brand_id) or is_staff())
  with check (is_member(brand_id) or is_staff());

create policy blib_read on public.brand_library for select using (is_member(brand_id) or is_staff());
create policy blib_staff on public.brand_library for all using (is_staff()) with check (is_staff());

create policy plib_read on public.piece_library for select using (is_member(piece_brand(piece_id)) or is_staff());
create policy plib_staff on public.piece_library for all using (is_staff()) with check (is_staff());

create policy issues_staff on public.shot_issues for all using (is_staff()) with check (is_staff());

-- ---------- file storage ----------
-- library: shared/<item_id>/<file> for ours, <brand_id>/<item_id>/<file> for a brand's own accessories.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('library', 'library', false, 30 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy library_files_read on storage.objects for select using (
  bucket_id = 'library' and (public.is_staff() or exists (
    select 1 from public.library_images im join public.library_items li on li.id = im.item_id
    where im.storage_path = objects.name and (
      (li.status = 'approved' and li.brand_id is null) or (li.brand_id is not null and public.is_member(li.brand_id))))));
create policy library_files_staff on storage.objects for insert
  with check (bucket_id = 'library' and public.is_staff());
create policy library_files_brand on storage.objects for insert
  with check (bucket_id = 'library' and public.is_member(public.path_brand(name)));
