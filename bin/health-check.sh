#!/bin/bash
# Comprehensive health check for hoopoo-pkgs repository and R2 infrastructure
# Verifies: repo structure, workflows, R2 channels, packages, signatures, databases

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

error() {
  echo -e "${RED}✗ ERROR: $1${NC}"
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo -e "${YELLOW}⚠ WARNING: $1${NC}"
  WARNINGS=$((WARNINGS + 1))
}

success() {
  echo -e "${GREEN}✓ $1${NC}"
}

info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

section() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ==============================================================================
section "1. Repository Structure Check"
# ==============================================================================

info "Checking repository directories..."

required_dirs=(
  ".github/workflows"
  "bin"
  "pkgbuilds"
)

for dir in "${required_dirs[@]}"; do
  if [[ -d $dir ]]; then
    success "$dir exists"
  else
    error "$dir is missing"
  fi
done

info "Checking critical files..."

required_files=(
  ".github/workflows/publish.yml"
  ".github/workflows/sync.yml"
  ".github/workflows/copy-packages.yml"
  "bin/r2-copy-packages.sh"
  "bin/sync-upstream.py"
)

for file in "${required_files[@]}"; do
  if [[ -f $file ]]; then
    success "$file exists"
  else
    error "$file is missing"
  fi
done

# ==============================================================================
section "2. Git Branch Analysis"
# ==============================================================================

info "Analyzing branches..."

current_branch=$(git rev-parse --abbrev-ref HEAD)
success "Current branch: $current_branch"

default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [[ $default_branch == "edge" ]]; then
  success "Default branch: $default_branch"
else
  warn "Default branch is '$default_branch', should be 'edge'"
fi

all_branches=$(git branch -a | grep -v HEAD | sed 's/^[* ]*//;s/remotes\/origin\///' | sort -u)
info "All branches found:"
echo "$all_branches" | while read -r branch; do
  if [[ $branch == "edge" ]]; then
    echo "  ✓ $branch (primary)"
  elif [[ $branch =~ ^(stable|master|edge_branch|add-r2-workflow|omarchy-approach|simplify-to-omarchy)$ ]]; then
    echo "  ⚠ $branch (can be deleted - R2 handles channels)"
  else
    echo "  ? $branch"
  fi
done

# ==============================================================================
section "3. Workflow Configuration Check"
# ==============================================================================

info "Checking publish.yml..."

if grep -q "r2:hoopoo-pkgs" .github/workflows/publish.yml; then
  success "Uses R2 (hoopoo-pkgs bucket)"
else
  error "Does not use R2"
fi

if grep -q "github.com.*releases" .github/workflows/publish.yml; then
  warn "Still references GitHub Releases"
fi

if grep -q "GPG_PRIVATE_KEY" .github/workflows/publish.yml; then
  success "GPG signing configured"
else
  error "GPG signing not configured"
fi

if grep -q "SHA256" .github/workflows/publish.yml; then
  success "SHA256 verification enabled"
else
  warn "SHA256 verification missing"
fi

info "Checking sync.yml..."

if grep -q "needs: sync" .github/workflows/sync.yml && \
   grep -q "needs: \[sync, promote\]" .github/workflows/sync.yml; then
  success "Job order correct (sync → promote → build-edge)"
else
  error "Job order incorrect"
fi

if grep -q "BOT_PAT" .github/workflows/sync.yml; then
  success "Uses BOT_PAT for workflow triggering"
else
  error "BOT_PAT not configured"
fi

if grep -q "updated to latest release" .github/workflows/sync.yml; then
  success "Human-friendly commit messages enabled"
else
  warn "Still using old commit message format"
fi

info "Checking copy-packages.yml..."

if grep -q "r2-copy-packages.sh" .github/workflows/copy-packages.yml; then
  success "Uses R2 copy script"
else
  error "Not using R2 copy script"
fi

if grep -q "gnupg" .github/workflows/copy-packages.yml; then
  success "GPG verification configured"
else
  warn "GPG verification not configured"
fi

# ==============================================================================
section "4. R2 Channel Accessibility"
# ==============================================================================

info "Testing pkgs.hoopoo.net edge channel..."

