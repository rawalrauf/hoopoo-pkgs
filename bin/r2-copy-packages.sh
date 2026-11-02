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

# Download ALL existing packages from destination channel via rclone
echo ""
echo "==> Downloading all existing packages from $TO_CHANNEL..."
mkdir -p dest
rclone copy "r2:hoopoo-pkgs/$TO_CHANNEL/x86_64/" dest/ \
  --include "*.pkg.tar.zst" --include "*.pkg.tar.zst.sig" \
  --s3-no-check-bucket --transfers 8 --progress

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

# Verify GPG signatures
echo ""
echo "==> Verifying GPG signatures..."
for pkg in src/*.pkg.tar.zst dest/*.pkg.tar.zst; do
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

# Validate package structure with pacman
echo ""
echo "==> Validating package structure with pacman..."
for pkg in src/*.pkg.tar.zst dest/*.pkg.tar.zst; do
  [[ -f $pkg ]] || continue
  if ! pacman -Qip "$pkg" &>/dev/null; then
    echo "  ERROR: Package structure invalid: $(basename "$pkg")"
    failed=$((failed + 1))
  fi
done

if (( failed > 0 )); then
  echo "ERROR: $failed package(s) failed structure validation"
  exit 1
fi

echo "  All packages verified successfully"

# Create output directory for new packages
mkdir -p output

# Copy requested packages to output
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

# Copy all existing destination packages (except ones being replaced)
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

# Generate repository database with ALL packages
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
