#!/bin/sh
# Fallback when graphical installer systemd unit fails.
set -eu
LOG=/var/log/greenwayos-gui-install.log

if [ ! -f /run/greenwayos/gui ]; then
  exit 0
fi

if command -v chvt >/dev/null 2>&1; then
  chvt 1 2>/dev/null || true
fi

# Never start getty here — it shows login: and blocks the installer.
systemctl stop getty@tty1.service 2>/dev/null || true

if [ -x /usr/local/bin/greenwayos-setup-install-console.sh ]; then
  /usr/local/bin/greenwayos-setup-install-console.sh || true
fi

printf '\n  GUI failed — starting text installer…\n  See %s\n\n' "$LOG" >/dev/tty1 2>/dev/null || true

if command -v openvt >/dev/null 2>&1; then
  export GREENWAYOS_INSTALLER_VIA_OPENVT=1
  exec openvt -f -s -w -c 1 -- /usr/local/bin/greenwayos-installer
fi

exec /usr/local/bin/greenwayos-installer
