"""Partition layout builders (guided wipe + dual-boot free space)."""
import shlex
from typing import Tuple

from .disk import (
    get_partition_name,
    list_partition_paths,
    assess_dualboot,
)


def build_auto_layout(
    disk_q: str,
    disk: str,
    boot_mode: str,
    method: str = "quick",
) -> Tuple[str, str, str, str, str, str, str]:
    """
    Destructive guided layout (wipes the whole disk).

    Returns:
      partition_cmd, format_cmd, efi_part, root_part, fstab_cmd, mount_root_cmd, grub_install_cmd
    """
    if method == "dualboot":
        return build_dualboot_layout(disk_q, disk, boot_mode)

    efi_part = get_partition_name(disk, 1)
    root_part = get_partition_name(disk, 2)

    if boot_mode == "uefi":
        partition_cmd = (
            f"set -e; swapoff -a 2>/dev/null || true; umount {disk_q}* 2>/dev/null || true; "
            f"wipefs --all --force {disk_q}; "
            f"dd if=/dev/zero of={disk_q} bs=1M count=10; "
            f"parted -s {disk_q} mklabel gpt "
            f"mkpart ESP fat32 1MiB 513MiB set 1 esp on "
            f"mkpart primary ext4 513MiB 100%; "
            f"partprobe {disk_q}; sleep 2"
        )
        if method == "manual":
            partition_cmd = (
                f"set -e; swapoff -a 2>/dev/null || true; umount {disk_q}* 2>/dev/null || true; "
                f"wipefs --all --force {disk_q}; "
                f"parted -s {disk_q} mklabel gpt "
                f"mkpart ESP fat32 1MiB 512MiB set 1 esp on "
                f"mkpart primary ext4 512MiB 90% "
                f"mkpart primary ext4 90% 100%; "
                f"partprobe {disk_q}; sleep 2"
            )
            root_part = get_partition_name(disk, 2)
        format_cmd = (
            f"mkfs.fat -F32 {shlex.quote(efi_part)} && mkfs.ext4 -F {shlex.quote(root_part)}"
        )
        fstab_cmd = (
            f"ROOT_UUID=$(blkid -s UUID -o value {shlex.quote(root_part)}); "
            f"EFI_UUID=$(blkid -s UUID -o value {shlex.quote(efi_part)}); "
            f'echo "UUID=$ROOT_UUID / ext4 defaults,noatime 0 1" > /mnt/etc/fstab; '
            f'echo "UUID=$EFI_UUID /boot/efi vfat umask=0077 0 2" >> /mnt/etc/fstab'
        )
        mount_root_cmd = (
            f"mount {shlex.quote(root_part)} /mnt && mountpoint -q /mnt && mkdir -p /mnt/boot "
            f"&& mkdir -p /mnt/boot/efi && mount {shlex.quote(efi_part)} /mnt/boot/efi"
        )
        # Register EFI NVRAM entry so firmware can boot GreenWayOS alongside others
        grub_install_cmd = (
            "chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi "
            "--bootloader-id=GreenWayOS --recheck --force"
        )
    else:
        root_part = get_partition_name(disk, 2) if method == "manual" else get_partition_name(disk, 2)
        partition_cmd = (
            f"set -e; swapoff -a 2>/dev/null || true; umount {disk_q}* 2>/dev/null || true; "
            f"wipefs --all --force {disk_q}; "
            f"dd if=/dev/zero of={disk_q} bs=1M count=10; "
            f"parted -s {disk_q} mklabel gpt "
            f"mkpart bios_grub 1MiB 3MiB set 1 bios_grub on "
            f"mkpart primary ext4 3MiB 100%; "
            f"partprobe {disk_q}; sleep 2"
        )
        if method == "manual":
            partition_cmd = (
                f"set -e; swapoff -a 2>/dev/null || true; umount {disk_q}* 2>/dev/null || true; "
                f"wipefs --all --force {disk_q}; "
                f"parted -s {disk_q} mklabel gpt "
                f"mkpart bios_grub 1MiB 3MiB set 1 bios_grub on "
                f"mkpart primary ext4 3MiB 90% "
                f"mkpart primary ext4 90% 100%; "
                f"partprobe {disk_q}; sleep 2"
            )
        efi_part = ""
        format_cmd = f"mkfs.ext4 -F {shlex.quote(root_part)}"
        fstab_cmd = (
            f"ROOT_UUID=$(blkid -s UUID -o value {shlex.quote(root_part)}); "
            f'echo "UUID=$ROOT_UUID / ext4 defaults,noatime 0 1" > /mnt/etc/fstab'
        )
        mount_root_cmd = (
            f"mount {shlex.quote(root_part)} /mnt && mountpoint -q /mnt && mkdir -p /mnt/boot"
        )
        grub_install_cmd = f"chroot /mnt grub-install --target=i386-pc --recheck --force {disk_q}"

    return partition_cmd, format_cmd, efi_part, root_part, fstab_cmd, mount_root_cmd, grub_install_cmd


