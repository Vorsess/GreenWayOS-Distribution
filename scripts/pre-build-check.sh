#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  GreenWayOS Pre-Build Health Check Script
#  This script validates the build system before running the full build
#  Usage: ./scripts/pre-build-check.sh
# ════════════════════════════════════════════════════════════════════

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKS_PASSED=0

echo ""
echo "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║${NC}  GreenWayOS Pre-Build Health Check${NC}                          ${CYAN}║${NC}"
echo "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Output helpers ──────────────────────────────────────────────────
pass()    { echo -e "${GREEN}✓${NC}  $*"; ((CHECKS_PASSED++)); }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; ((WARNINGS++)); }
error()   { echo -e "${RED}✗${NC}  $*"; ((ERRORS++)); }
section() { echo -e "\n${CYAN}→ $*${NC}"; }

# ════════════════════════════════════════════════════════════════════
#  1. Essential Tools Check
# ════════════════════════════════════════════════════════════════════
section "Essential Tools"

for tool in bash python3 sed grep find dd md5sum sha256sum git; do
    if command -v "$tool" &> /dev/null; then
        pass "$tool is available"
    else
        error "$tool not found (REQUIRED for build)"
    fi
done

for tool in live-build debootstrap grub-mkimage mksquashfs; do
    if command -v "$tool" &> /dev/null; then
        pass "$tool is available"
    else
        warn "$tool not found (will be installed during build)"
    fi
done

# ════════════════════════════════════════════════════════════════════
#  2. Directory Structure
# ════════════════════════════════════════════════════════════════════
section "Directory Structure"

directories=(
    "config"
    "config/bootloaders"
    "config/bootloaders/grub-pc"
    "config/bootloaders/grub-efi"
    "config/hooks"
    "config/hooks/live"
    "config/hooks/normal"
    "config/includes.chroot"
    "config/package-lists"
    "auto"
    "scripts"
)

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        pass "Directory exists: $dir"
    else
        error "Missing directory: $dir"
    fi
done

# ════════════════════════════════════════════════════════════════════
#  3. Critical Files
# ════════════════════════════════════════════════════════════════════
section "Critical Files"

