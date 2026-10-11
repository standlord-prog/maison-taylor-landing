-- Access rules test. Run after supabase_stub.sql and the migrations. Any failed check raises an error.
\set ON_ERROR_STOP 1
insert into auth.users values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@brand-a.com'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@brand-b.com'),
  ('cccccccc-0000-0000-0000-000000000003', 'ops@maison-taylor.com');
insert into public.staff values ('cccccccc-0000-0000-0000-000000000003', 'Ops');

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); execute 'set role authenticated'; end $$;
create function pg_temp.expect_error(q text, why text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'ok, refused: %', why; return; end;
  raise exception 'SHOULD HAVE FAILED: %', why;
end $$;
create function pg_temp.expect(cond boolean, what text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'FAILED: %', what; end if; raise notice 'ok: %', what; end $$;

-- Brand A signs up, makes a piece and uploads a photo
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.create_brand('Brand A') as brand_a \gset
insert into public.pieces (brand_id, title) values (:'brand_a', 'Linen Shirt') returning id as piece_a \gset
select pg_temp.expect_error($$select public.submit_piece('$$ || :'piece_a' || $$')$$, 'send without a photo');
insert into storage.objects (bucket_id, name) values ('sources', :'brand_a' || '/' || :'piece_a' || '/front.jpg');
insert into public.source_photos (piece_id, storage_path) values (:'piece_a', :'brand_a' || '/' || :'piece_a' || '/front.jpg');
select public.submit_piece(:'piece_a');
select pg_temp.expect((select count(*) = 8 from public.shots where piece_id = :'piece_a'), '8 shot slots made');
select pg_temp.expect_error($$insert into public.source_photos (piece_id, storage_path) values ('$$ || :'piece_a' || $$', 'x/late.jpg')$$, 'add photo after sending');
update public.pieces set status = 'ready' where id = :'piece_a';
select pg_temp.expect((select status = 'submitted' from public.pieces where id = :'piece_a'), 'brand cannot set its own status');
reset role;

-- Brand B sees nothing of A
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000002');
select public.create_brand('Brand B') as brand_b \gset
select pg_temp.expect((select count(*) = 0 from public.pieces), 'B cannot see A pieces');
select pg_temp.expect((select count(*) = 0 from storage.objects where bucket_id = 'sources'), 'B cannot see A photos');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('sources', '$$ || :'brand_a' || $$/x/y.jpg')$$, 'B uploads into A folder');
select pg_temp.expect_error($$select public.add_version((select id from public.shots limit 1), 'x', 'generator')$$, 'brand adds a version');
reset role;

-- We generate shot 1, upload it; brand does not see it until we publish
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
select id as shot1 from public.shots where piece_id = :'piece_a' and n = 1 \gset
insert into storage.objects (bucket_id, name) values ('shots', :'brand_a' || '/' || :'piece_a' || '/1/v1.jpg');
select public.add_version(:'shot1', :'brand_a' || '/' || :'piece_a' || '/1/v1.jpg', 'generator', null, '{"background":"ok"}', true) as v1 \gset
reset role;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select pg_temp.expect((select count(*) = 0 from public.shot_versions), 'A cannot see unpublished version');
select pg_temp.expect((select count(*) = 0 from storage.objects where bucket_id = 'shots'), 'A cannot open unpublished file');
select pg_temp.expect_error($$select public.request_edit('$$ || :'shot1' || $$', 'redo')$$, 'edit before shots are ready');
reset role;
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
select public.publish_piece(:'piece_a');
reset role;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select pg_temp.expect((select count(*) = 1 from public.shot_versions), 'A sees published version');
select pg_temp.expect((select count(*) = 1 from storage.objects where bucket_id = 'shots'), 'A opens published file');
select pg_temp.expect((select status = 'ready' from public.pieces where id = :'piece_a'), 'piece is ready');
-- Edits: price comes from the server
select public.request_edit(:'shot1', 'spot_remove', '{}', '{"x":0.5,"y":0.42,"r":0.06}', 'remove the belt') as e1 \gset
select pg_temp.expect((select price_cents = 50 from public.edit_requests where id = :'e1'), 'spot fix costs $0.50');
select pg_temp.expect_error($$select public.request_edit('$$ || :'shot1' || $$', 'spot_remove')$$, 'spot fix without a spot');
select pg_temp.expect_error($$select public.request_edit('$$ || :'shot1' || $$', 'mismatch')$$, 'mismatch with nothing ticked');
select public.request_edit(:'shot1', 'mismatch', '{pockets}') as e2 \gset
select pg_temp.expect((select price_cents = 0 from public.edit_requests where id = :'e2'), 'mismatch is free');
update public.edit_requests set price_cents = 0 where id = :'e1';
select pg_temp.expect((select price_cents = 50 from public.edit_requests where id = :'e1'), 'price unchanged');
reset role;
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000002');
select pg_temp.expect_error($$select public.request_edit('$$ || :'shot1' || $$', 'redo', '{}', null, 'x')$$, 'B edits A shot');
reset role;

-- Our fix comes in as v2; brand can go back to v1 for free
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
insert into storage.objects (bucket_id, name) values ('shots', :'brand_a' || '/' || :'piece_a' || '/1/v2.jpg');
select public.add_version(:'shot1', :'brand_a' || '/' || :'piece_a' || '/1/v2.jpg', 'generator', :'e1', '{}', true, true) as v2 \gset
select pg_temp.expect((select status = 'done' from public.edit_requests where id = :'e1'), 'edit marked done');
reset role;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select pg_temp.expect((select current_version_id = :'v2' from public.shots where id = :'shot1'), 'v2 is current');
select public.use_version(:'shot1', :'v1');
select pg_temp.expect((select current_version_id = :'v1' from public.shots where id = :'shot1'), 'back to v1');
select public.approve_shot(:'shot1');
reset role;

-- Library
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
insert into public.library_items (slug, kind, name, gender, status, attrs) values
  ('model-maya', 'model', 'Maya', 'female', 'approved', '{"height_cm":173,"size":"S","head_to_height":0.128}') returning id as maya \gset
insert into public.library_items (slug, kind, name, gender, status) values ('model-new', 'model', 'New', 'male', 'draft') returning id as draftm \gset
insert into public.library_images (item_id, role, storage_path, is_primary) values (:'maya', 'full_front', 'shared/' || :'maya' || '/full.jpg', true);
insert into storage.objects (bucket_id, name) values ('library', 'shared/' || :'maya' || '/full.jpg');
reset role;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select pg_temp.expect((select count(*) = 1 from public.library_items where kind = 'model'), 'brand sees approved model only');
select pg_temp.expect((select count(*) = 1 from storage.objects where bucket_id = 'library'), 'brand opens model picture');
select public.set_brand_item(:'brand_a', 'main_model', :'maya');
select pg_temp.expect_error($$select public.set_brand_item('$$ || :'brand_a' || $$', 'main_model', '$$ || :'draftm' || $$')$$, 'pick a draft model');
insert into public.library_items (slug, kind, name, brand_id) values ('a-own-bag', 'bag', 'Our tote', :'brand_a');
select pg_temp.expect_error($$insert into public.library_items (slug, kind, name, brand_id) values ('a-model', 'model', 'X', '$$ || :'brand_a' || $$')$$, 'brand adds a model');
insert into public.pieces (brand_id, title) values (:'brand_a', 'Second') returning id as piece2 \gset
insert into public.source_photos (piece_id, storage_path) values (:'piece2', :'brand_a' || '/' || :'piece2' || '/f.jpg');
select public.submit_piece(:'piece2');
select pg_temp.expect((select count(*) = 1 from public.piece_library where piece_id = :'piece2'), 'style card copied onto piece');
reset role;
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000002');
select pg_temp.expect((select count(*) = 0 from public.library_items where slug = 'a-own-bag'), 'B cannot see A own bag');
reset role;
\echo ALL ACCESS CHECKS PASSED
