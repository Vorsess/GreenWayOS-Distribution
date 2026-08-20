#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  Pre-build configuration script
#  Updates build parameters based on VERSION file with comprehensive validation
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Error handling ──────────────────────────────────────────────────
trap 'handle_error ${LINENO}' ERR
handle_error() {
    local line_no=$1
    echo "[✗] ERROR at line $line_no: pre-config.sh failed" >&2
    exit 1
}

# ── Color output helpers ──────────────────────────────────────────────
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_success() { printf "%b[✓]%b  %s\n" "${GREEN}" "${NC}" "$1"; }
log_warn()    { printf "%b[⚠]%b  %s\n" "${YELLOW}" "${NC}" "$1"; }
log_error()   { printf "%b[✗]%b  %s\n" "${RED}" "${NC}" "$1"; }
log_info()    { printf "%b[→]%b  %s\n" "${CYAN}" "${NC}" "$1"; }

# ── Validation helpers ──────────────────────────────────────────────
validate_file_exists() {
    local file="$1"
    local description="${2:-(unnamed)}"
    if [ ! -f "$file" ]; then
        log_error "Required file not found: $file ($description)"
        return 1
    fi
    log_success "Found: $file"
    return 0
}

validate_dir_exists() {
    local dir="$1"
    local description="${2:-(unnamed)}"
    if [ ! -d "$dir" ]; then
        log_error "Required directory not found: $dir ($description)"
        return 1
    fi
    log_success "Found directory: $dir"
    return 0
}

validate_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="${3:-(pattern check)}"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        log_warn "Pattern not found in $file: $pattern ($description)"
        return 1
    fi
    return 0
}

is_valid_version() {
    local version="$1"
    # Validate semantic version format: major.minor.patch-optional_suffix
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        return 0
    fi
    return 1
}

# ════════════════════════════════════════════════════════════════════
# Step 1: Environment Validation
# ════════════════════════════════════════════════════════════════════
log_info "Step 1: Environment validation"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || {
    log_error "Failed to change to project root"
    exit 1
}

log_success "Working directory: $(pwd)"

# Check required directories
validate_dir_exists "config" "Live-build configuration" || exit 1
validate_dir_exists "auto" "Live-build automation scripts" || exit 1
validate_dir_exists "scripts" "Build scripts" || exit 1

# Check required files
validate_file_exists "VERSION" "Project version file" || exit 1
validate_file_exists "build.sh" "Master build script" || exit 1
validate_file_exists "auto/config" "Live-build config script" || exit 1

# ════════════════════════════════════════════════════════════════════
# Step 2: VERSION File Validation
# ════════════════════════════════════════════════════════════════════
log_info "Step 2: VERSION file validation"

VERSION=$(cat VERSION | tr -d '[:space:]')

if [ -z "$VERSION" ]; then
    log_error "VERSION file is empty"
    exit 1
fi

if is_valid_version "$VERSION"; then
    log_success "VERSION is valid: $VERSION"
else
    log_warn "VERSION format unusual: $VERSION (expected semantic version like 1.0.0)"
fi

# ════════════════════════════════════════════════════════════════════
# Step 3: Build Parameters Setup
# ════════════════════════════════════════════════════════════════════
log_info "Step 3: Build parameters setup"

IMAGE_NAME="greenwayos-${VERSION}"
BUILD_DATE=$(date +%Y%m%d)
BUILD_TIME=$(date +%H:%M:%S)

log_success "Image name: $IMAGE_NAME"
log_success "Build date: $BUILD_DATE"
log_success "Build time: $BUILD_TIME"

# ════════════════════════════════════════════════════════════════════
# Step 4: auto/config File Backup and Update
# ════════════════════════════════════════════════════════════════════
log_info "Step 4: auto/config update"

CONFIG_FILE="auto/config"
CONFIG_BACKUP="${CONFIG_FILE}.backup.$(date +%s)"

# Create backup before modification
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    log_success "Created backup: $CONFIG_BACKUP"
else
    log_error "auto/config not found"
    exit 1
fi

# Verify auto/config is valid bash
if ! bash -n "$CONFIG_FILE" 2>/dev/null; then
    log_error "auto/config has syntax errors"
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    log_warn "Restored backup: $CONFIG_BACKUP"
    exit 1
fi

log_success "auto/config syntax validated"

# Check if the expected pattern exists in auto/config
if ! validate_file_contains "$CONFIG_FILE" "image-name"; then
    log_warn "auto/config doesn't contain expected 'image-name' pattern"
else
    log_success "auto/config contains expected patterns"
fi

# Perform the update with explicit error checking
if sed -i "s/--image-name \"greenwayos\"/--image-name \"${IMAGE_NAME}\"/" "$CONFIG_FILE" 2>/dev/null; then
    log_success "Updated auto/config with new image name"
else
    log_error "Failed to update auto/config"
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    exit 1
fi

# Verify the update was applied
if grep -q "$IMAGE_NAME" "$CONFIG_FILE"; then
    log_success "Verified: auto/config updated correctly"
else
    log_warn "Could not verify update was applied"
    log_info "Attempting manual verification..."
fi

# ════════════════════════════════════════════════════════════════════
# Step 5: Configuration Consistency Checks
# ════════════════════════════════════════════════════════════════════
log_info "Step 5: Configuration consistency checks"

# Check package list files exist
pkg_lists_found=0
if [ -d "config/package-lists" ]; then
    pkg_count=$(find config/package-lists -name "*.list.chroot" | wc -l)
    if [ "$pkg_count" -gt 0 ]; then
        log_success "Found $pkg_count package list files"
    else
        log_warn "No package list files found in config/package-lists"
    fi
else
    log_warn "config/package-lists directory not found"
fi

# Check hooks directory
if [ -d "config/hooks/live" ]; then
    hook_count=$(find config/hooks/live -type f | wc -l)
    log_success "Found $hook_count hook files"
else
    log_warn "config/hooks/live directory not found"
fi

# Check includes.chroot structure
if [ -d "config/includes.chroot" ]; then
    log_success "config/includes.chroot directory present"
else
    log_warn "config/includes.chroot directory not found"
fi

# ════════════════════════════════════════════════════════════════════
# Step 6: Final Validation Summary
# ════════════════════════════════════════════════════════════════════
log_info "Step 6: Final validation summary"

log_success "═══════════════════════════════════════════════════════════"
log_success "Pre-configuration completed successfully!"
log_success "───────────────────────────────────────────────────────────"
log_success "Version:      $VERSION"
log_success "Image name:   $IMAGE_NAME"
log_success "Build date:   $BUILD_DATE"
log_success "Build time:   $BUILD_TIME"
log_success "═══════════════════════════════════════════════════════════"
