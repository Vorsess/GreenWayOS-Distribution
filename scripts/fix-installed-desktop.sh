#!/bin/bash
# Fix audio, keyboard layout switcher, and ctOS GRUB on an already-installed GreenWayOS.
# Run as root on the INSTALLED system (not Live).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "=== 1/3 Audio (PulseAudio + firmware + unmute) ==="
apt-get update -qq
apt-get install -y --no-install-recommends \
  pulseaudio pulseaudio-utils pavucontrol alsa-utils alsa-ucm-conf \
  xfce4-pulseaudio-plugin rtkit \
  firmware-sof-signed firmware-intel-sound firmware-linux-free || \
apt-get install -y --no-install-recommends \
  pulseaudio pulseaudio-utils pavucontrol alsa-utils xfce4-pulseaudio-plugin

# Install audio setup helper
cat > /usr/local/bin/greenwayos-audio-setup <<'EOF'
#!/bin/sh
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
systemctl --user start pulseaudio.socket 2>/dev/null || true
systemctl --user start pulseaudio.service 2>/dev/null || true
pulseaudio --check 2>/dev/null || pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
i=0
while [ "$i" -lt 15 ]; do
  pactl info >/dev/null 2>&1 && break
  i=$((i + 1)); sleep 0.3
done
pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null || true
pactl set-sink-volume @DEFAULT_SINK@ 70% 2>/dev/null || true
pactl list short sinks 2>/dev/null | while read -r idx _; do
  [ -n "$idx" ] || continue
  pactl set-sink-mute "$idx" 0 2>/dev/null || true
  pactl set-sink-volume "$idx" 70% 2>/dev/null || true
done
amixer -q sset Master unmute 2>/dev/null || true
amixer -q sset Master 70% 2>/dev/null || true
amixer -q sset PCM unmute 2>/dev/null || true
exit 0
EOF
chmod +x /usr/local/bin/greenwayos-audio-setup

mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/greenwayos-audio.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=GreenWayOS Audio Setup
Exec=/usr/local/bin/greenwayos-audio-setup
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

systemctl --global enable pulseaudio.service 2>/dev/null || true
if [ -n "${SUDO_USER:-}" ]; then
  sudo -u "$SUDO_USER" systemctl --user enable pulseaudio.service 2>/dev/null || true
  sudo -u "$SUDO_USER" systemctl --user start pulseaudio.service 2>/dev/null || true
  sudo -u "$SUDO_USER" env DISPLAY="${DISPLAY:-:0}" \
    XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" \
    /usr/local/bin/greenwayos-audio-setup 2>/dev/null || true
fi

echo "--- audio diagnostics ---"
echo "cards:"; cat /proc/asound/cards 2>/dev/null || echo "(none)"
echo "pactl sinks:";
if [ -n "${SUDO_USER:-}" ]; then
  sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" \
    pactl list short sinks 2>/dev/null || echo "(no sinks — check VM Sound device / firmware)"
else
  pactl list short sinks 2>/dev/null || true
fi

echo "=== 2/3 Keyboard US/RU (Alt+Shift) + panel xkb ==="
apt-get install -y --no-install-recommends \
  xfce4-xkb-plugin x11-xkb-utils keyboard-configuration

cat > /etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle,grp_led:scroll"
BACKSPACE="guess"
EOF
setupcon --force 2>/dev/null || true

PANEL_XML='<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="28"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.050980"/>
        <value type="double" value="0.066667"/>
        <value type="double" value="0.090196"/>
        <value type="double" value="0.920000"/>
      </property>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="7"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="button-title" type="string" value="APPS //"/>
      <property name="show-button-title" type="bool" value="true"/>
      <property name="show-button-icon" type="bool" value="false"/>
    </property>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="show-handle" type="bool" value="false"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
      <property name="expand" type="bool" value="true"/>
    </property>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-7" type="string" value="xkb">
      <property name="display-type" type="uint" value="2"/>
      <property name="display-name" type="uint" value="1"/>
    </property>
    <property name="plugin-5" type="string" value="pulseaudio"/>
    <property name="plugin-6" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M // %Y-%m-%d"/>
    </property>
  </property>
</channel>'

KBD_XML='<?xml version="1.0" encoding="UTF-8"?>
<channel name="keyboard-layout" version="1.0">
  <property name="Default" type="empty">
    <property name="XkbDisable" type="bool" value="false"/>
    <property name="XkbLayout" type="string" value="us,ru"/>
    <property name="XkbVariant" type="string" value=","/>
    <property name="XkbOptions" type="empty">
      <property name="Group" type="array">
        <value type="string" value="grp:alt_shift_toggle"/>
      </property>
    </property>
  </property>
</channel>'

