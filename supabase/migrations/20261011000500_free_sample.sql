-- Free sample from free.html: one per brand, and what the brand wants to try.
alter table public.pieces add column free_want text check (free_want in ('photo', 'carousel', 'both'));
create unique index pieces_one_free_per_brand on public.pieces (brand_id) where free_want is not null;

-- A piece can be sent with a product page link instead of photos: we take the photos from the page.
-- A free sample gets one catalog shot (front), or none when the brand only wants the carousel.
create or replace function public.submit_piece(p uuid) returns void
language plpgsql security definer set search_path = public as $$
declare st piece_status; fw text; url text;
begin
  select status, free_want, product_url into st, fw, url from pieces where id = p for update;
  if st is null or not (is_member(piece_brand(p)) or is_staff()) then raise exception 'Piece not found'; end if;
  if st <> 'draft' then raise exception 'This piece is already sent'; end if;
  if not exists (select 1 from source_photos where piece_id = p) and coalesce(trim(url), '') = '' then
    raise exception 'Add a photo of the piece or a link to its page';
  end if;
  update pieces set status = 'submitted', submitted_at = now() where id = p;
  if fw is null then
    insert into shots (piece_id, n) select p, n from shot_angles on conflict do nothing;
  elsif fw in ('photo', 'both') then
    insert into shots (piece_id, n) values (p, 1) on conflict do nothing;
  end if;
end $$;
