#!/bin/sh
# Live mode: switch VMware console to the VT where X/LightDM runs.
set -eu

case " $(cat /proc/cmdline) " in
  *" greenwayos.install=1 "*) exit 0 ;;
esac

i=0
while [ "$i" -lt 45 ]; do
  if [ -S /tmp/.X11-unix/X0 ] 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

vt=""
if command -v pgrep >/dev/null 2>&1; then
  vt="$(pgrep -a Xorg 2>/dev/null | sed -n 's/.*vt\([0-9]\+\).*/\1/p' | head -1 || true)"
fi
[ -z "$vt" ] && vt=7

if command -v chvt >/dev/null 2>&1; then
  chvt "$vt" 2>/dev/null || true
fi

printf '\n  GreenWayOS Live — рабочий стол на Alt+F%d\n  Консоль: Alt+F1 (user + Enter)\n\n' "$vt" >/dev/tty1 2>/dev/null || true
exit 0
