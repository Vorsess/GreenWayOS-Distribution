#!/bin/sh
# Prepare Linux console for the text installer (VMware/QEMU/physical).
set -eu

dmesg -n 3 2>/dev/null || true

# Prefer mid resolutions that fit curses UI; avoid forcing 1920x1080 first.
if command -v fbset >/dev/null 2>&1 && [ -c /dev/fb0 ]; then
  for mode in 1280x800 1280x720 1024x768 1440x900 1680x1050 1920x1080; do
    w="${mode%x*}"
    h="${mode#*x}"
    if fbset -g "$w" "$h" "$w" "$h" 32 2>/dev/null; then
      break
    fi
  done
fi

for font in \
  /usr/share/consolefonts/Lat15-TerminusBold14x28.psf.gz \
  /usr/share/consolefonts/Lat15-TerminusBold16x32.psf.gz \
  /usr/share/consolefonts/Lat15-Terminus14x28.psf.gz \
  /usr/share/consolefonts/Lat15-VGA16.psf.gz; do
  if [ -f "$font" ] && command -v setfont >/dev/null 2>&1; then
    setfont "$font" 2>/dev/null && break
  fi
done

if command -v setterm >/dev/null 2>&1; then
  setterm -blank 0 -powerdown 0 -powersave off >/dev/tty1 2>/dev/null || true
fi

clear 2>/dev/null || true
exit 0
