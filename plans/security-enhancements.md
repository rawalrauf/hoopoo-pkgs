# Security Enhancements

## Key Management Improvements

Implement proper key rotation policy and secure storage.

### Key Rotation Policy

- Define key lifetime (e.g., 2-5 years)
- Document rotation procedure
- Plan for emergency key revocation
- Communicate rotation to users

### Secure Key Storage

- Current: GitHub Actions secrets (adequate for current scale)
- Future options:
  - Hardware security module (HSM)
  - Key management service (AWS KMS, Google Cloud KMS)
  - Offline signing (sign on secure machine, upload signatures)

## Multiple Signers Support

Enable team collaboration with individual signing keys.

### Use Cases

- Multiple maintainers
- Separate keys per package category
- Emergency backup signers

### Implementation

- Multiple keys in keyring package
- Each maintainer signs with their own key
- Users trust all maintainer keys
- Revocation procedure for compromised keys

## Reproducible Builds

Verify packages match source code for full transparency.

### Goals

- Anyone can rebuild and verify packages
- Detect supply chain tampering
- Build confidence in package integrity

### Requirements

- Deterministic build environment
- Document all build dependencies
- Provide build scripts and instructions
- Hash comparison tools

### Challenges

- AUR packages may have non-deterministic builds
- Timestamp variations in build artifacts
- Toolchain version differences
- System environment differences

## Implementation Notes

Security improvements are ongoing. Priority should match threat model and user base size.
