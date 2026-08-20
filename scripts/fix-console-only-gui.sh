#!/bin/bash
# Rescue a console-only GreenWayOS install (desktop packages were skipped).
# Boot installed system, login, then: sudo bash fix-console-only-gui.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
MIRROR="${1:-http://deb.debian.org/debian}"
MIRROR="${MIRROR%/}"

mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99-greenwayos-acquire <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

cat > /etc/apt/sources.list <<EOF
deb ${MIRROR} bookworm main contrib non-free non-free-firmware
deb ${MIRROR} bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

echo ">>> apt update (${MIRROR})"
apt-get update

echo ">>> Installing desktop (XFCE + LightDM) — mandatory"
apt-get install -y --no-install-recommends \
  xorg xserver-xorg xinit \
  xfce4 xfce4-terminal xfce4-panel xfce4-session xfwm4 xfdesktop4 \
  lightdm lightdm-gtk-greeter \
  network-manager network-manager-gnome \
  fonts-dejavu fonts-jetbrains-mono dbus-x11 policykit-1

echo ">>> Optional audio/panel extras"
apt-get install -y --no-install-recommends \
  xfce4-goodies xfce4-pulseaudio-plugin xfce4-xkb-plugin xfce4-notifyd \
  pulseaudio pavucontrol alsa-utils || true

systemctl enable lightdm.service
systemctl set-default graphical.target

echo ">>> OK. Reboot into GUI:"
echo "    sudo reboot"
echo "If still console: systemctl status lightdm ; journalctl -b -u lightdm"
