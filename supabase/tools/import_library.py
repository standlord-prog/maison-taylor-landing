"""Upload our image library (models, shoes, bags, backgrounds...) from a folder on the Mac to the server.

Folder layout, one folder per item:
    <root>/<kind>/<slug>/item.json      {"name": "Maya", "gender": "female", "attrs": {...}, "tags": [...], "known_issues": "..."}
    <root>/<kind>/<slug>/full_front.jpg  file name starts with the image role:
                                         full_front, full_back, full_side, three_quarter, face, hair_back,
                                         product, on_body, detail, flat, plate (e.g. face_2.jpg works too)
The first full_front (or the first image) becomes the picture brands see.
Items are added as drafts; approve them on the ops page. Re-running skips images already uploaded.

Run:  SUPABASE_URL=... SUPABASE_SERVICE_KEY=... python3 import_library.py ~/enevoo-data/biblioteka
The service key stays on the Mac (it bypasses all access rules); never put it in the site."""
import json, mimetypes, os, sys, urllib.request, urllib.error

URL = os.environ['SUPABASE_URL'].rstrip('/')
KEY = os.environ['SUPABASE_SERVICE_KEY']
KINDS = {'model', 'shoes', 'bag', 'jewelry', 'belt', 'hat', 'eyewear', 'top', 'bottom', 'outerwear', 'socks', 'background', 'prop'}
ROLES = ['full_front', 'full_back', 'full_side', 'three_quarter', 'face', 'hair_back', 'product', 'on_body', 'detail', 'flat', 'plate']
H = {'apikey': KEY, 'Authorization': 'Bearer ' + KEY}


def call(method, path, body=None, headers=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(URL + path, data=data, method=method, headers={**H, 'Content-Type': 'application/json', **(headers or {})})
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f'{method} {path}: {e.code} {e.read().decode()}')


def role_of(name):
    base = os.path.splitext(name)[0].lower()
    return next((r for r in sorted(ROLES, key=len, reverse=True) if base == r or base.startswith(r + '_')), None)


def main(root):
    for kind in sorted(os.listdir(root)):
        if kind not in KINDS:
            continue
        for slug in sorted(os.listdir(os.path.join(root, kind))):
            folder = os.path.join(root, kind, slug)
            meta_path = os.path.join(folder, 'item.json')
            if not os.path.isfile(meta_path):
                print(f'skip {kind}/{slug}: no item.json')
                continue
            meta = json.load(open(meta_path))
            found = call('GET', f'/rest/v1/library_items?slug=eq.{slug}&select=id,library_images(storage_path)')
            if found:
                item = found[0]
            else:
                item = call('POST', '/rest/v1/library_items', {
                    'slug': slug, 'kind': kind, 'name': meta['name'], 'gender': meta.get('gender'),
                    'attrs': meta.get('attrs', {}), 'tags': meta.get('tags', []),
                    'known_issues': meta.get('known_issues', ''), 'notes': meta.get('notes', '')
                }, {'Prefer': 'return=representation'})[0]
                item['library_images'] = []
            have = {i['storage_path'] for i in item['library_images']}
            files = sorted(f for f in os.listdir(folder) if role_of(f) and mimetypes.guess_type(f)[0] in ('image/jpeg', 'image/png', 'image/webp'))
            files.sort(key=lambda f: role_of(f) != 'full_front')
            primary_taken = bool(have)
            for f in files:
                path = f'shared/{item["id"]}/{f}'
                if path in have:
                    continue
                with open(os.path.join(folder, f), 'rb') as fh:
                    call('POST', f'/storage/v1/object/library/{path}', raw=fh.read(), headers={'Content-Type': mimetypes.guess_type(f)[0]})
                call('POST', '/rest/v1/library_images', {'item_id': item['id'], 'role': role_of(f), 'storage_path': path, 'is_primary': not primary_taken})
                primary_taken = True
                print(f'{kind}/{slug}: {f}')
    print('done')


if __name__ == '__main__':
    main(os.path.expanduser(sys.argv[1]))