def build_dualboot_layout(
    disk_q: str,
    disk: str,
    boot_mode: str,
) -> Tuple[str, str, str, str, str, str, str]:
    """
    Non-destructive UEFI dual-boot: reuse existing ESP, create root in free space.
    Does NOT wipe the disk or format the ESP.
    """
    ok, msg, info = assess_dualboot(disk, boot_mode)
    if not ok:
        raise ValueError(msg)

    esp = info["esp"]
    start_mib, end_mib, size_mib = info["free"]
    # Leave 1 MiB alignment margin at each end of the free region
    use_start = start_mib + 1
    use_end = end_mib - 1
    if use_end - use_start < 20 * 1024:
        raise ValueError(f"Aligned free space too small after margins ({size_mib} MiB raw)")

    esp_q = shlex.quote(esp)
    before_parts = list_partition_paths(disk)
    before_list = " ".join(shlex.quote(p) for p in before_parts)

    # Create only a new Linux root partition; never wipe / never touch ESP
    partition_cmd = (
        f"set -e; "
        f"echo '>>> Dual-boot: keeping existing partitions, creating root in free space'; "
        f"umount {esp_q} 2>/dev/null || true; "
        f"parted -s -a optimal {disk_q} unit MiB "
        f"mkpart GWOS_ROOT ext4 {use_start} {use_end}; "
        f"partprobe {disk_q}; sleep 2; "
        f"udevadm settle --timeout=10 2>/dev/null || sleep 2; "
        # Resolve new partition path (not in the before-set)
        f"ROOT_PART=''; "
        f"for p in $(lsblk -ln -o NAME,TYPE {disk_q} | awk '$2==\"part\"{{print \"/dev/\"$1}}'); do "
        f"  case \" {before_list} \" in *\" $p \"*) ;; *) ROOT_PART=$p; break ;; esac; "
        f"done; "
        f"if [ -z \"$ROOT_PART\" ]; then "
        f"  echo 'ERROR: could not detect new root partition'; lsblk {disk_q}; exit 1; "
        f"fi; "
        f"echo \"$ROOT_PART\" > /tmp/greenwayos-dualboot-root; "
        f"echo '>>> New root partition:' \"$ROOT_PART\""
    )

    # format/mount/fstab read root path from /tmp/greenwayos-dualboot-root written above
    format_cmd = (
        "set -e; "
        "ROOT_PART=$(cat /tmp/greenwayos-dualboot-root); "
        f"ESP={esp_q}; "
        "mkfs.ext4 -F -L GreenWayOS \"$ROOT_PART\""
    )

    fstab_cmd = (
        "set -e; "
        "ROOT_PART=$(cat /tmp/greenwayos-dualboot-root); "
        f"ESP={esp_q}; "
        "ROOT_UUID=$(blkid -s UUID -o value \"$ROOT_PART\"); "
        "EFI_UUID=$(blkid -s UUID -o value \"$ESP\"); "
        'echo "UUID=$ROOT_UUID / ext4 defaults,noatime 0 1" > /mnt/etc/fstab; '
        'echo "UUID=$EFI_UUID /boot/efi vfat umask=0077 0 2" >> /mnt/etc/fstab'
    )

    mount_root_cmd = (
        "set -e; "
        "ROOT_PART=$(cat /tmp/greenwayos-dualboot-root); "
        f"ESP={esp_q}; "
        "mount \"$ROOT_PART\" /mnt && mountpoint -q /mnt && "
        "mkdir -p /mnt/boot /mnt/boot/efi && mount \"$ESP\" /mnt/boot/efi"
    )

    grub_install_cmd = (
        "chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi "
        "--bootloader-id=GreenWayOS --recheck --force"
    )

    # Placeholder paths for logging; real root is resolved at runtime
    root_placeholder = "(dualboot-new)"
    return (
        partition_cmd,
        format_cmd,
        esp,
        root_placeholder,
        fstab_cmd,
        mount_root_cmd,
        grub_install_cmd,
    )


def build_lvm_layout(disk_q: str, disk: str, boot_mode: str) -> Tuple[str, ...]:
    """Placeholder for future full LVM support."""
    raise NotImplementedError("LVM layout is not implemented yet; use guided partitioning.")
