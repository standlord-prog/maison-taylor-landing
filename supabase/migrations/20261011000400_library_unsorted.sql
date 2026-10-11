-- Photos imported in bulk (e.g. from the Yandex Disk model agency) arrive without a known role.
-- They get "unsorted" until someone picks the role in ops.html.
alter type public.library_image_role add value if not exists 'unsorted';
