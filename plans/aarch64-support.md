# aarch64 Support

Add ARM64 package repository for modern ARM devices.

## Target Hardware

- Apple Silicon Macs (M1, M2, M3, M4)
- Snapdragon X Elite laptops
- ARM servers (AWS Graviton, Ampere)
- Other aarch64 devices

## Requirements

### Build Infrastructure

- GitHub ARM runners (Linux ARM64 available)
- Or self-hosted ARM build infrastructure
- Sufficient build time budget (ARM builds may be slower)

### Architecture-Specific Handling

- **Skip x86_64-only packages:**
  - Chrome, Chromium (no official ARM builds)
  - NVIDIA drivers
  - Intel-specific firmware/drivers
  
- **Architecture-specific dependencies:**
  - Different kernel modules
  - ARM bootloader support
  - Device-specific firmware

### Repository Management

- Dual-architecture database management
- Separate package pools: `x86_64/` and `aarch64/`
- Mirror both architectures to R2

### Testing

- Test on real ARM hardware
- Verify bootloader installation
- Test critical packages (kernel, base system, desktop environment)

## Implementation Notes

Most AUR packages are architecture-agnostic (scripts, configs). Main challenge is binary packages and hardware-specific components.
