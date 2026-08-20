#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  GreenWayOS Pre-Build Validation Script
#  Checks package availability, disk space, syntax, and security
# ══════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKS_PASSED=0

# ── Output helpers ──────────────────────────────────────────────────
info()  { printf "%b✓%b  %s\n" "${GREEN}" "${NC}" "$1"; ((++CHECKS_PASSED)); }
warn()  { printf "%b⚠%b  %s\n" "${YELLOW}" "${NC}" "$1"; ((++WARNINGS)); }
error() { printf "%b✗%b  %s\n" "${RED}" "${NC}" "$1"; ((++ERRORS)); }
header() { printf "\n%b→ %s%b\n" "${CYAN}" "$1" "${NC}"; }

# ══════════════════════════════════════════════════════════════════════
#  SECTION 1: Environment Check
# ══════════════════════════════════════════════════════════════════════
header "Environment Validation"

if [ ! -f "build.sh" ]; then
    error "build.sh not found in current directory"
fi

if [ ! -d "config" ]; then
    error "config/ directory not found"
fi

if [ ! -d "auto" ]; then
    error "auto/ directory not found"
fi

info "Project structure verified"

# Check for required tools
for tool in bash python3 sed grep find; do
    if command -v "$tool" &> /dev/null; then
        info "$tool is available"
    else
        error "$tool not found (required)"
    fi
done

# ══════════════════════════════════════════════════════════════════════
#  SECTION 2: Syntax and Permissions Validation (consolidated)
# ══════════════════════════════════════════════════════════════════════
header "Syntax and Permissions Validation"

# Check bash files (auto scripts)
bash_files=(build.sh auto/build auto/clean auto/config)
for file in "${bash_files[@]}"; do
    if [ ! -f "$file" ]; then
        warn "File not found: $file"
        continue
    fi
    
    # Check syntax
    if ! bash -n "$file" 2>/dev/null; then
        error "Bash syntax error in $file"
        continue
    fi
    
    # Check executable permission
    if [ ! -x "$file" ]; then
        warn "Not executable: $file (will be fixed by build.sh)"
    else
        info "✓ Bash syntax and executable: $file"
    fi
done

# Check hooks (consolidated syntax and permissions check)
hook_count=0
while IFS= read -r hook; do
    ((++hook_count))
    
    # Check syntax
    if ! bash -n "$hook" 2>/dev/null; then
        error "Syntax error in hook: $hook"
        continue
    fi
    
    # Check executable permission
    if [ ! -x "$hook" ]; then
        warn "Hook not executable: $hook (will be fixed by build.sh)"
    else
        info "✓ Hook syntax and executable: $(basename "$hook")"
    fi
done < <(find config/hooks -type f \( -name "*.chroot" -o -name "*.binary" -o -name "*.hook.chroot" -o -name "*.hook.binary" \) )

if [ "$hook_count" -eq 0 ]; then
    warn "No hooks found in config/hooks/"
fi

# Check Python files (welcome is a shell wrapper → ctOS HUD)
python_files=(
    "config/includes.chroot/usr/local/bin/greenwayos-installer"
    "config/includes.chroot/usr/local/bin/greenwayos-installer-gui"
    "config/includes.chroot/usr/local/bin/greenwayos-ctos-hud"
    "config/includes.chroot/usr/local/bin/greenwayos-welcome-legacy"
)
for file in "${python_files[@]}"; do
    if [ ! -f "$file" ]; then
        warn "Python file not found: $file"
        continue
    fi

    if ! python3 -m py_compile "$file" 2>/dev/null; then
        error "Python syntax error in $file"
    else
        info "✓ Python syntax OK: $(basename "$file")"
    fi
done

welcome_wrapper="config/includes.chroot/usr/local/bin/greenwayos-welcome"
if [ -f "$welcome_wrapper" ]; then
    if head -n1 "$welcome_wrapper" | grep -qE '^#!/(usr/)?bin/(env )?(ba)?sh'; then
        if bash -n "$welcome_wrapper" 2>/dev/null; then
            info "✓ Shell wrapper OK: greenwayos-welcome → ctOS HUD"
        else
            error "Shell syntax error in $welcome_wrapper"
        fi
    else
        error "greenwayos-welcome must be a shell wrapper to greenwayos-ctos-hud"
    fi
else
    error "Missing greenwayos-welcome wrapper"
fi

# ══════════════════════════════════════════════════════════════════════
#  SECTION 3: Package Availability Check
# ══════════════════════════════════════════════════════════════════════
header "Package Availability Check"

