#!/bin/bash
# R2-based package copy script
# Copies packages between R2 channels (edge/stable)
#
# OPTIMIZATION: Incremental database updates
# - Downloads ONLY destination database (~800 KB)
# - Downloads ONLY packages being promoted
# - Uses repo-add to append to existing database
# - Uploads ONLY new packages + updated database
# - Existing packages stay in R2 (never re-downloaded or re-uploaded)
# - Much faster and scales better as repository grows

set -euo pipefail

usage() {
  echo "Usage: $0 --packages 'pkg1 pkg2 ...' --from CHANNEL --to CHANNEL"
  echo ""
  echo "Options:"
  echo "  --packages  Space-separated list of package names"
  echo "  --from      Source channel (edge/stable)"
  echo "  --to        Destination channel (edge/stable)"
  exit 1
}

# Parse arguments
PACKAGES=""
FROM_CHANNEL=""
TO_CHANNEL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --packages)
      PACKAGES="$2"
      shift 2
      ;;
    --from)
      FROM_CHANNEL="$2"
      shift 2
      ;;
    --to)
      TO_CHANNEL="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -z $PACKAGES ]] && { echo "Error: --packages required"; usage; }
[[ -z $FROM_CHANNEL ]] && { echo "Error: --from required"; usage; }
[[ -z $TO_CHANNEL ]] && { echo "Error: --to required"; usage; }

echo "=== R2 Package Copy ==="
echo "Source: $FROM_CHANNEL"
echo "Destination: $TO_CHANNEL"
echo "Packages: $PACKAGES"
echo ""