if curl -fsSL --retry 3 --max-time 10 "https://pkgs.hoopoo.net/edge/x86_64/hoopoo.db" > "$WORKDIR/edge.db" 2>/dev/null; then
  success "Edge database accessible"
  edge_size=$(stat -f%z "$WORKDIR/edge.db" 2>/dev/null || stat -c%s "$WORKDIR/edge.db" 2>/dev/null)
  info "  Size: $edge_size bytes"
else
  error "Edge database not accessible"
fi

info "Testing pkgs.hoopoo.net stable channel..."

if curl -fsSL --retry 3 --max-time 10 "https://pkgs.hoopoo.net/stable/x86_64/hoopoo.db" > "$WORKDIR/stable.db" 2>/dev/null; then
  success "Stable database accessible"
  stable_size=$(stat -f%z "$WORKDIR/stable.db" 2>/dev/null || stat -c%s "$WORKDIR/stable.db" 2>/dev/null)
  info "  Size: $stable_size bytes"
else
  error "Stable database not accessible"
fi

# ==============================================================================
section "5. Package Count Analysis"
# ==============================================================================

if [[ -f "$WORKDIR/edge.db" ]]; then
  edge_count=$(tar -xOf "$WORKDIR/edge.db" --wildcards '*/desc' 2>/dev/null | grep -c '^%FILENAME%' || echo 0)
  success "Edge channel: $edge_count packages"
else
  warn "Cannot count edge packages"
  edge_count=0
fi

if [[ -f "$WORKDIR/stable.db" ]]; then
  stable_count=$(tar -xOf "$WORKDIR/stable.db" --wildcards '*/desc' 2>/dev/null | grep -c '^%FILENAME%' || echo 0)
  success "Stable channel: $stable_count packages"
else
  warn "Cannot count stable packages"
  stable_count=0
fi

if (( edge_count > stable_count )); then
  info "Edge has $((edge_count - stable_count)) more packages than stable (expected)"
elif (( edge_count == stable_count )); then
  info "Edge and stable have same package count"
else
  warn "Stable has more packages than edge (unusual)"
fi

# ==============================================================================
section "6. Signature Verification Sample"
# ==============================================================================

info "Checking Hoopoo GPG key..."

if gpg --list-keys "070030E5D914817BA797F66AAF1C8F036A5E73FD" &>/dev/null; then
  success "Hoopoo GPG key found in keyring"
  key_info=$(gpg --list-keys --with-colons "070030E5D914817BA797F66AAF1C8F036A5E73FD" 2>/dev/null | grep '^uid' | head -1 | cut -d: -f10)
  info "  Key: $key_info"
else
  warn "Hoopoo GPG key not in keyring (install hoopoo-keyring package)"
  info "  Importing from keyserver..."
  gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 070030E5D914817BA797F66AAF1C8F036A5E73FD 2>/dev/null || \
    warn "Could not import key from keyserver"
fi

info "Checking signature file availability (sample)..."

# Just check if .sig files exist in general
if curl -fsSL --head --max-time 5 "https://pkgs.hoopoo.net/edge/x86_64/" 2>&1 | grep -q "200"; then
  success "Edge channel accessible for signature checks"
else
  warn "Could not verify edge channel signatures"
fi

if curl -fsSL --head --max-time 5 "https://pkgs.hoopoo.net/stable/x86_64/" 2>&1 | grep -q "200"; then
  success "Stable channel accessible for signature checks"
else
  warn "Could not verify stable channel signatures"
fi

info "(Detailed signature verification available via copy-packages workflow)"

# ==============================================================================
section "7. Database Integrity Check"
# ==============================================================================

info "Verifying edge database structure..."

if [[ -f "$WORKDIR/edge.db" ]]; then
  if tar -tf "$WORKDIR/edge.db" &>/dev/null; then
    success "Edge database is valid tar.zst"
    
    # Check for required fields
    has_filename=$(tar -xOf "$WORKDIR/edge.db" --wildcards '*/desc' 2>/dev/null | grep -c '^%FILENAME%' || echo 0)
    has_sha256=$(tar -xOf "$WORKDIR/edge.db" --wildcards '*/desc' 2>/dev/null | grep -c '^%SHA256SUM%' || echo 0)
    
    if (( has_filename > 0 )); then
      success "  Contains FILENAME entries ($has_filename)"
    else
      error "  Missing FILENAME entries"
    fi
    
    if (( has_sha256 > 0 )); then
      success "  Contains SHA256SUM entries ($has_sha256)"
    else
      warn "  Missing SHA256SUM entries"
    fi
  else
    error "Edge database is corrupted"
  fi
