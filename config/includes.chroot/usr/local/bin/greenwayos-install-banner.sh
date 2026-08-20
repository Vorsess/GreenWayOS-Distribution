#!/bin/sh
# Post-boot banner on tty1 for installer modes (after plymouth / boot scroll).
set -eu

CMDLINE="$(cat /proc/cmdline)"
case " ${CMDLINE} " in
  *" greenwayos.install=1 "*|*" greenwayos_install=1 "*) ;;
  *) exit 0 ;;
esac

if command -v chvt >/dev/null 2>&1; then
  chvt 1 2>/dev/null || true
fi

if case " ${CMDLINE} " in *" greenwayos.gui_install=1 "*) true ;; *) false ;; esac; then
  cat >/dev/tty1 <<'EOF'

  ══════════════════════════════════════════
  GreenWayOS — графический установщик
  ══════════════════════════════════════════
  Запуск X11… подождите 30–60 сек.
  GUI: Alt+F2   |   Shell: Alt+F1 (user + Enter)
  Текстовый: sudo openvt -f -s -w -- greenwayos-installer
  Лог: /var/log/greenwayos-gui-install.log

EOF
else
  cat >/dev/tty1 <<'EOF'

  ══════════════════════════════════════════
  GreenWayOS — текстовый установщик
  ══════════════════════════════════════════
  Запуск на tty1… подождите несколько секунд.
  Если экран пустой: Alt+F1
  Аварийно: sudo openvt -f -s -w -- greenwayos-installer

EOF
fi

exit 0
