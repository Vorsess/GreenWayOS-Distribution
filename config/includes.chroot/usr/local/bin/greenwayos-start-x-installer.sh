#!/bin/bash
# Start standalone X11 for the graphical installer (VMware/QEMU/physical).
# X11 on tty2; tty1 stays login console. Falls back to text installer on any failure.
set -u

LOG=/var/log/greenwayos-gui-install.log
XLOG=/var/log/Xorg-installer.log
XAUTH=/tmp/.Xauth-greenwayos
X_VT=2
STATUS_TTY=/dev/tty1

msg() { printf '%s\n' "$*" >"$STATUS_TTY" 2>/dev/null || true; }

chvt_tty() {
  local n="${1:-1}"
  if command -v chvt >/dev/null 2>&1; then
    chvt "$n" 2>/dev/null || true
  elif [ -x /bin/chvt ]; then
    /bin/chvt "$n" 2>/dev/null || true
  fi
}

kill_x() {
  pkill -f 'Xorg :0' 2>/dev/null || true
  pkill -f 'X :0' 2>/dev/null || true
  sleep 1
}

x11_alive() {
  DISPLAY=:0 XAUTHORITY="$XAUTH" xset q >/dev/null 2>&1
}

fallback_text_installer() {
  local reason="${1:-unknown}"
  echo "FALLBACK: starting text installer (${reason})" >>"$LOG"
  kill_x
  pkill -f greenwayos-installer-gui 2>/dev/null || true
  # Do NOT start getty here — it steals tty1 and shows a login prompt ("login:").
  systemctl stop getty@tty1.service 2>/dev/null || true
  chvt_tty 1
  msg ""
  msg "  Графический установщик недоступен (${reason})."
  msg "  Запуск текстового установщика…"
  msg "  Лог: ${LOG}"
  sleep 2
  if [ -x /usr/local/bin/greenwayos-setup-install-console.sh ]; then
    /usr/local/bin/greenwayos-setup-install-console.sh || true
  fi
  # GUI unit has StandardInput=null — must open a real VT for curses.
  unset GREENWAYOS_INSTALLER_VIA_OPENVT || true
  if command -v openvt >/dev/null 2>&1; then
    export GREENWAYOS_INSTALLER_VIA_OPENVT=1
    exec openvt -f -s -w -c 1 -- /usr/local/bin/greenwayos-installer
  fi
  exec /usr/local/bin/greenwayos-installer
}

exec >>"$LOG" 2>&1
echo "=== $(date) === greenwayos-start-x-installer.sh ===" | tee -a /dev/console /dev/tty1 2>/dev/null || true
echo "Kernel cmdline: $(cat /proc/cmdline)" | tee -a /dev/console 2>/dev/null || true

msg ""
msg "  GreenWayOS ctOS — X11 INSTALL PROTOCOL…"
msg "  Alt+F2 = GUI   Alt+F1 = shell"
msg "  Log: ${LOG}"

if [ ! -x /usr/local/bin/greenwayos-installer-gui ]; then
  fallback_text_installer "gui missing"
fi

if ! python3 -c "
from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PyQt5.QtGui import QFont
" 2>/dev/null; then
  fallback_text_installer "pyqt5 missing"
fi

mkdir -p /tmp/.X11-unix /run/greenwayos
kill_x
rm -f "$XAUTH" /tmp/.X11-unix/X0 2>/dev/null || true
touch "$XAUTH"
chmod 600 "$XAUTH"
xauth -f "$XAUTH" generate :0 . trusted >/dev/null 2>&1 || true
export XAUTHORITY="$XAUTH"

if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
     org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
  if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)" || true
    export DBUS_SESSION_BUS_ADDRESS
    echo "Started session dbus: ${DBUS_SESSION_BUS_ADDRESS:-unset}"
  fi
fi

write_xorg_conf() {
  local driver="$1"
  local conf="/run/greenwayos-xorg.conf"
  cat >"$conf" <<EOF
Section "ServerFlags"
    Option "DontVTSwitch" "false"
    Option "AllowMouseOpenFail" "true"
    Option "AutoAddGPU" "off"
EndSection

Section "Device"
    Identifier "GreenWayOS GPU"
    Driver "${driver}"
EndSection

Section "Monitor"
    Identifier "GreenWayOS Monitor"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Option "PreferredMode" "1280x800"
    Modeline "1280x800" 83.50 1280 1352 1480 1680 800 803 809 831 -hsync +vsync
    Modeline "1024x768" 65.00 1024 1048 1184 1344 768 771 777 806 -hsync +vsync
    Modeline "1280x720" 74.50 1280 1344 1472 1664 720 723 728 748 -hsync +vsync
EndSection

Section "Screen"
    Identifier "GreenWayOS Screen"
    Device "GreenWayOS GPU"
    Monitor "GreenWayOS Monitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual 1280 800
        Modes "1280x800" "1280x720" "1024x768" "800x600"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "GreenWayOS Layout"
    Screen "GreenWayOS Screen"
EndSection
EOF
  printf '%s' "$conf"
}