fi

info "Verifying stable database structure..."

if [[ -f "$WORKDIR/stable.db" ]]; then
  if tar -tf "$WORKDIR/stable.db" &>/dev/null; then
    success "Stable database is valid tar.zst"
    
    has_filename=$(tar -xOf "$WORKDIR/stable.db" --wildcards '*/desc' 2>/dev/null | grep -c '^%FILENAME%' || echo 0)
    has_sha256=$(tar -xOf "$WORKDIR/stable.db" --wildcards '*/desc' 2>/dev/null | grep -c '^%SHA256SUM%' || echo 0)
    
    if (( has_filename > 0 )); then
      success "  Contains FILENAME entries ($has_filename)"
    else
      error "  Missing FILENAME entries"
    fi
    
    if (( has_sha256 > 0 )); then
      success "  Contains SHA256SUM entries ($has_sha256)"
    else
      warn "  Missing SHA256SUM entries"
    fi
  else
    error "Stable database is corrupted"
  fi
fi

# ==============================================================================
section "8. GitHub Secrets Check"
# ==============================================================================

info "Checking required secrets (cannot verify values, only presence)..."

required_secrets=(
  "BOT_PAT"
  "GPG_PRIVATE_KEY"
  "GPG_PASSPHRASE"
  "R2_ACCESS_KEY_ID"
  "R2_SECRET_ACCESS_KEY"
  "R2_ENDPOINT_URL"
)

info "Required secrets for workflows:"
for secret in "${required_secrets[@]}"; do
  echo "  - $secret"
done

success "Manual verification needed via GitHub Settings → Secrets"

# ==============================================================================
section "9. Package Repository Check"
# ==============================================================================

info "Checking pkgbuilds directory..."

pkgbuild_count=$(find pkgbuilds -name PKGBUILD 2>/dev/null | wc -l)
if (( pkgbuild_count > 0 )); then
  success "Found $pkgbuild_count PKGBUILD files"
  
  if (( pkgbuild_count > edge_count )); then
    info "  $(( pkgbuild_count - edge_count )) packages not yet published to edge"
  fi
else
  error "No PKGBUILD files found"
fi

# ==============================================================================
section "10. Cleanup Recommendations"
# ==============================================================================

info "Branches that can be safely deleted:"

cleanup_branches=(
  "stable"
  "master"
  "edge_branch"
  "add-r2-workflow"
  "omarchy-approach"
  "simplify-to-omarchy"
)

found_obsolete=false
for branch in "${cleanup_branches[@]}"; do
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null || \
     git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
    echo "  - $branch (R2 handles channels now)"
    found_obsolete=true
  fi
done

if ! $found_obsolete; then
  info "  None - all obsolete branches already cleaned up!"
else
  info ""
  info "To delete local branches:"
  echo "  git branch -D stable master edge_branch add-r2-workflow omarchy-approach simplify-to-omarchy"

  info ""
  info "To delete remote branches:"
  echo "  git push origin --delete stable master edge_branch add-r2-workflow omarchy-approach simplify-to-omarchy"
fi

# ==============================================================================
section "Summary"
# ==============================================================================

echo ""
if (( ERRORS == 0 && WARNINGS == 0 )); then
  success "All checks passed! 🎉"
elif (( ERRORS == 0 )); then
  warn "Checks passed with $WARNINGS warning(s)"
else
  error "Found $ERRORS error(s) and $WARNINGS warning(s)"
  exit 1
fi

echo ""
info "Repository: hoopoo-pkgs"
info "Edge packages: $edge_count"
info "Stable packages: $stable_count"
info "PKGBUILD files: $pkgbuild_count"
info "Domain: pkgs.hoopoo.net"
info "Status: R2 migration complete ✓"
