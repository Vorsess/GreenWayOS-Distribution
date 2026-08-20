#!/usr/bin/env bash
set -Eeuo pipefail

ISO="${1:-}"
if [[ -z "${ISO}" || ! -f "${ISO}" ]]; then
  echo "Usage: $0 path/to/image.iso" >&2
  exit 2
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 3; }
}

need xorriso

echo "[iso-check] ISO: ${ISO}"

list_live() {
  xorriso -indev "${ISO}" -osirrox on -find /live -maxdepth 1 -type f -print 2>/dev/null | sed 's|^|  |'
}

echo "[iso-check] /live contents:"
list_live || true

have_vmlinuz="$(xorriso -indev "${ISO}" -osirrox on -find /live -maxdepth 1 -name vmlinuz -type f -print -quit 2>/dev/null || true)"
have_initrd="$(xorriso -indev "${ISO}" -osirrox on -find /live -maxdepth 1 -name initrd.img -type f -print -quit 2>/dev/null || true)"

if [[ -z "${have_vmlinuz}" || -z "${have_initrd}" ]]; then
  echo "[iso-check] FAIL: missing /live/vmlinuz or /live/initrd.img" >&2
  exit 10
fi

extra_kernels="$(xorriso -indev "${ISO}" -osirrox on -find /live -maxdepth 1 -name 'vmlinuz-*' -type f -print 2>/dev/null | wc -l | tr -d ' ')"
extra_initrds="$(xorriso -indev "${ISO}" -osirrox on -find /live -maxdepth 1 -name 'initrd.img-*' -type f -print 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${extra_kernels}" != "0" || "${extra_initrds}" != "0" ]]; then
  echo "[iso-check] WARN: versioned kernel/initrd also present under /live (expected 0)." >&2
fi

# Sanity: GRUB config exists and references live kernel paths
grub_pc="$(xorriso -indev "${ISO}" -osirrox on -find /boot/grub -name grub.cfg -type f -print -quit 2>/dev/null || true)"
if [[ -z "${grub_pc}" ]]; then
  echo "[iso-check] FAIL: /boot/grub/grub.cfg not found in ISO" >&2
  exit 11
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
xorriso -indev "${ISO}" -osirrox on -extract "${grub_pc}" "${tmpdir}/grub.cfg" >/dev/null 2>&1 || true
if [[ ! -s "${tmpdir}/grub.cfg" ]]; then
  echo "[iso-check] FAIL: could not extract ${grub_pc}" >&2
  exit 12
fi

if ! grep -q '/live/vmlinuz' "${tmpdir}/grub.cfg"; then
  echo "[iso-check] FAIL: grub.cfg does not reference /live/vmlinuz" >&2
  exit 13
fi
if ! grep -q '/live/initrd.img' "${tmpdir}/grub.cfg"; then
  echo "[iso-check] FAIL: grub.cfg does not reference /live/initrd.img" >&2
  exit 14
fi
if ! grep -q '^menuentry ' "${tmpdir}/grub.cfg"; then
  echo "[iso-check] FAIL: grub.cfg has no menuentry blocks" >&2
  exit 15
fi

menu_count="$(grep -c '^menuentry ' "${tmpdir}/grub.cfg" || true)"
linux_refs="$(grep -cE '(linux16|linux) /live/vmlinuz' "${tmpdir}/grub.cfg" || true)"
if [[ "${linux_refs}" -lt "${menu_count}" ]]; then
  echo "[iso-check] FAIL: grub.cfg menu entries (${menu_count}) != kernel refs (${linux_refs})" >&2
  exit 16
fi

echo "[iso-check] grub.cfg: ${menu_count} entries, kernel/initrd paths OK"

# Optional: EFI boot image present on hybrid ISO
efi_img="$(xorriso -indev "${ISO}" -osirrox on -find /boot -name '*.efi' -type f -print -quit 2>/dev/null || true)"
if [[ -n "${efi_img}" ]]; then
  echo "[iso-check] UEFI loader: ${efi_img}"
else
  echo "[iso-check] WARN: no .efi under /boot (UEFI boot may fail on some firmware)" >&2
fi

echo "[iso-check] PASS"

