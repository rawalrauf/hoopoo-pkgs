#!/usr/bin/env python3
import json, re, sys, subprocess, os, urllib.request, hashlib, tempfile

github_token = os.environ.get('GITHUB_TOKEN', '')

def github_get(url):
    req = urllib.request.Request(url)
    if github_token:
        req.add_header('Authorization', f'Bearer {github_token}')
    with urllib.request.urlopen(req) as r:
        return json.load(r)

updated = []

for pkgdir in sorted(os.listdir('pkgbuilds')):
    pkgjson = f'pkgbuilds/{pkgdir}/.hoopoo/package.json'
    pkgbuild = f'pkgbuilds/{pkgdir}/PKGBUILD'

    if not os.path.isfile(pkgjson) or not os.path.isfile(pkgbuild):
        continue

    with open(pkgjson) as f:
        meta = json.load(f)

    watch = meta.get('upstream', {}).get('watch', {})
    repo = watch.get('github', '')
    if not repo:
        continue

    pattern = watch.get('pattern', '')

    try:
        release = github_get(f'https://api.github.com/repos/{repo}/releases/latest')
    except Exception as e:
        print(f'  SKIP {pkgdir}: failed to fetch release ({e})')
        continue

    tag = release.get('tag_name', '')
    if not tag:
        print(f'  SKIP {pkgdir}: no tag_name in release')
        continue

    if pattern:
        m = re.search(pattern, tag)
        latest = m.group('version') if m else ''
    else:
        latest = tag.lstrip('v')

    if not latest:
        print(f'  SKIP {pkgdir}: could not parse version from tag {tag}')
        continue

    with open(pkgbuild) as f:
        content = f.read()

    current_match = re.search(r'^pkgver=(.+)$', content, re.MULTILINE)
    if not current_match:
        print(f'  SKIP {pkgdir}: no pkgver found')
        continue
    current = current_match.group(1).strip()

    result = subprocess.run(['vercmp', latest, current], capture_output=True, text=True)
    cmp = int(result.stdout.strip()) if result.returncode == 0 else 0
    if cmp <= 0:
        print(f'  OK {pkgdir}: {current} is current')
        continue

    print(f'  UPDATE {pkgdir}: {current} -> {latest} (tag: {tag})')

    new_content = re.sub(r'^pkgver=.*$', f'pkgver={latest}', content, flags=re.MULTILINE)
    new_content = re.sub(r'^pkgrel=.*$', 'pkgrel=1', new_content, flags=re.MULTILINE)

    source_match = re.search(r'^source(?:_x86_64)?=\(["\']([^"\']+)["\']', new_content, re.MULTILINE)
    if source_match:
        raw_url = source_match.group(1)
        if '::' in raw_url:
            raw_url = raw_url.split('::')[1]
        env = os.environ.copy()
        env['pkgver'] = latest
        env['pkgname'] = pkgdir
        try:
            source_url = subprocess.run(
                ['bash', '-c', f'pkgver={latest} pkgname={pkgdir} echo "{raw_url}"'],
                capture_output=True, text=True, env=env
            ).stdout.strip()
            if not source_url.startswith('http'):
                source_url = subprocess.run(
                    ['bash', '-c', f'pkgver="{latest}"; pkgname="{pkgdir}"; echo "{raw_url}"'],
                    capture_output=True, text=True
                ).stdout.strip()
        except Exception:
            source_url = ''

        if source_url.startswith('http'):
            print(f'  Fetching checksum from {source_url}')
            try:
                with tempfile.NamedTemporaryFile(delete=False) as tmp:
                    tmppath = tmp.name
                req = urllib.request.Request(source_url)
                with urllib.request.urlopen(req, timeout=60) as r:
                    sha = hashlib.sha256()
                    while chunk := r.read(65536):
                        sha.update(chunk)
                checksum = sha.hexdigest()
                print(f'  New sha256: {checksum}')
                new_content = re.sub(
                    r"^sha256sums=\(.*?\)$",
                    f"sha256sums=('{checksum}')",
                    new_content, flags=re.MULTILINE
                )
            except Exception as e:
                print(f'  WARNING: could not fetch source for checksum ({e}), skipping checksum update')
        else:
            print(f'  WARNING: could not resolve source URL, skipping checksum update')

    with open(pkgbuild, 'w') as f:
        f.write(new_content)

    updated.append(pkgdir)

if updated:
    print(f'\nUpdated: {", ".join(updated)}')
    sys.exit(0)
else:
    print('\nAll packages up to date')
    sys.exit(0)
