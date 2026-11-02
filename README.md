# Hoopoo Package Repository

Pacman repository for Hoopoo Linux — packages not available in standard Arch repos.

## Add to pacman

First install the keyring to trust Hoopoo packages:

```bash
sudo pacman-key --recv-keys 070030E5D914817BA797F66AAF1C8F036A5E73FD --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 070030E5D914817BA797F66AAF1C8F036A5E73FD
sudo pacman -U https://pkgs.hoopoo.net/stable/x86_64/hoopoo-keyring-1-1-any.pkg.tar.zst
```

Then add to `/etc/pacman.conf`:

```ini
[hoopoo]
SigLevel = Required DatabaseOptional
Server = https://pkgs.hoopoo.net/stable/$arch
```

For testing/latest packages, use the edge channel:

```ini
[hoopoo]
SigLevel = Required DatabaseOptional
Server = https://pkgs.hoopoo.net/edge/$arch
```

## Channels

**Channels:** `edge` → `stable`

- **`edge`** — Latest versions, built automatically on push or upstream update. Packages are tested here before promotion.
- **`stable`** — Production-ready packages, manually promoted from edge after validation.

Packages build once against edge, and the same file is promoted to stable. A published filename never changes its bytes.

## How packages reach users

```
PR merge or upstream update
  └─ publish.yml       build package, sign with GPG, publish to edge
Manual promotion
  └─ copy-packages.yml copy validated packages from edge to stable
```

To ship a change:
1. Update PKGBUILD in a PR or let upstream sync do it automatically
2. Merge to `edge` branch (or sync workflow commits automatically)
3. Package builds and publishes to `edge` within minutes
4. Test the package on `edge`
5. Manually promote to `stable` when ready

## Contributing a package

### Add a new package

1. Fork the repository and create a branch from `edge`.
2. Create the package directory:

   ```bash
   mkdir -p pkgbuilds/my-package
   ```

3. Write `pkgbuilds/my-package/PKGBUILD` following Arch packaging standards:
   - Set `arch=('x86_64')` for x86_64 packages, or `arch=('any')` for architecture-independent packages
   - Pin git sources with `#commit=<sha>` or `#tag=<tag>` (unpinned sources are rejected)
   - Run `updpkgsums` to fill checksums (from `pacman-contrib`)

4. *Optional:* Create `pkgbuilds/my-package/.hoopoo/package.json` to enable automatic upstream updates:

   ```json
   {
     "source": "local",
     "upstream": {
       "watch": {
         "github": "owner/repo",
         "pattern": "v(?P<version>[0-9]+(?:\\.[0-9]+)*)"
       }
     }
   }
   ```

   For projects that only push tags (no GitHub Releases):

   ```json
   {
     "source": "local",
     "upstream": {
       "watch": {
         "git_tags": "https://github.com/owner/repo.git",
         "pattern": "(?P<version>[0-9]+(?:\\.[0-9]+)*)"
       }
     }
   }
   ```

   For AUR packages (auto-pulls updates from AUR):

   ```json
   {
     "source": "local",
     "upstream": {
       "watch": {
         "aur": "package-name"
       }
     }
   }
   ```

5. Open a PR against `edge`. Explain what the package is and how you tested it.

### Update an existing package

- **New upstream version:** If the package has `upstream.watch` configured, the bot updates it automatically on the next scheduled run. Otherwise, update `pkgver` manually, run `updpkgsums`, and reset `pkgrel=1`.
- **Packaging change at same version:** Bump `pkgrel`.
- Never set `epoch` without discussion in the PR first (it's permanent).

### Package metadata (.hoopoo/package.json)

```json
{
  "source": "local",
  
  "gpg_keys": ["KEY_ID_1", "KEY_ID_2"],
  
  "nocheck": "true",
  
  "hoopoo_deps": ["other-hoopoo-package"],
  
  "upstream": {
    "watch": {
      "github": "owner/repo",
      "pattern": "v?(?P<version>[0-9]+(?:\\.[0-9]+)*)"
    }
  }
}
```

**Fields:**
- `source` — Always `"local"` for packages maintained here
- `gpg_keys` — GPG key IDs to import before building (for source signature verification)
- `nocheck` — Set to `"true"` to skip the `check()` function when checkdepends are unavailable
- `hoopoo_deps` — Other Hoopoo packages needed at build time
- `upstream.watch` — Enables automatic upstream version tracking (see examples above)

**Important:** In JSON regex patterns, backslashes must be doubled: `\.` becomes `\\.` and `\(` becomes `\\(`.

## Maintainer tasks

### Promote packages to stable

When packages in `edge` have been tested and are ready for production:

```bash
gh workflow run copy-packages.yml \
  -f source_channel=edge \
  -f destination_channel=stable \
  -f packages="package1 package2 package3"
```

This copies the validated packages from edge to stable with full verification (SHA256 + GPG + pacman structure checks).

### Republish a package

Use this when a publish run failed, or to rebuild a package at the current version:

```bash
gh workflow run publish.yml -f packages="package1 package2"
```

It publishes `edge` branch's version of each named package. To force a rebuild at the same version, bump `pkgrel` first.

### Retire a package

To completely remove a package from the repository:

```bash
gh workflow run unpublish.yml \
  -f packages="package1 package2" \
  -f channels="edge stable" \
  -f delete_pkgbuild=true
```

This removes the package from the databases, deletes the package files from R2 storage, and optionally deletes the PKGBUILD directory and commits the change.

## Repository infrastructure

- **Hosting:** Cloudflare R2 (object storage)
- **Domain:** `pkgs.hoopoo.net` with custom Cloudflare Worker
- **CDN:** Cloudflare global edge network
- **Signing:** GPG key `070030E5D914817BA797F66AAF1C8F036A5E73FD` (Hoopoo \<packages@hoopoo.dev\>)
- **CI/CD:** GitHub Actions
- **Storage:** ~1 GB (edge) + ~1 GB (stable) ≈ $0.03/month
- **Architecture:** x86_64 only

### Verification

All packages are verified at multiple stages:
1. **SHA256 checksums** from database metadata
2. **GPG signatures** with Hoopoo signing key
3. **Pacman structure validation** (`pacman -Qip`)

This three-layer verification (inspired by Omarchy) ensures package integrity throughout the pipeline.
