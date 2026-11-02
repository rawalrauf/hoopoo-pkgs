#!/bin/bash
# Remove packages from hoopoo repository channels
# 
#   unpublish-packages --channel <channel> --packages <pkg1> <pkg2> ...
#
# What it does:
#   1. Downloads current database from R2
#   2. Uses repo-remove to remove package entries
#   3. Uploads updated database back to R2
#   4. Package files stay in R2 (immutable, no cost)
#   5. Users won't see the package anymore (removed from database)

set -euo pipefail

usage() {
  echo "Usage: $0 --channel CHANNEL --packages PACKAGE1 PACKAGE2 ..."
  echo ""
  echo "Options:"
  echo "  --channel    Channel to remove from (edge/stable)"
  echo "  --packages   Space-separated list of packages to remove"
  echo ""
  echo "Example:"
  echo "  $0 --channel edge --packages linux-ptl nvidia-580xx-dkms"
  exit 1
}

CHANNEL=""
PACKAGES=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --channel)
      CHANNEL="$2"
      shift 2
      ;;
    --packages)
      PACKAGES="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -z $CHANNEL ]] && { echo "Error: --channel required"; usage; }
[[ -z $PACKAGES ]] && { echo "Error: --packages required"; usage; }

echo "=== Unpublish Packages ==="
echo "Channel: $CHANNEL"
echo "Packages: $PACKAGES"
echo ""

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"

# Download current database
echo "==> Downloading current database from $CHANNEL..."
mkdir -p repo

if ! rclone copy "r2:hoopoo-pkgs/$CHANNEL/x86_64/" repo/ \
     --include "hoopoo.db.tar.zst" --include "hoopoo.files.tar.zst" \
     --s3-no-check-bucket 2>/dev/null; then
  echo "ERROR: Could not download database from $CHANNEL"
  exit 1
fi

if [[ ! -f repo/hoopoo.db.tar.zst ]]; then
  echo "ERROR: No database found in $CHANNEL"
  exit 1
fi

# Count entries before
before=$(tar -tf repo/hoopoo.db.tar.zst 2>/dev/null | grep -c '/$' || echo 0)
echo "  Current database has $before entries"

# Find package names from bases
echo ""
echo "==> Finding packages to remove..."
pkg_array=($PACKAGES)
remove_list=()

for base in "${pkg_array[@]}"; do
  # Extract package names that match this base
  names=$(tar -xOf repo/hoopoo.db.tar.zst --wildcards '*/desc' 2>/dev/null | \
    awk -v base="$base" '
      /^%NAME%$/ { getline name }
      /^%BASE%$/ { getline pkgbase; if (pkgbase == base) print name }
    ')
  
  if [[ -n $names ]]; then
    while IFS= read -r name; do
      echo "  Found: $name (from $base)"
      remove_list+=("$name")
    done <<< "$names"
  else
    echo "  Warning: $base not found in $CHANNEL database"
  fi
done

if [[ ${#remove_list[@]} -eq 0 ]]; then
  echo ""
  echo "No packages to remove"
  exit 0
fi

# Remove packages from database
echo ""
echo "==> Removing packages from database..."
cd repo
repo-remove hoopoo.db.tar.zst "${remove_list[@]}"

# Create symlinks
ln -sf hoopoo.db.tar.zst hoopoo.db
ln -sf hoopoo.files.tar.zst hoopoo.files

# Count entries after
after=$(tar -tf hoopoo.db.tar.zst 2>/dev/null | grep -c '/$' || echo 0)
removed=$((before - after))

echo "  Removed $removed entries"
echo "  Database now has $after entries"

if (( removed != ${#remove_list[@]} )); then
  echo "WARNING: Expected to remove ${#remove_list[@]} entries, but removed $removed"
fi

# Upload updated database
echo ""
echo "==> Uploading updated database to R2..."
rclone copy . "r2:hoopoo-pkgs/$CHANNEL/x86_64/" \
  --include "hoopoo.db*" --include "hoopoo.files*" \
  --copy-links --s3-no-check-bucket

echo ""
echo "✓ Removed ${#remove_list[@]} package(s) from $CHANNEL"
echo ""
echo "Note: Package files remain in R2 (immutable URLs, zero cost)"
