#!/usr/bin/env python3
import json, re, sys

release_json = sys.argv[1]
dep = sys.argv[2]

with open(release_json) as f:
    d = json.load(f)

for a in d.get('assets', []):
    if re.match(r'^' + re.escape(dep) + r'-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$', a['name']) and 'debug' not in a['name']:
        print(a['browser_download_url'])
        break
