#!/bin/bash
# R2-based package copy script
# Copies packages between R2 channels (edge/stable)

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

# Download only requested packages from source channel
echo "==> Downloading requested packages from $FROM_CHANNEL..."
mkdir -p src
for pkg in $PACKAGES; do
  echo "  Fetching: $pkg-*.pkg.tar.zst"
  rclone copy "r2:hoopoo-pkgs/$FROM_CHANNEL/x86_64/" src/ \
    --include "$pkg-*.pkg.tar.zst" --include "$pkg-*.pkg.tar.zst.sig" \
    --s3-no-check-bucket --transfers 4 --progress
done

# Download existing packages from destination channel (for database rebuild)
echo ""
echo "==> Downloading existing packages from $TO_CHANNEL..."
rclone copy "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" dest/ \
  --include "*.pkg.tar.zst" --include "*.pkg.tar.zst.sig" \
  --s3-no-check-bucket --transfers 8 --progress

# Create output directory for new packages
mkdir -p output

# Copy requested packages
echo ""
echo "==> Copying packages..."
copied=()
for pkg_name in $PACKAGES; do
  found=false
  for file in src/*.pkg.tar.zst; do
    [[ -f $file ]] || continue
    base=$(pkgbase "$(basename "$file")")
    if [[ $base == "$pkg_name" ]]; then
      echo "  Copying: $(basename "$file")"
      cp "$file" output/
      [[ -f "${file}.sig" ]] && cp "${file}.sig" output/
      copied+=("$(basename "$file")")
      found=true
    fi
  done
  
  if ! $found; then
    echo "  Warning: Package '$pkg_name' not found in $FROM_CHANNEL"
  fi
done

if [[ ${#copied[@]} -eq 0 ]]; then
  echo ""
  echo "No packages copied. Exiting."
  exit 0
fi

# Copy existing destination packages that aren't being replaced
echo ""
echo "==> Merging with existing $TO_CHANNEL packages..."
for file in dest/*.pkg.tar.zst; do
  [[ -f $file ]] || continue
  base=$(pkgbase "$(basename "$file")")
  
  # Check if this package is being replaced
  skip=false
  for copied_file in "${copied[@]}"; do
    copied_base=$(pkgbase "$copied_file")
    if [[ $base == "$copied_base" ]]; then
      skip=true
      echo "  Replacing: $(basename "$file") -> $copied_file"
      break
    fi
  done
  
  if ! $skip; then
    cp "$file" output/ 2>/dev/null || true
    [[ -f "${file}.sig" ]] && cp "${file}.sig" output/ 2>/dev/null || true
  fi
done

# Generate repository database
echo ""
echo "==> Generating repository database..."
cd output
shopt -s nullglob
pkgs=(*.pkg.tar.zst)
if (( ${#pkgs[@]} == 0 )); then
  echo "Error: No packages in output directory!"
  exit 1
fi

repo-add hoopoo.db.tar.zst "${pkgs[@]}"
echo "Database created with ${#pkgs[@]} packages"

# Upload to R2
echo ""
echo "==> Uploading to R2 ($TO_CHANNEL)..."

# Upload packages and signatures (skip existing)
rclone copy . "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" \
  --include "*.pkg.tar.zst" --include "*.pkg.tar.zst.sig" \
  --s3-no-check-bucket --transfers 8 --ignore-existing --progress

# Upload database files (overwrite)
rclone copy . "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" \
  --include "hoopoo.db*" --include "hoopoo.files*" \
  --copy-links --s3-no-check-bucket --progress

echo ""
echo "✓ Copy complete!"
echo "  Copied: ${copied[*]}"
echo "  Destination: pkgs.hoopoo.net/$TO_CHANNEL/x86_64/"