# Helper function to extract package base name
pkgbase() {
  local name="${1%.pkg.tar.zst}"
  # Remove version-release-arch suffix (e.g., "pkg-1.2.3-1-x86_64" -> "pkg")
  echo "$name" | sed -E 's/-[0-9]+(\.[0-9]+)*-[0-9]+-[^-]+$//'
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"

# Download source database first to get SHA256 checksums
echo "==> Downloading source database from $FROM_CHANNEL..."
mkdir -p db-src
rclone copy "r2:hoopoo-pkgs/$FROM_CHANNEL/x86_64/" db-src/ \
  --include "hoopoo.db.tar.zst" --s3-no-check-bucket

# Parse source database for package info (name, version, sha256)
declare -A SRC_SHA256
if [[ -f db-src/hoopoo.db.tar.zst ]]; then
  tar -xOf db-src/hoopoo.db.tar.zst --wildcards '*/desc' 2>/dev/null | awk '
    $0 == "%FILENAME%" { getline; fname = $0; next }
    $0 == "%SHA256SUM%" { getline; print fname, $0 }
  ' > /tmp/src-checksums.txt
  
  while read -r filename sha256; do
    SRC_SHA256["$filename"]="$sha256"
  done < /tmp/src-checksums.txt
  
  echo "  Found $(wc -l < /tmp/src-checksums.txt) packages in $FROM_CHANNEL database"
fi

# Download only requested packages from source channel via rclone
echo ""
echo "==> Downloading requested packages from $FROM_CHANNEL..."
mkdir -p src
for pkg in $PACKAGES; do
  echo "  Fetching: $pkg-*.pkg.tar.zst"
  rclone copy "r2:hoopoo-pkgs/$FROM_CHANNEL/x86_64/" src/ \
    --include "$pkg-*.pkg.tar.zst" --include "$pkg-*.pkg.tar.zst.sig" \
    --s3-no-check-bucket --transfers 4 --progress
done

# Download ONLY destination database (incremental approach - no package downloads!)
echo ""
echo "==> Downloading destination database from $TO_CHANNEL..."
mkdir -p dest
rclone copy "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" dest/ \
  --include "hoopoo.db.tar.zst" --include "hoopoo.files.tar.zst" \
  --s3-no-check-bucket 2>/dev/null || echo "No existing database found"

# Verify SHA256 checksums against source database
echo ""
echo "==> Verifying SHA256 checksums..."
failed=0
for pkg in src/*.pkg.tar.zst; do
  [[ -f $pkg ]] || continue
  filename=$(basename "$pkg")
  expected=${SRC_SHA256["$filename"]:-}
  
  if [[ -z $expected ]]; then
    echo "  WARNING: No SHA256 in database for $filename"
    continue
  fi
  
  got=$(sha256sum "$pkg" | awk '{print $1}')
  if [[ $got != "$expected" ]]; then
    echo "  ERROR: SHA256 mismatch for $filename"
    echo "    Expected: $expected"
    echo "    Got:      $got"
    failed=$((failed + 1))
  else
    echo "  ✓ $filename"
  fi
done

if (( failed > 0 )); then
  echo "ERROR: $failed package(s) failed SHA256 verification"
  exit 1
fi

# Verify GPG signatures (only for newly downloaded packages from source)
echo ""
echo "==> Verifying GPG signatures..."
failed=0
for pkg in src/*.pkg.tar.zst; do
  [[ -f $pkg ]] || continue
  sig="${pkg}.sig"
  
  if [[ ! -f $sig ]]; then
    echo "  WARNING: No signature for $(basename "$pkg")"
    continue
  fi
  
  if gpg --batch --verify "$sig" "$pkg" 2>/dev/null; then
    echo "  ✓ $(basename "$pkg")"
  else
    echo "  ERROR: Invalid signature for $(basename "$pkg")"
    failed=$((failed + 1))
  fi
done

if (( failed > 0 )); then
  echo "ERROR: $failed package(s) failed GPG verification"
  exit 1
fi

# Validate package structure with pacman (only for newly downloaded packages)
echo ""
echo "==> Validating package structure with pacman..."
for pkg in src/*.pkg.tar.zst; do
  [[ -f $pkg ]] || continue
  if ! pacman -Qip "$pkg" &>/dev/null; then
    echo "  ERROR: Package structure invalid: $(basename "$pkg")"
    failed=$((failed + 1))
  else
    echo "  ✓ $(basename "$pkg")"
  fi
done

if (( failed > 0 )); then
  echo "ERROR: $failed package(s) failed structure validation"
  exit 1
fi

echo "  All packages verified successfully"

# Create output directory for new packages
mkdir -p output

# Verify requested packages exist and collect all downloaded files
echo ""
echo "==> Preparing packages for promotion..."
requested_found=()
all_pkgs=()
for pkg_name in $PACKAGES; do
  found=false
  for file in src/*.pkg.tar.zst; do
    [[ -f $file ]] || continue
    base=$(pkgbase "$(basename "$file")")
    if [[ $base == "$pkg_name" ]]; then
      if ! $found; then
        requested_found+=("$pkg_name")
        found=true
      fi
    fi
  done
  
  if ! $found; then
    echo "  Warning: Package '$pkg_name' not found in $FROM_CHANNEL"
  fi
done

if [[ ${#requested_found[@]} -eq 0 ]]; then
  echo ""
  echo "No packages to promote. Exiting."
  exit 0
fi

# Collect all downloaded package names (including split packages)
for file in src/*.pkg.tar.zst; do
  [[ -f $file ]] || continue
  base=$(pkgbase "$(basename "$file")")
  echo "  Ready to promote: $(basename "$file")"
  all_pkgs+=("$base")
done

# Check if destination database exists, or if we need to create fresh
echo ""
if [[ -f dest/hoopoo.db.tar.zst ]]; then
  echo "==> Using incremental database update (FAST MODE)..."
  echo "  Existing database found, will append new packages"
  
  # Copy existing database to output
  mkdir -p output
  cp dest/hoopoo.db.tar.zst output/
  cp dest/hoopoo.files.tar.zst output/
  
  # Copy new packages to output
  for file in src/*.pkg.tar.zst; do
    [[ -f $file ]] || continue
    cp "$file" output/
    [[ -f "${file}.sig" ]] && cp "${file}.sig" output/
  done
  
  # Incrementally add ALL downloaded packages to existing database
  cd output
  shopt -s nullglob
  new_pkgs=(*.pkg.tar.zst)
  
  if (( ${#new_pkgs[@]} > 0 )); then
    echo "  Appending ${#new_pkgs[@]} package(s) to database (including split packages)..."
    repo-add hoopoo.db.tar.zst "${new_pkgs[@]}"
    
    # Count total packages in database
    total=$(tar -tf hoopoo.db.tar.zst 2>/dev/null | grep -c '/$' || echo 0)
    echo "  Database now has $total packages total"
  fi
  
else
  echo "==> Creating fresh database (no existing database found)..."
  
  # No existing database, create fresh
  mkdir -p output
  for file in src/*.pkg.tar.zst; do
    [[ -f $file ]] || continue
    cp "$file" output/
    [[ -f "${file}.sig" ]] && cp "${file}.sig" output/
  done
  
  cd output
  shopt -s nullglob
  pkgs=(*.pkg.tar.zst)
  if (( ${#pkgs[@]} == 0 )); then
    echo "Error: No packages in output directory!"
    exit 1
  fi
  
  repo-add hoopoo.db.tar.zst "${pkgs[@]}"
  echo "  Database created with ${#pkgs[@]} packages"
fi

# Upload to R2
echo ""
echo "==> Uploading to R2 ($TO_CHANNEL)..."

# Delete old versions of packages being promoted
echo "  Removing old versions from R2..."
for pkg_name in "${requested_found[@]}"; do
  # List all versions of this package in R2 and delete them
  echo "    Cleaning up old versions of: $pkg_name"
  rclone delete "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" \
    --include "$pkg_name-*.pkg.tar.zst" --include "$pkg_name-*.pkg.tar.zst.sig" \
    --s3-no-check-bucket 2>/dev/null || true
done

# Upload new packages and signatures
echo "  Uploading new package files..."
rclone copy . "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" \
  --include "*.pkg.tar.zst" --include "*.pkg.tar.zst.sig" \
  --s3-no-check-bucket --transfers 8 --progress

# Upload database files (overwrite - these always change)
echo "  Uploading updated database..."
rclone copy . "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" \
  --include "hoopoo.db.tar.zst" --include "hoopoo.db" \
  --include "hoopoo.files.tar.zst" --include "hoopoo.files" \
  --exclude "*.old" --exclude "*.gz" \
  --copy-links --s3-no-check-bucket --progress

echo ""
echo "✓ Copy complete!"
echo "  Promoted packages: ${all_pkgs[*]}"
echo "  Destination: pkgs.hoopoo.net/$TO_CHANNEL/x86_64/"
echo ""
echo "Note: Old versions of promoted packages were replaced. Other packages remain unchanged."
