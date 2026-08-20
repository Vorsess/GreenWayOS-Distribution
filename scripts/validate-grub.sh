#!/bin/bash
# Validate GRUB configs before ISO build (kernel paths, BIOS/UEFI parity, modules).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GRUB_PC="config/bootloaders/grub-pc/grub.cfg"
GRUB_EFI="config/bootloaders/grub-efi/grub.cfg"
ERRORS=0

err() { printf '✗ GRUB: %s\n' "$1" >&2; ERRORS=$((ERRORS + 1)); }
ok()  { printf '✓ GRUB: %s\n' "$1"; }

for f in "$GRUB_PC" "$GRUB_EFI"; do
  if [ ! -f "$f" ]; then
    err "Missing $f"
    exit 1
  fi
done

menu_pc=$(grep -c '^menuentry ' "$GRUB_PC" || true)
menu_efi=$(grep -c '^menuentry ' "$GRUB_EFI" || true)
if [ "$menu_pc" -lt 1 ] || [ "$menu_efi" -lt 1 ]; then
  err "No menuentry blocks found"
else
  ok "menuentry count: BIOS=${menu_pc} UEFI=${menu_efi}"
fi

if [ "$menu_pc" -ne "$menu_efi" ]; then
  err "BIOS and UEFI menuentry counts differ (${menu_pc} vs ${menu_efi})"
fi

titles_pc=$(grep '^menuentry ' "$GRUB_PC" | sed 's/menuentry "\([^"]*\)".*/\1/' | sort)
titles_efi=$(grep '^menuentry ' "$GRUB_EFI" | sed 's/menuentry "\([^"]*\)".*/\1/' | sort)
if [ "$titles_pc" != "$titles_efi" ]; then
  err "BIOS/UEFI menu titles differ"
  diff -u <(echo "$titles_pc") <(echo "$titles_efi") >&2 || true
else
  ok "BIOS/UEFI menu titles match"
fi

# Kernel/initrd paths (live-build publishes symlinks here)
for f in "$GRUB_PC" "$GRUB_EFI"; do
  name=$(basename "$(dirname "$f")")
  if ! grep -q '/live/vmlinuz' "$f"; then
    err "$name: missing /live/vmlinuz reference"
  fi
  if ! grep -q '/live/initrd.img' "$f"; then
    err "$name: missing /live/initrd.img reference"
  fi
  if grep -E '^\s+(linux16|linux) ' "$f" | grep -qv '/live/vmlinuz'; then
    err "$name: kernel line must use /live/vmlinuz (not /boot/vmlinuz or /vmlinuz)"
  fi
  if grep -qE '(linux16|linux) /boot/vmlinuz' "$f"; then
    err "$name: stale kernel path /boot/vmlinuz (must use /live/vmlinuz)"
  fi
  if grep -qE 'gw\.(install|gui)=' "$f"; then
    err "$name: stale gw.install/gw.gui kernel params"
  fi
  if ! grep -q 'search --no-floppy' "$f"; then
    err "$name: missing search fallback for live medium"
  fi
  if ! grep -q 'FATAL: /live/vmlinuz missing' "$f"; then
    err "$name: missing pre-boot kernel guard in menu entries"
  fi
done

# BIOS must use linux16/initrd16; UEFI must use linux/initrd (not linux16)
linux16_pc=$(grep -c 'linux16 /live/vmlinuz' "$GRUB_PC" || true)
initrd16_pc=$(grep -c 'initrd16 /live/initrd.img' "$GRUB_PC" || true)
if [ "$linux16_pc" -ne "$menu_pc" ] || [ "$initrd16_pc" -ne "$menu_pc" ]; then
  err "grub-pc: every menuentry must use linux16 + initrd16 (${linux16_pc}/${initrd16_pc} vs ${menu_pc})"
else
  ok "grub-pc: linux16/initrd16 on all entries"
fi

if grep -qE '^\s+linux /live/vmlinuz' "$GRUB_PC"; then
  err "grub-pc: must not use 'linux' (use linux16 for BIOS)"
fi

linux_efi=$(grep -c 'linux /live/vmlinuz' "$GRUB_EFI" || true)
initrd_efi=$(grep -c 'initrd /live/initrd.img' "$GRUB_EFI" || true)
if [ "$linux_efi" -ne "$menu_efi" ] || [ "$initrd_efi" -ne "$menu_efi" ]; then
  err "grub-efi: every menuentry must use linux + initrd (${linux_efi}/${initrd_efi} vs ${menu_efi})"
else
  ok "grub-efi: linux/initrd on all entries"
fi

if grep -qE 'linux16|initrd16' "$GRUB_EFI"; then
  err "grub-efi: must not use linux16/initrd16"
fi

# Required modules
for mod in gzio search search_fs_file echo; do
  for f in "$GRUB_PC" "$GRUB_EFI"; do
    if ! grep -q "insmod ${mod}" "$f"; then
      err "$(basename "$(dirname "$f")"): missing insmod ${mod}"
    fi
  done
done
if ! grep -q 'insmod linux16' "$GRUB_PC"; then
  err "grub-pc: missing insmod linux16"
fi
if ! awk '$1=="insmod" && $2=="linux"{found=1} END{exit !found}' "$GRUB_EFI"; then
  err "grub-efi: missing insmod linux"
fi

# Installer entries
for f in "$GRUB_PC" "$GRUB_EFI"; do
  if ! grep -q 'greenwayos.install=1' "$f" || ! grep -q 'greenwayos.gui_install=1' "$f"; then
    err "$(basename "$(dirname "$f")"): installer kernel params missing"
  fi
  block=$(awk '/menuentry "INSTALL \/\/ TTY"/,/^[}]/' "$f")
  if ! echo "$block" | grep -q 'greenwayos.install=1'; then
    err "$(basename "$(dirname "$f")"): INSTALL // TTY missing greenwayos.install=1"
  fi
  if echo "$block" | grep -q 'greenwayos.gui_install=1'; then
    err "$(basename "$(dirname "$f")"): INSTALL // TTY must not set gui_install"
  fi
  if ! grep -q 'menuentry "LIVE NODE"' "$f"; then
    err "$(basename "$(dirname "$f")"): missing LIVE NODE menuentry"
  fi
  if ! grep -q 'menuentry "INSTALL // GUI"' "$f"; then
    err "$(basename "$(dirname "$f")"): missing INSTALL // GUI menuentry"
  fi
done

# live-build alignment
if ! grep -qE -- '--linux-flavours[[:space:]]+amd64' auto/config; then
  err "auto/config: --linux-flavours amd64 required for /live/vmlinuz"
else
  ok "auto/config: --linux-flavours amd64"
fi

if ! grep -q 'grub-pc grub-efi' auto/config; then
  err "auto/config: must enable both grub-pc and grub-efi bootloaders"
else
  ok "auto/config: grub-pc + grub-efi bootloaders"
fi

if [ "$ERRORS" -gt 0 ]; then
  printf '\n✗ GRUB validation failed (%d error(s))\n' "$ERRORS" >&2
  exit 1
fi

printf '✓ GRUB validation passed\n'
exit 0
