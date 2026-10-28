#!/usr/bin/env python3
import json, re, sys, os, urllib.request, hashlib

github_token = os.environ.get('GITHUB_TOKEN', '')

def vercmp(a, b):
    def split(v):
        return re.findall(r'[0-9]+|[a-zA-Z]+', v)
    def cmp_parts(pa, pb):
        for x, y in zip(pa, pb):
            if x.isdigit() and y.isdigit():
                r = int(x) - int(y)
            else:
                r = (x > y) - (x < y)
            if r != 0:
                return r
        return len(pa) - len(pb)
    ea, va, ra = re.match(r'^(?:(\d+):)?([^-]+?)(?:-(\d+))?$', a or '0').groups()
    eb, vb, rb = re.match(r'^(?:(\d+):)?([^-]+?)(?:-(\d+))?$', b or '0').groups()
    ea, eb = int(ea or 0), int(eb or 0)
    if ea != eb:
        return ea - eb
    r = cmp_parts(split(va or ''), split(vb or ''))
    if r != 0:
        return r
    return int(ra or 0) - int(rb or 0)

def http_get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()

def github_get_json(url):
    headers = {}
    if github_token:
        headers['Authorization'] = f'Bearer {github_token}'
    return json.loads(http_get(url, headers))

def fetch_checksum(url):
    req = urllib.request.Request(url)
    sha = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=60) as r:
        while chunk := r.read(65536):
            sha.update(chunk)
    return sha.hexdigest()

def sync_github(pkgdir, pkgbuild_path, content, watch):
    repo = watch.get('github', '')
    pattern = watch.get('pattern', '')

    try:
        release = github_get_json(f'https://api.github.com/repos/{repo}/releases/latest')
    except Exception as e:
        print(f'  SKIP {pkgdir}: failed to fetch release ({e})')
        return None

    tag = release.get('tag_name', '')
    if not tag:
        print(f'  SKIP {pkgdir}: no tag_name in release')
        return None

    if pattern:
        m = re.search(pattern, tag)
        latest = m.group('version') if m else ''
    else:
        latest = tag.lstrip('v')

    if not latest:
        print(f'  SKIP {pkgdir}: could not parse version from tag {tag}')
        return None

    current_match = re.search(r'^pkgver=(.+)$', content, re.MULTILINE)
    if not current_match:
        print(f'  SKIP {pkgdir}: no pkgver found')
        return None
    current = current_match.group(1).strip()

    if vercmp(latest, current) <= 0:
        print(f'  OK {pkgdir}: {current} is current')
        return None

    print(f'  UPDATE {pkgdir}: {current} -> {latest} (tag: {tag})')

    new_content = re.sub(r'^pkgver=.*$', f'pkgver={latest}', content, flags=re.MULTILINE)
    new_content = re.sub(r'^pkgrel=.*$', 'pkgrel=1', new_content, flags=re.MULTILINE)

    source_match = re.search(r'^source(?:_x86_64)?=\(\s*["\']([^"\']+)["\']', new_content, re.MULTILINE)
    if source_match:
        raw_url = source_match.group(1)
        if '::' in raw_url:
            raw_url = raw_url.split('::')[1]
        source_url = raw_url.replace('${pkgver}', latest).replace('$pkgver', latest) \
                             .replace('${pkgname}', pkgdir).replace('$pkgname', pkgdir)
        if source_url.startswith('http'):
            print(f'  Fetching checksum from {source_url}')
            try:
                checksum = fetch_checksum(source_url)
                print(f'  New sha256: {checksum}')
                new_content = re.sub(
                    r"^sha256sums=\(.*?\)$",
                    f"sha256sums=('{checksum}')",
                    new_content, flags=re.MULTILINE
                )
            except Exception as e:
                print(f'  WARNING: could not fetch checksum ({e}), skipping')
        else:
            print(f'  WARNING: could not resolve source URL, skipping checksum update')

    return new_content

def sync_aur(pkgdir, pkgbuild_path, content, watch):
    aur_pkg = watch.get('aur', pkgdir)

    try:
        info = github_get_json(f'https://aur.archlinux.org/rpc/v5/info/{aur_pkg}')
    except Exception as e:
        print(f'  SKIP {pkgdir}: AUR RPC failed ({e})')
        return None

    results = info.get('results', [])
    if not results:
        print(f'  SKIP {pkgdir}: not found on AUR')
        return None

    aur_version = results[0].get('Version', '')
    latest = re.sub(r'-\d+$', '', aur_version)
    latest = re.sub(r'^\d+:', '', latest)

    current_match = re.search(r'^pkgver=(.+)$', content, re.MULTILINE)
    if not current_match:
        print(f'  SKIP {pkgdir}: no pkgver found')
        return None
    current = current_match.group(1).strip()

    if vercmp(latest, current) <= 0:
        print(f'  OK {pkgdir}: {current} is current')
        return None

    print(f'  UPDATE {pkgdir}: {current} -> {latest} (AUR: {aur_version})')

    try:
        new_content = http_get(f'https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={aur_pkg}').decode()
        print(f'  Pulled fresh PKGBUILD from AUR')
        return new_content
    except Exception as e:
        print(f'  WARNING: could not fetch AUR PKGBUILD ({e}), skipping')
        return None

updated = []

for pkgdir in sorted(os.listdir('pkgbuilds')):
    pkgjson = f'pkgbuilds/{pkgdir}/.hoopoo/package.json'
    pkgbuild_path = f'pkgbuilds/{pkgdir}/PKGBUILD'

    if not os.path.isfile(pkgjson) or not os.path.isfile(pkgbuild_path):
        continue

    with open(pkgjson) as f:
        meta = json.load(f)

    watch = meta.get('upstream', {}).get('watch', {})
    if not watch:
        continue

    with open(pkgbuild_path) as f:
        content = f.read()

    new_content = None

    if 'github' in watch:
        new_content = sync_github(pkgdir, pkgbuild_path, content, watch)
    elif 'aur' in watch:
        new_content = sync_aur(pkgdir, pkgbuild_path, content, watch)
    else:
        print(f'  SKIP {pkgdir}: unknown watch type')
        continue

    if new_content is not None:
        with open(pkgbuild_path, 'w') as f:
            f.write(new_content)
        updated.append(pkgdir)

if updated:
    print(f'\nUpdated: {", ".join(updated)}')
else:
    print('\nAll packages up to date')