files=(
    "build.sh"
    "VERSION"
    "README.md"
    "auto/config"
    "auto/build"
    "auto/clean"
    "config/bootloaders/grub-pc/grub.cfg"
    "config/bootloaders/grub-efi/grub.cfg"
    "config/package-lists/base.list.chroot"
    "config/hooks/live/50-kernel-symlinks.hook.binary"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        pass "File exists: $file"
    else
        error "Missing file: $file"
    fi
done

# ════════════════════════════════════════════════════════════════════
#  4. Bash Syntax Validation
# ════════════════════════════════════════════════════════════════════
section "Bash Syntax Validation"

bash_files=(
    "build.sh"
    "auto/build"
    "auto/clean"
    "auto/config"
    "scripts/pre-config.sh"
    "scripts/validate.sh"
    "scripts/validate-grub.sh"
)

for file in "${bash_files[@]}"; do
    if [ -f "$file" ]; then
        if bash -n "$file" 2>/dev/null; then
            pass "Syntax OK: $file"
        else
            error "Syntax ERROR in $file"
            bash -n "$file" 2>&1 | head -3 | sed 's/^/        /'
        fi
    fi
done

# ════════════════════════════════════════════════════════════════════
#  5. Hook Syntax Validation
# ════════════════════════════════════════════════════════════════════
section "Hook Syntax Validation"

hook_errors=0
while IFS= read -r hook; do
    if bash -n "$hook" 2>/dev/null; then
        pass "Hook OK: $(basename "$hook")"
    else
        error "Hook syntax ERROR: $(basename "$hook")"
        bash -n "$hook" 2>&1 | head -2 | sed 's/^/        /'
        ((hook_errors++))
    fi
done < <(find config/hooks -type f \( -name "*.chroot" -o -name "*.binary" -o -name "*.hook.*" \))

if [ "$hook_errors" -gt 0 ]; then
    ((ERRORS+=hook_errors))
fi

# ════════════════════════════════════════════════════════════════════
#  6. Python Syntax Validation
# ════════════════════════════════════════════════════════════════════
section "Python Syntax Validation"

python_files=(
    "config/includes.chroot/usr/local/bin/greenwayos-installer"
    "config/includes.chroot/usr/local/bin/greenwayos-installer-gui"
    "config/includes.chroot/usr/local/bin/greenwayos-ctos-hud"
    "config/includes.chroot/usr/local/bin/greenwayos-welcome-legacy"
)

for file in "${python_files[@]}"; do
    if [ -f "$file" ]; then
        if python3 -m py_compile "$file" 2>/dev/null; then
            pass "Python OK: $(basename "$file")"
        else
            warn "Python syntax issue in $(basename "$file") (will check during runtime)"
        fi
    fi
done

if [ -f config/includes.chroot/usr/local/bin/greenwayos-welcome ]; then
    if bash -n config/includes.chroot/usr/local/bin/greenwayos-welcome 2>/dev/null; then
        pass "Shell wrapper OK: greenwayos-welcome"
    else
        warn "Shell syntax issue in greenwayos-welcome"
    fi
fi

# ════════════════════════════════════════════════════════════════════
#  7. GRUB Configuration Analysis
# ════════════════════════════════════════════════════════════════════
section "GRUB Configuration Analysis"

for grub_file in config/bootloaders/grub-pc/grub.cfg config/bootloaders/grub-efi/grub.cfg; do
    if [ -f "$grub_file" ]; then
        
        # Check for required keywords
        if grep -q "menuentry" "$grub_file"; then
            pass "$(basename "$grub_file"): Contains menuentry"
        else
            error "$(basename "$grub_file"): Missing menuentry"
        fi
        
        if grep -q "/live/vmlinuz" "$grub_file"; then
            pass "$(basename "$grub_file"): References kernel"
        else
            error "$(basename "$grub_file"): No kernel reference"
        fi
        
        # Check for multiple search fallbacks
        search_count=$(grep -c "search\|set root" "$grub_file" || echo "0")
        if [ "$search_count" -ge 2 ]; then
            pass "$(basename "$grub_file"): Multiple fallback search methods"
        else
            warn "$(basename "$grub_file"): Only one search method (should have fallbacks)"
        fi
    fi
done

# ════════════════════════════════════════════════════════════════════
#  8. Package Lists Validation
# ════════════════════════════════════════════════════════════════════
section "Package Lists Validation"

# Kernel: on Debian live-build, linux-image is normally installed by lb chroot_linux-image
# when auto/config sets --linux-flavours (see live-build(7)). Listing linux-image-amd64 in
# package lists is optional and can duplicate that step.
if grep -qE '--linux-flavours[[:space:]]+' auto/config 2>/dev/null; then
    pass "Kernel: expected from live-build (--linux-flavours in auto/config)"
else
    kernel_in_lists=0
    for pf in config/package-lists/*.list.chroot; do
        [ -f "$pf" ] || continue
        if grep -qE '^linux-image-amd64[[:space:]]*$' "$pf"; then
            kernel_in_lists=1
            break
        fi
    done
    if [ "$kernel_in_lists" -eq 1 ]; then
        pass "Kernel: linux-image-amd64 listed in package lists"
    else
        warn "Kernel: no --linux-flavours in auto/config and no linux-image-amd64 in package lists"
    fi
fi

for pkg_file in config/package-lists/*.list.chroot; do
    if [ -f "$pkg_file" ]; then
        pkg_count=$(grep -v "^#" "$pkg_file" | grep -v "^$" | wc -l)
        pass "$(basename "$pkg_file"): $pkg_count packages"

        # Optional explicit kernel in this file (unusual when using --linux-flavours)
        if grep -q "linux-image-amd64" "$pkg_file"; then
            pass "  ├─ $(basename "$pkg_file"): also lists linux-image-amd64"
        fi

        # Boot-related packages (optional in lists; live-build adds bootloader bits for ISO)
        for pkg in grub-pc grub-efi-amd64 initramfs-tools; do
            if grep -q "$pkg" "$pkg_file"; then
                pass "  ├─ Includes $pkg"
            fi
        done
    fi
done

# ════════════════════════════════════════════════════════════════════
#  9. System Resources
# ════════════════════════════════════════════════════════════════════
section "System Resources"

# Check disk space
disk_available=$(df . | awk 'NR==2 {print $4}')
disk_available_gb=$((disk_available / 1024 / 1024))

if [ "$disk_available_gb" -ge 30 ]; then
    pass "Disk space: ${disk_available_gb}GB available (minimum 20GB required)"
else
    error "Insufficient disk space: ${disk_available_gb}GB (need 20GB minimum)"
fi

# Check RAM
ram_total_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
ram_total_gb=$((ram_total_mb / 1024))

if [ "$ram_total_gb" -ge 4 ]; then
    pass "RAM: ${ram_total_gb}GB available (good)"
elif [ "$ram_total_gb" -ge 2 ]; then
    warn "RAM: ${ram_total_gb}GB available (minimum 2GB, 4GB+ recommended)"
else
    error "Insufficient RAM: ${ram_total_gb}GB (need 2GB minimum)"
fi

# ════════════════════════════════════════════════════════════════════
#  10. Permission Checks
# ════════════════════════════════════════════════════════════════════
section "Permission Checks"

if [ "$EUID" -eq 0 ]; then
    pass "Running as root (required for build)"
else
    error "Not running as root - build.sh requires sudo"
fi

for file in build.sh auto/build auto/clean auto/config; do
    if [ -f "$file" ]; then
        if [ -x "$file" ]; then
            pass "File is executable: $file"
        else
            warn "File not executable: $file (will be fixed by scripts)"
        fi
    fi
done

# ════════════════════════════════════════════════════════════════════
#  SUMMARY
# ════════════════════════════════════════════════════════════════════
echo ""
echo "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║${NC}  Pre-Build Check Summary${NC}                                  ${CYAN}║${NC}"
echo "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo "${CYAN}║${NC}  Checks Passed:  ${GREEN}${CHECKS_PASSED}${NC}"
echo "${CYAN}║${NC}  Warnings:       ${YELLOW}${WARNINGS}${NC}"
echo "${CYAN}║${NC}  Errors:         ${RED}${ERRORS}${NC}"
echo "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ════════════════════════════════════════════════════════════════════
#  FINAL VERDICT
# ════════════════════════════════════════════════════════════════════

if [ "$ERRORS" -eq 0 ]; then
    echo "${GREEN}✓ BUILD READY${NC}"
    echo ""
    echo "All checks passed. Ready to run: ${CYAN}sudo ./build.sh${NC}"
    echo ""
    exit 0
else
    echo "${RED}✗ BUILD NOT READY${NC}"
    echo ""
    echo "Please fix the errors above before running build.sh"
    echo ""
    exit 1
fi