apply_user_xfce() {
  local home="$1" user="$2"
  mkdir -p "$home/.config/xfce4/xfconf/xfce-perchannel-xml"
  printf '%s\n' "$PANEL_XML" > "$home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
  printf '%s\n' "$KBD_XML" > "$home/.config/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml"
  chown -R "$user:$user" "$home/.config/xfce4" 2>/dev/null || true
}

for home in /home/*; do
  [ -d "$home" ] || continue
  user="$(basename "$home")"
  id "$user" >/dev/null 2>&1 || continue
  apply_user_xfce "$home" "$user"
done
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
printf '%s\n' "$PANEL_XML" > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
printf '%s\n' "$KBD_XML" > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml

# Apply layout for current session if DISPLAY is set
if [ -n "${DISPLAY:-}" ] || [ -n "${SUDO_USER:-}" ]; then
  runuser_cmd() {
    if [ -n "${SUDO_USER:-}" ]; then
      sudo -u "$SUDO_USER" env DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/home/$SUDO_USER/.Xauthority}" "$@"
    else
      "$@"
    fi
  }
  runuser_cmd setxkbmap -layout us,ru -option grp:alt_shift_toggle 2>/dev/null || true
fi

echo "=== 3/3 Custom GRUB (GreenWayOS ctOS) ==="
THEME_DIR="/usr/share/grub/themes/GreenWay-ctOS"
mkdir -p "$THEME_DIR" /etc/default/grub.d /boot/grub

# Theme text (shipped with ISO after rebuild; create here if missing)
if [ ! -f "$THEME_DIR/theme.txt" ]; then
  cat > "$THEME_DIR/theme.txt" <<'EOF'
desktop-color: "#0A0E12"
desktop-image: "background.png"
title-text: "GreenWayOS // NODE"
title-font: "DejaVu Sans Bold 16"
title-color: "#00E8FF"
message-font: "DejaVu Sans 12"
message-color: "#1DB954"
terminal-font: "DejaVu Sans Mono 12"

+ boot_menu {
  left = 12%
  width = 76%
  top = 28%
  height = 48%
  item_font = "DejaVu Sans 14"
  item_color = "#7A8B9A"
  selected_item_font = "DejaVu Sans Bold 14"
  selected_item_color = "#00E8FF"
  item_height = 32
  item_padding = 10
  item_spacing = 6
  scrollbar = false
}

+ label {
  id = "__timeout__"
  left = 12%
  top = 82%
  width = 76%
  align = "center"
  font = "DejaVu Sans 12"
  color = "#1DB954"
  text = "AUTO-BOOT // %d"
}
EOF
fi

if [ ! -f "$THEME_DIR/background.png" ]; then
  if [ -f /usr/share/greenwayos/ctos/wallpaper.png ]; then
    cp -f /usr/share/greenwayos/ctos/wallpaper.png "$THEME_DIR/background.png"
  elif [ -f /usr/share/greenwayos/ctos/wallpaper-lock.png ]; then
    cp -f /usr/share/greenwayos/ctos/wallpaper-lock.png "$THEME_DIR/background.png"
  fi
fi

cat > /etc/default/grub.d/99-greenwayos.cfg <<'EOF'
GRUB_DISTRIBUTOR="GreenWayOS"
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_GFXMODE=1024x768
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_THEME="/usr/share/grub/themes/GreenWay-ctOS/theme.txt"
GRUB_BACKGROUND="/usr/share/grub/themes/GreenWay-ctOS/background.png"
EOF

if [ -f /etc/default/grub ]; then
  sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="GreenWayOS"/' /etc/default/grub
  grep -q '^GRUB_DISTRIBUTOR=' /etc/default/grub || echo 'GRUB_DISTRIBUTOR="GreenWayOS"' >> /etc/default/grub
  sed -i 's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
  if grep -q '^GRUB_THEME=' /etc/default/grub; then
    sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/usr/share/grub/themes/GreenWay-ctOS/theme.txt"|' /etc/default/grub
  else
    echo 'GRUB_THEME="/usr/share/grub/themes/GreenWay-ctOS/theme.txt"' >> /etc/default/grub
  fi
fi

cat > /boot/grub/custom.cfg <<'EOF'
set menu_color_normal=cyan/black
set menu_color_highlight=black/cyan
set color_normal=cyan/black
set color_highlight=black/cyan
EOF

update-grub

echo
echo "Done."
echo "  • Sound: open pavucontrol or click the volume icon (re-login if still X)."
echo "  • Layout: Alt+Shift (US/RU). Panel shows layout near the clock after re-login."
echo "  • GRUB: reboot to see GreenWayOS // NODE theme."
echo "Re-login to XFCE (or reboot) recommended."
