#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = os.environ["REPO"]
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]


def gh(*args):
    result = subprocess.run(
        ["gh", *args],
        env={**os.environ, "GH_TOKEN": GITHUB_TOKEN},
        capture_output=True,
        text=True,
    )
    return result


def curl_download(url, dest):
    subprocess.run(["curl", "-sL", "-H", f"Authorization: Bearer {GITHUB_TOKEN}", url, "-o", dest], check=True)


def pkgbase(name):
    n = name.replace(".pkg.tar.zst", "")
    parts = n.rsplit("-", 3)
    return parts[0] if len(parts) == 4 else n


def get_release(tag):
    result = subprocess.run(
        ["curl", "-sL", "-H", f"Authorization: Bearer {GITHUB_TOKEN}",
         f"https://api.github.com/repos/{REPO}/releases/tags/{tag}"],
        capture_output=True, text=True, check=True
    )
    return json.loads(result.stdout)


def ensure_stable_release():
    r = gh("release", "view", "stable", "--repo", REPO)
    if r.returncode != 0:
        gh("release", "create", "stable",
           "--repo", REPO,
           "--title", "stable",
           "--notes", "Stable channel — packages promoted from edge.",
           "--latest=false")


def main():
    old_pkgs_file = sys.argv[1] if len(sys.argv) > 1 else "/tmp/remove.txt"
    edge_release_json = sys.argv[2] if len(sys.argv) > 2 else "/tmp/existing-release.json"

    old_pkgs = [l.strip() for l in Path(old_pkgs_file).read_text().splitlines() if l.strip() and l.endswith(".pkg.tar.zst")]

    if not old_pkgs:
        print("No old packages to promote.")
        return

    try:
        edge_release = json.loads(Path(edge_release_json).read_text())
    except Exception:
        print("Could not read edge release JSON, skipping promotion.")
        return

    edge_assets = {a["name"]: a for a in edge_release.get("assets", [])}

    ensure_stable_release()
    stable_release = get_release("stable")
    stable_assets = {a["name"]: a for a in stable_release.get("assets", [])}

    with tempfile.TemporaryDirectory() as tmpdir:
        to_upload = []

        for pkg in old_pkgs:
            if pkg not in edge_assets:
                print(f"SKIP {pkg}: not found in edge release assets")
                continue

            url = edge_assets[pkg]["browser_download_url"]
            dest = os.path.join(tmpdir, pkg)
            print(f"Downloading {pkg} from edge")
            curl_download(url, dest)
            to_upload.append(pkg)

            sig = pkg + ".sig"
            if sig in edge_assets:
                sig_url = edge_assets[sig]["browser_download_url"]
                sig_dest = os.path.join(tmpdir, sig)
                print(f"Downloading {sig} from edge")
                curl_download(sig_url, sig_dest)
                to_upload.append(sig)

        if not to_upload:
            print("Nothing downloaded, skipping promotion.")
            return

        promoted_bases = {pkgbase(p) for p in to_upload if p.endswith(".pkg.tar.zst")}

        for sname in list(stable_assets.keys()):
            if pkgbase(sname) == next((b for b in promoted_bases if pkgbase(sname) == b), None) \
                    and sname not in to_upload:
                print(f"Removing old stable version: {sname}")
                gh("release", "delete-asset", "stable", sname, "--repo", REPO, "--yes")
                if sname + ".sig" in stable_assets:
                    gh("release", "delete-asset", "stable", sname + ".sig", "--repo", REPO, "--yes")

        existing_stable_pkgs = []
        for sname, sasset in stable_assets.items():
            if not sname.endswith(".pkg.tar.zst") or "-debug-" in sname:
                continue
            if pkgbase(sname) in promoted_bases:
                continue
            dest = os.path.join(tmpdir, sname)
            if not os.path.exists(dest):
                curl_download(sasset["browser_download_url"], dest)
            existing_stable_pkgs.append(sname)

        pkgs_for_db = [f for f in os.listdir(tmpdir) if f.endswith(".pkg.tar.zst")]
        if pkgs_for_db:
            subprocess.run(
                ["repo-add", "hoopoo.db.tar.gz"] + pkgs_for_db,
                cwd=tmpdir, check=True
            )

        for asset in ["hoopoo.db.tar.gz", "hoopoo.db", "hoopoo.files.tar.gz", "hoopoo.files"]:
            gh("release", "delete-asset", "stable", asset, "--repo", REPO, "--yes")

        upload_files = []
        for f in os.listdir(tmpdir):
            if f.endswith((".pkg.tar.zst", ".pkg.tar.zst.sig", ".tar.gz")) or f in ("hoopoo.db", "hoopoo.files"):
                upload_files.append(f)

        if upload_files:
            print(f"Uploading to stable: {upload_files}")
            gh("release", "upload", "stable", *upload_files, "--repo", REPO, "--clobber")
        else:
            print("Nothing to upload to stable.")

        print(f"Promoted to stable: {[p for p in to_upload if p.endswith('.pkg.tar.zst')]}")


if __name__ == "__main__":
    main()
