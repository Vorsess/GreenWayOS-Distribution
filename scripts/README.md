# GreenWayOS Build Scripts

This directory contains helper scripts for building GreenWayOS.

## Scripts

### `validate.sh`

Pre-build validation script that performs comprehensive checks:

```bash
bash scripts/validate.sh
```

**Checks:**
- ✓ Project structure validation
- ✓ Bash syntax in all scripts
- ✓ Python syntax for installer
- ✓ Package availability in APT
- ✓ File permissions
- ✓ Security checks (NOPASSWD, hardcoded secrets, etc.)
- ✓ Disk space requirements (min 20GB)
- ✓ Configuration consistency

**Usage:**
```bash
cd debian-live
sudo bash scripts/validate.sh
```

**Output:**
- Returns exit code 0 if all checks pass
- Returns exit code 1 if critical errors found
- Shows warnings for non-critical issues

### `pre-config.sh`

Updates build configuration before `lb config` runs:

```bash
bash scripts/pre-config.sh
```

**Features:**
- Reads version from `VERSION` file
- Updates ISO image name with version tag
- Prepares build environment

**Automatic execution:**
This script is called automatically by `build.sh` as part of preparation.

**Manual execution:**
```bash
bash scripts/pre-config.sh
```

## Typical Build Workflow

```bash
# 1. Validate project
sudo bash scripts/validate.sh

# 2. Run full build (includes pre-config automatically)
sudo bash build.sh

# 3. Resulting files
# - greenwayos-1.0.2-rc1-amd64.hybrid.iso
# - greenwayos-1.0.2-rc1-amd64.hybrid.iso.sha256
# - greenwayos-1.0.2-rc1-amd64.hybrid.iso.md5
# - build.log
```

## Troubleshooting

### Validation fails with package errors

```bash
sudo apt-get update
sudo bash scripts/validate.sh
```

### Pre-config modifies auto/config incorrectly

Restore `auto/config`:
```bash
git checkout auto/config
# or manually edit auto/config
```

### Permission errors

Ensure scripts are executable:
```bash
chmod +x scripts/*.sh auto/build auto/clean auto/config
```

## Adding New Scripts

When adding new scripts:

1. Make them executable: `chmod +x scripts/myscript.sh`
2. Add header comment with description
3. Use `set -e` for error handling
4. Document in this README
5. Call from `build.sh` if needed in preparation phase

## Integration with CI/CD

These scripts are called by GitHub Actions workflow (`.github/workflows/build.yml`):

```yaml
- name: Syntax check
  run: bash -n scripts/validate.sh

- name: Pre-configuration
  run: bash scripts/pre-config.sh
```
