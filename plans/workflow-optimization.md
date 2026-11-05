# Workflow Optimization

## Selective Package Download

Currently downloads all 78 packages (~10GB) even when building just one. 

### Options

1. **Download only non-rebuilt packages** - Calculate which packages will be rebuilt, download only the rest
2. **Database patching** - Skip package downloads entirely, patch the database to remove packages that will be rebuilt

### Benefits

- Faster workflow start (avoid 10GB download when building single package)
- Reduced bandwidth usage
- Shorter CI times

## Remove Rebuild-All Default

Make `packages` input required for manual workflow triggers to prevent accidental 6+ hour "rebuild all" runs.

Currently leaving the input empty rebuilds everything, which is rarely intended.

## Workflow Documentation

Update workflow comments to explain:
- Recent changes (GPG key migration, timestamp preservation, deletion logic)
- Publish workflow retry procedures
- When to use each workflow trigger option
