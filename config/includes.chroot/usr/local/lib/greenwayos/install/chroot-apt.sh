#!/bin/bash
# Install packages inside target chroot (/mnt). Called from install.engine.
# Desktop/GUI packages are MANDATORY — never continue without them.
set -euo pipefail

BOOT_MODE="${1:-bios}"
EXTRA_PACKAGES="${2:-}"
MIRROR="${3:-http://deb.debian.org/debian}"

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# Harden apt against hung mirrors (RU / flaky CDN)
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99-greenwayos-acquire <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::ftp::Timeout "30";
APT::Get::Assume-Yes "true";
APT::Install-Recommends "false";
EOF

# Full Bookworm sources (firmware needs non-free-firmware)
MIRROR="${MIRROR%/}"
cat > /etc/apt/sources.list <<EOF
deb ${MIRROR} bookworm main contrib non-free non-free-firmware
deb ${MIRROR} bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

retry_apt() {
  local attempt
  for attempt in 1 2 3; do
    echo "[apt-get attempt ${attempt}/3] $*"
    if apt-get "$@"; then
      return 0
    fi
    echo "W: apt-get failed (attempt ${attempt}/3)"
    [ "$attempt" -lt 3 ] && sleep $((2 ** attempt))
  done
  return 1
}

# Soft install: try whole set, then fall back package-by-package
soft_install() {
  local name="$1"
  shift
  local -a pkgs=("$@")
  echo ">>> Soft install (${name}): ${pkgs[*]}"
  if retry_apt install -y --no-install-recommends "${pkgs[@]}"; then
    echo ">>> Soft install (${name}): OK"
    return 0
  fi
  echo "W: batch (${name}) failed — trying packages one by one"
  local pkg
  for pkg in "${pkgs[@]}"; do
    if retry_apt install -y --no-install-recommends "$pkg"; then
      echo ">>> + ${pkg}"
    else
      echo "W: skipped optional package: ${pkg}"
    fi
  done
}

