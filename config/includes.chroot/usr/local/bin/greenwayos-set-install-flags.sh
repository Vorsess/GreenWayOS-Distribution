#!/bin/sh
# Create /run/greenwayos/* flags from kernel cmdline (idempotent).
set -eu

CMDLINE="$(cat /proc/cmdline)"
INSTALL=
GUI=

case " ${CMDLINE} " in
  *" greenwayos.install=1 "*|*" greenwayos_install=1 "*) INSTALL=1 ;;
esac
case " ${CMDLINE} " in
  *" greenwayos.gui_install=1 "*|*" greenwayos_gui=1 "*|*" greenwayos_gui_install=1 "*) GUI=1 ;;
esac

if [ -z "${INSTALL}" ]; then
  exit 0
fi

mkdir -p /run/greenwayos
: > /run/greenwayos/install
if [ -n "${GUI}" ]; then
  : > /run/greenwayos/gui
else
  rm -f /run/greenwayos/gui
fi

if [ -n "${GUI}" ]; then
  MSG="  GreenWayOS — графический установщик
  Загрузка…  GUI: Alt+F2  |  Shell: Alt+F1 (user + Enter)"
else
  MSG="  GreenWayOS — текстовый установщик
  Загрузка…  установщик на Alt+F1"
fi
printf '\n%s\n\n' "$MSG" >/dev/tty1 2>/dev/null || true

exit 0
