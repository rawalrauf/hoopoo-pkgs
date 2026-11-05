# Hoopoo Package Repository Roadmap

## Recently Completed (2026-11-05)

- ✅ GPG key migration (D3931CBE26A484582489EEB7394AFBE6E502DB8F)
- ✅ Timestamp preservation (aged-packages workflow compatibility)
- ✅ Simplified deletion logic (reuse files-to-delete.txt)
- ✅ Fixed brave-bin unnecessary rebuilds (epoch handling)
- ✅ Repository cleanup (removed all orphaned packages)

## Planned Improvements

### Workflow Optimization (Next 2-4 weeks)
- **Selective package download** - Currently downloads all 78 packages (~10GB) even when building just one. Optimize to download only packages that won't be rebuilt, or use database patching to eliminate downloads entirely.
- **Remove rebuild-all default** - Make `packages` input required for manual workflow triggers to prevent accidental 6+ hour "rebuild all" runs.
- **Workflow documentation** - Update workflow comments to explain recent changes and document publish workflow retry procedures.

### Architecture Expansion (3-6 months)
- **aarch64 support** - Add ARM64 package repository for modern ARM devices (Apple Silicon, Snapdragon X Elite, AWS Graviton). Requires:
  - GitHub ARM runners or self-hosted ARM build infrastructure
  - Architecture-specific package filtering (skip x86_64-only packages like Chrome, NVIDIA drivers)
  - Dual-architecture database management
  - Testing on real ARM hardware

### Infrastructure Hardening (6-12 months)
- **Mirror redundancy** - Add secondary mirrors for reliability and geographic distribution:
  - Multi-region R2 buckets (US, EU, AP)
  - Alternative cloud storage backup (AWS S3 or Backblaze B2)
  - Mirror health monitoring and automatic failover
  - Optional community mirror program

### Security Enhancements (ongoing)
- **Key management improvements** - Implement proper key rotation policy and secure storage
- **Multiple signers support** - Enable team collaboration with individual signing keys
- **Reproducible builds** - Verify packages match source code for full transparency

---

This roadmap represents achievable goals for building Hoopoo into a production-grade distribution. Items are sequenced based on impact and resource requirements, with infrastructure and security improvements planned as the project scales to serve more users.