if apt-cache search "^" > /dev/null 2>&1; then
    info "APT cache is available"
    missing_count=0
    
    while IFS= read -r pkg; do
        # Skip comments and empty lines
        [[ "$pkg" =~ ^# ]] && continue
        [ -z "$pkg" ] && continue
        
        if ! apt-cache show "$pkg" > /dev/null 2>&1; then
            warn "Package not found in APT cache: $pkg"
            ((++missing_count))
        fi
    done < <(cat config/package-lists/*.list.chroot 2>/dev/null || true)
    
    if [ "$missing_count" -eq 0 ]; then
        info "All packages available in APT cache"
    else
        warn "$missing_count packages not found (may be optional)"
    fi
else
    warn "APT cache not available (skipping package check)"
fi

# ══════════════════════════════════════════════════════════════════════
#  SECTION 4: Security Checks
# ══════════════════════════════════════════════════════════════════════
header "Security Validation"

# Live ISO: passwordless sudo for default user is intentional (see sudoers.d comment).
if grep -q "NOPASSWD" config/includes.chroot/etc/sudoers.d/* 2>/dev/null; then
    warn "NOPASSWD sudo detected (expected for live user without password; tighten after disk install)"
else
    info "No NOPASSWD entries under sudoers.d/"
fi

# Check for hardcoded passwords
if grep -r "password.*=" config/includes.chroot/usr/local/bin/ 2>/dev/null | \
   grep -v "^\s*#" | grep -v "def\|input\|getpass"; then
    warn "Potential hardcoded password patterns found (check manually)"
else
    info "No obvious hardcoded passwords detected"
fi

# Check for dangerous shell patterns in hooks
dangerous_patterns=$(grep -r "eval\|from __future__.*print" config/hooks/ build.sh 2>/dev/null | \
                    grep -v "^\s*#" | wc -l)
if [ "$dangerous_patterns" -gt 0 ]; then
    warn "Found $dangerous_patterns potentially dangerous shell patterns"
else
    info "No dangerous shell patterns detected"
fi

# ══════════════════════════════════════════════════════════════════════
#  SECTION 5: Disk Space Check
# ══════════════════════════════════════════════════════════════════════
header "Disk Space Check"

available_space=$(df -B1 "$(pwd)" | tail -1 | awk '{print $4}')
available_gb=$((available_space / (1024*1024*1024)))
required_gb=20

if [ "$available_gb" -ge "$required_gb" ]; then
    info "Disk space OK: ${available_gb}GB available (need $required_gb)"
else
    error "Insufficient disk space: ${available_gb}GB available (need $required_gb)"
fi

# ══════════════════════════════════════════════════════════════════════
#  SECTION 6: Configuration Consistency
# ══════════════════════════════════════════════════════════════════════
header "Configuration Consistency Check"

# Check auto/config content
if grep -q "distribution bookworm" auto/config; then
    info "Build target Debian Bookworm confirmed"
else
    warn "Debian Bookworm not found in auto/config"
fi

if grep -q "architectures amd64" auto/config; then
    info "Architecture amd64 confirmed"
else
    warn "Architecture amd64 not found in auto/config"
fi

if grep -q "binary-images iso-hybrid" auto/config; then
    info "ISO format: iso-hybrid confirmed"
else
    warn "iso-hybrid not found in auto/config"
fi

# GRUB structural checks (kernel paths, BIOS/UEFI parity, modules)
if [ -f scripts/validate-grub.sh ]; then
    if bash scripts/validate-grub.sh; then
        info "GRUB configs validated (scripts/validate-grub.sh)"
    else
        error "GRUB validation failed — see scripts/validate-grub.sh"
    fi
else
    error "scripts/validate-grub.sh missing"
fi

# GRUB kernel params must match live-config hook + systemd installer units
INSTALL_HOOK="config/includes.chroot/lib/live/config/0100-greenwayos-install-mode"
if [ ! -f "$INSTALL_HOOK" ]; then
    error "Missing live-config hook: $INSTALL_HOOK"
elif [ ! -x "$INSTALL_HOOK" ] && ! grep -q '^#!/' "$INSTALL_HOOK"; then
    warn "Install-mode hook should be a shell script: $INSTALL_HOOK"
else
    info "live-config install-mode hook present"
fi

for grub_cfg in config/bootloaders/grub-pc/grub.cfg config/bootloaders/grub-efi/grub.cfg; do
    if [ ! -f "$grub_cfg" ]; then
        warn "GRUB config not found: $grub_cfg"
        continue
    fi
    if grep -qE 'gw\.(install|gui)=' "$grub_cfg"; then
        error "Stale installer kernel params in $grub_cfg (use greenwayos.install=1 / greenwayos.gui_install=1)"
    elif ! grep -q 'greenwayos.install=1' "$grub_cfg" || ! grep -q 'greenwayos.gui_install=1' "$grub_cfg"; then
        error "Installer kernel params missing in $grub_cfg"
    elif ! awk '/menuentry "INSTALL \/\/ TTY"/,/^[}]/' "$grub_cfg" | grep -q 'greenwayos.install=1'; then
        error "INSTALL // TTY entry missing greenwayos.install=1 in $grub_cfg"
    elif awk '/menuentry "INSTALL \/\/ TTY"/,/^[}]/' "$grub_cfg" | grep -q 'greenwayos.gui_install=1'; then
        error "INSTALL // TTY must not set greenwayos.gui_install=1 in $grub_cfg"
    elif ! grep -q 'noautologin' "$grub_cfg"; then
        error "Installer GRUB entries must include noautologin in $grub_cfg"
    else
        info "Installer GRUB params OK: $(basename "$(dirname "$grub_cfg")")/grub.cfg"
    fi
done

gui_svc="config/includes.chroot/etc/systemd/system/greenwayos-gui-install.service"
text_svc="config/includes.chroot/etc/systemd/system/greenwayos-text-install.service"
if grep -q 'ConditionKernelCommandLine=greenwayos.gui_install=1' "$gui_svc" && \
   grep -q 'ConditionKernelCommandLine=greenwayos.install=1' "$text_svc"; then
    info "Installer systemd units gate on kernel cmdline (greenwayos.install/gui_install)"
elif grep -q 'ConditionPathExists=/run/greenwayos/gui' "$gui_svc" && \
     grep -q 'ConditionPathExists=/run/greenwayos/install' "$text_svc"; then
    info "Installer systemd units use /run/greenwayos flag files"
else
    error "Installer units must gate on greenwayos.install/gui_install (cmdline or /run/greenwayos flags)"
fi

if grep -q 'systemctl enable lightdm' config/hooks/live/04-gui.chroot; then
    info "lightdm enabled in 04-gui.chroot hook (Live desktop)"
else
    error "lightdm must be enabled in config/hooks/live/04-gui.chroot for Live mode"
fi

if grep -q 'graphical.target' config/hooks/live/04-gui.chroot; then
    info "default boot target set to graphical in 04-gui.chroot"
else
    error "04-gui.chroot must set default.target to graphical.target for Live mode"
fi

if [ -f config/includes.chroot/etc/systemd/system/greenwayos-live-display.service ]; then
    info "greenwayos-live-display.service present (VT switch for Live)"
else
    error "Missing greenwayos-live-display.service for Live mode"
fi

for grub_cfg in config/bootloaders/grub-pc/grub.cfg config/bootloaders/grub-efi/grub.cfg; do
    live_block="$(awk '/menuentry "LIVE NODE"/,/^[}]/' "$grub_cfg")"
    if echo "$live_block" | grep -q 'plymouth.enable=0'; then
        info "LIVE NODE GRUB entry disables Plymouth: $(basename "$(dirname "$grub_cfg")")/grub.cfg"
    else
        error "LIVE NODE GRUB entry must disable Plymouth (plymouth.enable=0) in $grub_cfg"
    fi
    if echo "$live_block" | grep -qE '\bquiet\b|\bsplash\b'; then
        error "LIVE NODE GRUB entry must not use quiet/splash in $grub_cfg"
    fi
done

# ══════════════════════════════════════════════════════════════════════
#  ctOS HUD theme package
# ══════════════════════════════════════════════════════════════════════
CTOS_ROOT="config/includes.chroot/usr/share/greenwayos/ctos"
THEME_ROOT="config/includes.chroot/usr/share/themes/GreenWay-ctOS"
if [ -f "$CTOS_ROOT/branding.json" ] && [ -f "$CTOS_ROOT/wallpaper.png" ]; then
    info "ctOS branding.json + wallpaper present"
else
    error "Missing ctOS assets under $CTOS_ROOT (branding.json / wallpaper.png)"
fi
if [ -f "$THEME_ROOT/gtk-3.0/gtk.css" ] && [ -f "$THEME_ROOT/xfwm4/themerc" ]; then
    info "GreenWay-ctOS GTK + xfwm4 theme present"
else
    error "Missing GreenWay-ctOS theme under $THEME_ROOT"
fi
if [ -f config/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf.d/99-greenwayos-ctos.conf ]; then
    info "LightDM ctOS greeter config present"
else
    error "Missing LightDM ctOS greeter conf.d snippet"
fi
if [ -f config/includes.chroot/etc/skel/.config/gtk-3.0/settings.ini ] && \
   [ -f config/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml ]; then
    info "ctOS skel + xdg XFCE defaults present"
else
    error "Missing ctOS skel/xdg XFCE theme defaults"
fi
if [ -x config/includes.chroot/usr/local/bin/greenwayos-ctos-hud ] || \
   [ -f config/includes.chroot/usr/local/bin/greenwayos-ctos-hud ]; then
    info "ctOS HUD welcome binary present"
else
    error "Missing greenwayos-ctos-hud"
fi

GRUB_THEME_DIR="config/includes.chroot/usr/share/grub/themes/GreenWay-ctOS"
if [ -f "$GRUB_THEME_DIR/theme.txt" ] && [ -f "$GRUB_THEME_DIR/background.png" ]; then
    info "Installed-system GRUB theme GreenWay-ctOS present"
else
    error "Missing GRUB theme under $GRUB_THEME_DIR (theme.txt / background.png)"
fi
if [ -f config/includes.chroot/etc/default/grub.d/99-greenwayos.cfg ]; then
    info "GRUB grub.d/99-greenwayos.cfg present"
else
    error "Missing etc/default/grub.d/99-greenwayos.cfg"
fi
if [ -f config/includes.chroot/etc/default/keyboard ] && \
   grep -q 'us,ru' config/includes.chroot/etc/default/keyboard; then
    info "Keyboard us,ru + Alt+Shift defaults present"
else
    error "Missing /etc/default/keyboard with us,ru layouts"
fi
if grep -q 'pavucontrol' config/includes.chroot/usr/local/lib/greenwayos/install/chroot-apt.sh && \
   grep -q 'xfce4-xkb-plugin' config/includes.chroot/usr/local/lib/greenwayos/install/chroot-apt.sh; then
    info "Installer chroot-apt installs audio + xkb packages"
else
    error "chroot-apt.sh must install pavucontrol and xfce4-xkb-plugin"
fi
if grep -q 'value="xkb"' config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml; then
    info "XFCE panel includes xkb layout plugin"
else
    error "skel xfce4-panel.xml must include xkb plugin"
fi
if grep -q 'GreenWay-ctOS' config/includes.chroot/usr/local/lib/greenwayos/install/engine.py && \
   grep -q 'greenwayos-ctos-hud' config/includes.chroot/usr/local/lib/greenwayos/install/engine.py; then
    info "install.engine copies ctOS theme to target system"
else
    error "install.engine must rsync GreenWay-ctOS theme and ctOS HUD to /mnt"
fi
if [ -f scripts/CTOS_CHECKLIST.txt ]; then
    info "Manual post-ISO checklist: scripts/CTOS_CHECKLIST.txt"
else
    warn "scripts/CTOS_CHECKLIST.txt missing"
fi

# ══════════════════════════════════════════════════════════════════════
#  FINAL REPORT
# ══════════════════════════════════════════════════════════════════════
printf "\n%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "${CYAN}" "${NC}"
printf "  %bValidation Summary%b\n" "${GREEN}${BOLD}" "${NC}"
printf "%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "${CYAN}" "${NC}"

printf "  %b✓ Checks Passed: %d%b\n" "${GREEN}" "$CHECKS_PASSED" "${NC}"
printf "  %b⚠ Warnings: %d%b\n" "${YELLOW}" "$WARNINGS" "${NC}"
printf "  %b✗ Errors: %d%b\n" "${RED}" "$ERRORS" "${NC}"
printf "%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n\n" "${CYAN}" "${NC}"

if [ "$ERRORS" -gt 0 ]; then
    printf "%b✗ VALIDATION FAILED - Fix errors before proceeding%b\n\n" "${RED}" "${NC}"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    printf "%b⚠ VALIDATION PASSED with %d warning(s) - Review manually if needed%b\n\n" "${YELLOW}" "$WARNINGS" "${NC}"
    exit 0
else
    printf "%b✓ VALIDATION PASSED - Ready to build!%b\n\n" "${GREEN}" "${NC}"
    exit 0
fi
