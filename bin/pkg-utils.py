#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
REPO = os.environ.get("REPO", "")


def pkgbase(name):
    n = name.replace(".pkg.tar.zst", "")
    parts = n.rsplit("-", 3)
    return parts[0] if len(parts) == 4 else n


def curl_download(url, dest):
    subprocess.run(
        ["curl", "-sL", "-H", f"Authorization: Bearer {GITHUB_TOKEN}", url, "-o", dest],
        check=True,
    )


def gh(*args):
    subprocess.run(
        ["gh", *args],
        env={**os.environ, "GH_TOKEN": GITHUB_TOKEN},
        check=False,
    )


def get_release(tag):
    result = subprocess.run(
        [
            "curl", "-sL",
            "-H", f"Authorization: Bearer {GITHUB_TOKEN}",
            f"https://api.github.com/repos/{REPO}/releases/tags/{tag}",
        ],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def ensure_release(tag):
    r = subprocess.run(
        ["gh", "release", "view", tag, "--repo", REPO],
        env={**os.environ, "GH_TOKEN": GITHUB_TOKEN},
        capture_output=True,
    )
    if r.returncode != 0:
        subprocess.run(
            ["gh", "release", "create", tag,
             "--repo", REPO,
             "--title", tag,
             "--notes", "Automated release",
             "--latest=false"],
            env={**os.environ, "GH_TOKEN": GITHUB_TOKEN},
            check=True,
        )


def copy_packages(packages, src_tag, dst_tag):
    src = get_release(src_tag)
    dst = get_release(dst_tag)

    src_assets = {a["name"]: a["browser_download_url"] for a in src.get("assets", [])}
    dst_assets = {a["name"]: a for a in dst.get("assets", [])}

    to_copy = []
    to_replace = []

    for name, url in src_assets.items():
        if not name.endswith(".pkg.tar.zst") or "-debug-" in name:
            continue
        base = pkgbase(name)
        if base not in packages:
            continue
        to_copy.append((name, url))
        print(f"COPY: {name}")
        for dname in dst_assets:
            if pkgbase(dname) == base and dname != name:
                to_replace.append(dname)
                print(f"  REPLACE: {dname}")

    if not to_copy:
        print("No matching packages found in source release — nothing to copy.")
        return

    ensure_release(dst_tag)

    for name in to_replace:
        print(f"Deleting old {name} from {dst_tag}")
        gh("release", "delete-asset", dst_tag, name, "--repo", REPO, "--yes")
        gh("release", "delete-asset", dst_tag, name + ".sig", "--repo", REPO, "--yes")

    dst = get_release(dst_tag)
    dst_assets = {a["name"]: a for a in dst.get("assets", [])}

    with tempfile.TemporaryDirectory() as tmpdir:
        for name, url in to_copy:
            print(f"Downloading {name}")
            curl_download(url, os.path.join(tmpdir, name))
            sig = name + ".sig"
            if sig in src_assets:
                print(f"Downloading {sig}")
                curl_download(src_assets[sig], os.path.join(tmpdir, sig))

        new_bases = {pkgbase(f) for f in os.listdir(tmpdir) if f.endswith(".pkg.tar.zst")}
        seen = set(new_bases)
        for asset in dst.get("assets", []):
            name = asset["name"]
            if not name.endswith(".pkg.tar.zst") or "-debug-" in name:
                continue
            base = pkgbase(name)
            if base in seen:
                continue
            seen.add(base)
            dest = os.path.join(tmpdir, name)
            if not os.path.exists(dest):
                curl_download(asset["browser_download_url"], dest)

        pkgs_for_db = [f for f in os.listdir(tmpdir) if f.endswith(".pkg.tar.zst")]
        if pkgs_for_db:
            subprocess.run(["repo-add", "hoopoo.db.tar.gz"] + pkgs_for_db, cwd=tmpdir, check=True)

        for asset in ["hoopoo.db.tar.gz", "hoopoo.db", "hoopoo.files.tar.gz", "hoopoo.files"]:
            gh("release", "delete-asset", dst_tag, asset, "--repo", REPO, "--yes")

        upload_files = [
            f for f in os.listdir(tmpdir)
            if f.endswith((".pkg.tar.zst", ".pkg.tar.zst.sig", ".tar.gz"))
            or f in ("hoopoo.db", "hoopoo.files")
        ]
        if upload_files:
            print(f"Uploading to {dst_tag}: {upload_files}")
            subprocess.run(
                ["gh", "release", "upload", dst_tag] + upload_files + ["--repo", REPO, "--clobber"],
                env={**os.environ, "GH_TOKEN": GITHUB_TOKEN},
                cwd=tmpdir,
                check=True,
            )

    print(f"Done. Promoted {[n for n, _ in to_copy]} to {dst_tag}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--packages", required=True, help="Space-separated package names")
    parser.add_argument("--from", dest="src", default="edge")
    parser.add_argument("--to", dest="dst", default="stable")
    args = parser.parse_args()
    copy_packages(args.packages.split(), args.src, args.dst)
