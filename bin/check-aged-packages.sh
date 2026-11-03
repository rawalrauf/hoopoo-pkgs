#!/bin/bash
# Check for packages in edge that are older than 14 days
# and should be promoted to stable

set -euo pipefail

# Temporary: Use 1 hour threshold for testing (normally 14 days)
HOURS_THRESHOLD=1
EXCLUDE_PACKAGES="${1:-}"  # Space-separated list of packages to exclude

echo "=== Checking for aged packages in edge ==="
echo "Threshold: $HOURS_THRESHOLD hours (TESTING MODE - will only return 1 package)"
[[ -n $EXCLUDE_PACKAGES ]] && echo "Excluding: $EXCLUDE_PACKAGES"
echo ""

# Get current timestamp
NOW=$(date +%s)
THRESHOLD_SECONDS=$((HOURS_THRESHOLD * 3600))

# List all .pkg.tar.zst files in edge channel with their last modified time
rclone lsjson "r2:hoopoo-pkgs/edge/x86_64/" \
  --s3-no-check-bucket \
  --files-only \
  --include "*.pkg.tar.zst" \
  --exclude "*.sig" > /tmp/edge-packages.json

# Parse JSON and find packages older than threshold
AGED_PACKAGES=()

while IFS= read -r line; do
  # Extract filename and modified time from JSON
  filename=$(echo "$line" | jq -r '.Name')
  mod_time=$(echo "$line" | jq -r '.ModTime')
  
  # Convert modified time to Unix timestamp
  mod_timestamp=$(date -d "$mod_time" +%s 2>/dev/null || echo 0)
  
  # Calculate age in seconds
  age=$((NOW - mod_timestamp))
  
  # Extract package base name (remove version-release-arch suffix)
  pkg_base=$(echo "$filename" | sed -E 's/-[0-9]+(\.[0-9]+)*-[0-9]+-[^-]+\.pkg\.tar\.zst$//')
  
  # Check if package is older than threshold
  if (( age > THRESHOLD_SECONDS )); then
    age_days=$((age / 86400))
    
    # Check if this package should be excluded
    should_exclude=false
    for exclude_pkg in $EXCLUDE_PACKAGES; do
      if [[ $pkg_base == "$exclude_pkg" ]]; then
        should_exclude=true
        echo "  Skipping $pkg_base (age: ${age_days}d) - excluded by upstream sync"
        break
      fi
    done
    
    if ! $should_exclude; then
      echo "  Found: $pkg_base (age: ${age_days}d)"
      AGED_PACKAGES+=("$pkg_base")
    fi
  fi
done < <(jq -c '.[]' /tmp/edge-packages.json)

# Remove duplicates (in case multiple split packages from same base)
UNIQUE_AGED=($(printf '%s\n' "${AGED_PACKAGES[@]}" | sort -u))

# TESTING: Only return first package
if [[ ${#UNIQUE_AGED[@]} -gt 0 ]]; then
  echo ""
  echo "TESTING MODE: Found ${#UNIQUE_AGED[@]} total aged packages, selecting only the first one"
  UNIQUE_AGED=("${UNIQUE_AGED[0]}")
fi

echo ""
if [[ ${#UNIQUE_AGED[@]} -eq 0 ]]; then
  echo "No aged packages found."
  echo "aged_packages=" >> "$GITHUB_OUTPUT"
else
  echo "Found ${#UNIQUE_AGED[@]} aged package(s) ready for promotion (TESTING: limited to 1):"
  printf '  - %s\n' "${UNIQUE_AGED[@]}"
  echo ""
  echo "aged_packages=${UNIQUE_AGED[*]}" >> "$GITHUB_OUTPUT"
fi
