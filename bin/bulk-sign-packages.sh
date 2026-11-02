#!/bin/bash
# Bulk sign existing packages that are missing signatures
# This is a one-time operation to sign packages built before GPG signing was implemented

set -euo pipefail

usage() {
  echo "Usage: $0 --channel CHANNEL"
  echo ""
  echo "Options:"
  echo "  --channel   Channel to sign packages in (edge/stable)"
  echo ""
  echo "Environment variables required:"
  echo "  GPG_PRIVATE_KEY     Base64-encoded GPG private key"
  echo "  GPG_PASSPHRASE      GPG key passphrase"
  exit 1
}

CHANNEL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --channel)
      CHANNEL="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -z $CHANNEL ]] && { echo "Error: --channel required"; usage; }
[[ -z ${GPG_PRIVATE_KEY:-} ]] && { echo "Error: GPG_PRIVATE_KEY environment variable required"; exit 1; }
[[ -z ${GPG_PASSPHRASE:-} ]] && { echo "Error: GPG_PASSPHRASE environment variable required"; exit 1; }

echo "=== Bulk Sign Packages ==="
echo "Channel: $CHANNEL"
echo ""

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"

# Import GPG key
echo "==> Importing GPG key..."
echo "$GPG_PRIVATE_KEY" | base64 -d | gpg --batch --import
echo "allow-preset-passphrase" >> ~/.gnupg/gpg-agent.conf
gpg-connect-agent reloadagent /bye 2>/dev/null || true

KEYGRIP=$(gpg --with-keygrip --list-secret-keys Hoopoo 2>/dev/null | grep Keygrip | head -1 | awk '{print $3}')
if [[ -n $KEYGRIP ]]; then
  /usr/lib/gnupg/gpg-preset-passphrase --preset "$KEYGRIP" <<< "$GPG_PASSPHRASE" 2>/dev/null || true
fi

# List all packages in channel
echo ""
echo "==> Listing packages in $CHANNEL..."
rclone lsf "r2:hoopoo-pkgs/$CHANNEL/x86_64/" --files-only --s3-no-check-bucket \
  | grep '\.pkg\.tar\.zst$' > package-list.txt

total=$(wc -l < package-list.txt)
echo "  Found $total packages"

# Check which ones are missing signatures
echo ""
echo "==> Checking for missing signatures..."
mkdir -p packages
unsigned=()

while IFS= read -r pkg; do
  sig="${pkg}.sig"
  if ! rclone lsf "r2:hoopoo-pkgs/$CHANNEL/x86_64/" --files-only --s3-no-check-bucket \
       | grep -qx "$sig"; then
    echo "  Missing signature: $pkg"
    unsigned+=("$pkg")
  fi
done < package-list.txt

if [[ ${#unsigned[@]} -eq 0 ]]; then
  echo ""
  echo "✓ All packages already signed!"
  exit 0
fi

echo ""
echo "==> Found ${#unsigned[@]} unsigned packages"
echo ""

# Download unsigned packages
echo "==> Downloading unsigned packages..."
for pkg in "${unsigned[@]}"; do
  echo "  Downloading: $pkg"
  rclone copy "r2:hoopoo-pkgs/$CHANNEL/x86_64/$pkg" packages/ \
    --s3-no-check-bucket
done

# Sign all packages
echo ""
echo "==> Signing packages..."
signed=0
failed=0

for pkg in "${unsigned[@]}"; do
  pkgfile="packages/$pkg"
  
  if [[ ! -f $pkgfile ]]; then
    echo "  ERROR: File not found: $pkg"
    failed=$((failed + 1))
    continue
  fi
  
  echo "  Signing: $pkg"
  if gpg --batch --yes --pinentry-mode loopback \
     --passphrase "$GPG_PASSPHRASE" \
     --detach-sign "$pkgfile"; then
    signed=$((signed + 1))
  else
    echo "  ERROR: Failed to sign $pkg"
    failed=$((failed + 1))
  fi
done

echo ""
echo "==> Signed: $signed, Failed: $failed"

if [[ $failed -gt 0 ]]; then
  echo "ERROR: Some packages failed to sign"
  exit 1
fi

# Upload signatures to R2
echo ""
echo "==> Uploading signatures to R2..."
cd packages
rclone copy . "r2:hoopoo-pkgs/$CHANNEL/x86_64/" \
  --include "*.sig" --s3-no-check-bucket --progress

echo ""
echo "✓ Bulk signing complete!"
echo "  Signed and uploaded ${#unsigned[@]} signatures to $CHANNEL"