stage_install() {
  local num="$1"
  local total="$2"
  local name="$3"
  shift 3
  local -a pkgs=("$@")
  local count=${#pkgs[@]}
  local t0=$SECONDS
  echo ">>> GWOS_APT_STAGE ${num}/${total} ${name} start packages=${count}"
  echo ">>> Packages (${name}): ${pkgs[*]}"
  if retry_apt install -y --no-install-recommends "${pkgs[@]}"; then
    echo ">>> GWOS_APT_STAGE ${num}/${total} ${name} done elapsed=$((SECONDS - t0))s"
    return 0
  fi
  echo ">>> GWOS_APT_STAGE ${num}/${total} ${name} failed elapsed=$((SECONDS - t0))s"
  return 1
}

require_cmds() {
  local missing=0
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "E: required command missing after install: $c"
      missing=1
    fi
  done
  return "$missing"
}

debconf-set-selections <<'EOF'
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean false
lightdm shared/default-x-display-manager select lightdm
EOF

echo ">>> GWOS_APT_STAGE 0/5 prepare start"
echo ">>> Mirror: ${MIRROR}"
echo ">>> Updating package index..."
if ! retry_apt update; then
  echo "E: apt-get update failed — cannot continue without package index"
  exit 1
fi
echo ">>> GWOS_APT_STAGE 0/5 prepare done"

if [ "$BOOT_MODE" = "uefi" ]; then
  GRUB_PKG="grub-efi-amd64"
else
  GRUB_PKG="grub-pc"
fi

# ── 1/5 BASE (mandatory) ───────────────────────────────────────────
if ! stage_install 1 5 base \
  locales tzdata sudo dbus-x11 \
  linux-image-amd64 initramfs-tools \
  grub-common "${GRUB_PKG}" os-prober efibootmgr; then
  echo "E: base packages failed — aborting"
  exit 1
fi

# ── 2/5 DESKTOP CORE (mandatory — without this you get console-only) ─
if ! stage_install 2 5 desktop-core \
  xorg xserver-xorg xinit \
  xfce4 xfce4-terminal xfce4-panel xfce4-session xfwm4 xfdesktop4 \
  lightdm lightdm-gtk-greeter \
  network-manager network-manager-gnome \
  fonts-dejavu fonts-jetbrains-mono \
  dbus-x11 policykit-1; then
  echo "E: desktop-core FAILED — refusing console-only install"
  echo "E: Check network/mirror. sources.list:"
  cat /etc/apt/sources.list || true
  exit 1
fi

# Verify GUI stack actually present
if ! dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
  echo "E: lightdm not installed"
  exit 1
fi
if ! dpkg -l xfce4-session 2>/dev/null | grep -q '^ii' && ! dpkg -l xfce4 2>/dev/null | grep -q '^ii'; then
  echo "E: XFCE session not installed"
  exit 1
fi

# Enable graphical boot. systemctl often returns non-zero inside chroot
# (no PID1) — NEVER let that abort the install after packages succeeded.
enable_graphical_boot() {
  mkdir -p /etc/systemd/system
  # Preferred when systemd tools work in chroot
  systemctl enable lightdm.service 2>/dev/null || true
  systemctl set-default graphical.target 2>/dev/null || true
  # Hard guarantee via symlinks (works offline in chroot)
  if [ -f /lib/systemd/system/lightdm.service ]; then
    ln -sfn /lib/systemd/system/lightdm.service \
      /etc/systemd/system/display-manager.service
  fi
  if [ -f /lib/systemd/system/graphical.target ]; then
    ln -sfn /lib/systemd/system/graphical.target \
      /etc/systemd/system/default.target
  fi
  # Debconf default DM
  echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
  echo ">>> graphical boot enabled (lightdm + graphical.target)"
}
enable_graphical_boot

# ── 3/5 DESKTOP EXTRAS (soft — must not kill GUI) ───────────────────
echo ">>> GWOS_APT_STAGE 3/5 desktop-extras start"
soft_install desktop-extras \
  xfce4-goodies xfce4-pulseaudio-plugin xfce4-xkb-plugin xfce4-notifyd \
  pulseaudio pulseaudio-utils pavucontrol alsa-utils alsa-ucm-conf rtkit \
  x11-xkb-utils keyboard-configuration \
  firmware-linux-free firmware-sof-signed firmware-intel-sound \
  open-vm-tools open-vm-tools-desktop spice-vdagent
# Guest tools services (clipboard / DnD) — ignore if not in VM
systemctl enable open-vm-tools.service 2>/dev/null || true
systemctl enable vgauth.service 2>/dev/null || true
systemctl enable spice-vdagent.service 2>/dev/null || true
echo ">>> GWOS_APT_STAGE 3/5 desktop-extras done"

# ── 4/5 APPS (soft) ─────────────────────────────────────────────────
echo ">>> GWOS_APT_STAGE 4/5 apps start"
soft_install apps \
  firefox-esr libreoffice-writer libreoffice-calc vlc mousepad \
  wireshark-common tshark gparted remmina terminator \
  python3 python3-tk python3-pyqt5 scrot neofetch \
  vim htop curl wget git build-essential gcc \
  tcpdump nmap netcat-openbsd iproute2 iputils-ping traceroute dnsutils whois net-tools \
  iptables iptables-persistent openvpn sysstat lsof strace psmisc rsync parted lshw pciutils usbutils
echo ">>> GWOS_APT_STAGE 4/5 apps done"

# ── 5/5 EXPERT (soft) ───────────────────────────────────────────────
if [ -n "$EXTRA_PACKAGES" ]; then
  echo ">>> GWOS_APT_STAGE 5/5 expert start"
  # shellcheck disable=SC2086
  soft_install expert $EXTRA_PACKAGES
  echo ">>> GWOS_APT_STAGE 5/5 expert done"
else
  echo ">>> GWOS_APT_STAGE 5/5 expert skipped"
fi

# Final GUI sanity (packages only — systemctl in chroot is unreliable)
echo ">>> GUI sanity check"
dpkg -l lightdm xfce4-session xserver-xorg 2>/dev/null | grep '^ii' || true
enable_graphical_boot
if [ ! -e /etc/systemd/system/default.target ] && [ ! -L /etc/systemd/system/default.target ]; then
  echo "E: failed to set default.target → graphical"
  exit 1
fi
if [ ! -e /etc/systemd/system/display-manager.service ] && [ ! -L /etc/systemd/system/display-manager.service ]; then
  echo "E: failed to link display-manager → lightdm"
  exit 1
fi

echo ">>> Package installation finished (GUI stack OK)"
exit 0