start_xorg() {
  local driver="$1"
  local conf
  conf="$(write_xorg_conf "$driver")"
  rm -f "$XLOG" 2>/dev/null || true

  # vesa/fbdev first — vmware driver often segfaults in VMware Workstation.
  Xorg :0 "vt${X_VT}" -nolisten tcp -auth "$XAUTH" \
    -config "$conf" -logfile "$XLOG" -noreset +extension GLX &
  local xpid=$!
  echo "Trying Xorg driver=${driver} PID=${xpid} vt=${X_VT}"

  local n=0
  while [ "$n" -lt 45 ]; do
    if x11_alive; then
      echo "X11 ready with ${driver} after ${n}s"
      return 0
    fi
    if ! kill -0 "$xpid" 2>/dev/null; then
      echo "Xorg (${driver}) exited early (possible segfault — check fonts/drivers)"
      tail -n 40 "$XLOG" 2>/dev/null || true
      return 1
    fi
    if [ $((n % 10)) -eq 0 ] && [ "$n" -gt 0 ]; then
      msg "  Ожидание X11 на Alt+F2… ${n}s (${driver})"
    fi
    n=$((n + 1))
    sleep 1
  done

  kill "$xpid" 2>/dev/null || true
  wait "$xpid" 2>/dev/null || true
  echo "Xorg (${driver}) timeout"
  tail -n 40 "$XLOG" 2>/dev/null || true
  return 1
}

set_x_resolution() {
  if ! command -v xrandr >/dev/null 2>&1; then
    return 0
  fi
  local out mode modeline
  out="$(DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')"
  [ -z "$out" ] && out="default"

  DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr --output "$out" --auto 2>/dev/null || true

  add_mode() {
    modeline="$1"
    shift
    DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr --newmode "$modeline" "$@" 2>/dev/null || true
    DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr --addmode "$out" "$modeline" 2>/dev/null || true
  }

  add_mode "1280x800_60.00" 83.50 1280 1352 1480 1680 800 803 809 831 -hsync +vsync
  add_mode "1024x768_60.00" 65.00 1024 1048 1184 1344 768 771 777 806 -hsync +vsync
  add_mode "1280x720_60.00" 74.50 1280 1344 1472 1664 720 723 728 748 -hsync +vsync

  # Prefer installer-friendly sizes (buttons fit); avoid forcing 1080p.
  for mode in 1280x800_60.00 1280x800 1280x720_60.00 1280x720 1024x768_60.00 1024x768 800x600; do
    if DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr --output "$out" --mode "$mode" 2>/dev/null; then
      echo "X resolution set to ${mode} on ${out}"
      return 0
    fi
    if DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr -s "$mode" 2>/dev/null; then
      echo "X resolution set to ${mode}"
      return 0
    fi
  done
  return 0
}

for drv in vesa fbdev vmware; do
  msg "  Пробуем X11: ${drv} → Alt+F2"
  if start_xorg "$drv"; then
    if ! x11_alive; then
      kill_x
      continue
    fi
    DISPLAY=:0 XAUTHORITY="$XAUTH" xhost +local:root 2>/dev/null || true
    set_x_resolution
    DISPLAY=:0 XAUTHORITY="$XAUTH" xsetroot -solid "#0A0E12" 2>/dev/null || true
    if ! x11_alive; then
      kill_x
      continue
    fi
    msg "  X11 готов — Alt+F2"
    chvt_tty "$X_VT"
    echo "Launching greenwayos-installer-gui on DISPLAY=:0"
    set +e
    env DISPLAY=:0 XAUTHORITY="$XAUTH" QT_QPA_PLATFORM=xcb \
      QT_AUTO_SCREEN_SCALE_FACTOR=0 QT_X11_NO_MITSHM=1 \
      LANG=C.UTF-8 LC_ALL=C.UTF-8 \
      /usr/local/bin/greenwayos-installer-gui
    rc=$?
    set -u
    echo "GUI exited with code ${rc}"
    if [ "$rc" -ne 0 ] || ! x11_alive; then
      fallback_text_installer "gui exit ${rc}"
    fi
    exit 0
  fi
  kill_x
done

fallback_text_installer "x11 failed"
