"""Disk detection and validation."""
import os
import re
import subprocess
import time
from typing import List, Optional, Tuple

_SKIP_NAMES = ("loop", "ram", "fd", "sr", "dm-", "zram")


def detect_boot_mode() -> str:
    return "uefi" if os.path.exists("/sys/firmware/efi") else "bios"


def get_live_boot_disk() -> Optional[str]:
    """Return whole disk to exclude from install targets (never the ISO CD-ROM itself)."""
    try:
        src = subprocess.check_output(
            ["findmnt", "-n", "-o", "SOURCE", "/run/live/medium"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).strip()
        if not src:
            return None
        parent = subprocess.check_output(
            ["lsblk", "-no", "PKNAME", src],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).strip()
        if parent:
            disk = f"/dev/{parent}"
        elif src.startswith("/dev/"):
            disk = src
        else:
            return None
        base = os.path.basename(disk)
        # Booting from optical / loop must not hide empty HDDs (common in VMware).
        if base.startswith(("sr", "loop", "ram", "fd")):
            return None
        return disk
    except Exception:
        return None


def _parse_lsblk_disk_line(line: str) -> Optional[Tuple[str, str, str]]:
    """Parse lsblk line; TYPE is the last column (MODEL may be empty)."""
    parts = line.split()
    if len(parts) < 3:
        return None
    if parts[-1] != "disk":
        return None
    name, size = parts[0], parts[1]
    model = " ".join(parts[2:-1]) if len(parts) > 3 else ""
    return f"/dev/{name}", size, model


def _settle_block_devices() -> None:
    """Wait briefly for udev/VM disks to appear (GUI boots slower than text)."""
    try:
        subprocess.run(
            ["udevadm", "settle", "--timeout=5"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
            check=False,
        )
    except Exception:
        time.sleep(1)


def _disks_from_sysfs(live_disk: Optional[str]) -> List[Tuple[str, str, str]]:
    disks: List[Tuple[str, str, str]] = []
    sys_block = "/sys/block"
    if not os.path.isdir(sys_block):
        return disks
    for dev_name in sorted(os.listdir(sys_block)):
        if dev_name.startswith(_SKIP_NAMES):
            continue
        dev = f"/dev/{dev_name}"
        if live_disk and dev == live_disk:
            continue
        size_path = f"{sys_block}/{dev_name}/size"
        if not os.path.isfile(size_path):
            continue
        try:
            sectors = int(open(size_path, encoding="ascii").read().strip())
            size_gb = (sectors * 512) / (1024 ** 3)
        except (OSError, ValueError):
            continue
        if size_gb < 1:
            continue
        model = ""
        model_path = f"{sys_block}/{dev_name}/device/model"
        if os.path.isfile(model_path):
            try:
                model = open(model_path, encoding="ascii", errors="replace").read().strip()
            except OSError:
                pass
        size_human = f"{size_gb:.0f}G" if size_gb >= 1 else f"{int(size_gb * 1024)}M"
        disks.append((dev, size_human, model or "Unknown"))
    return disks


def _lsblk_disks(live_disk: Optional[str]) -> List[Tuple[str, str, str]]:
    disks: List[Tuple[str, str, str]] = []
    seen = set()
    try:
        out = subprocess.check_output(
            ["lsblk", "-d", "-o", "NAME,SIZE,MODEL,TYPE", "--noheadings"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=10,
        ).strip()
        for line in out.splitlines():
            parsed = _parse_lsblk_disk_line(line.strip())
            if not parsed:
                continue
            dev, size, model = parsed
            base = os.path.basename(dev)
            if base.startswith(_SKIP_NAMES):
                continue
            if live_disk and dev == live_disk:
                continue
            if dev in seen:
                continue
            seen.add(dev)
            disks.append((dev, size, model or "Unknown"))
    except Exception:
        pass
    return disks


def get_disks() -> List[Tuple[str, str, str]]:
    live_disk = get_live_boot_disk()
    disks: List[Tuple[str, str, str]] = []

    for attempt in range(4):
        if attempt:
            time.sleep(1.5)
        else:
            _settle_block_devices()

        disks = _lsblk_disks(live_disk)
        if not disks:
            seen = {d[0] for d in disks}
            for entry in _disks_from_sysfs(live_disk):
                if entry[0] not in seen:
                    disks.append(entry)
                    seen.add(entry[0])
        if disks:
            break

    return disks


def list_disk_partitions(disk: str) -> List[str]:
    """Human-readable partition lines for a whole disk (for installer UI)."""
    parts: List[str] = []
    try:
        out = subprocess.check_output(
            ["lsblk", "-n", "-o", "NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE", disk],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=10,
        ).strip()
    except Exception:
        return parts

    disk_base = os.path.basename(disk)
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 2:
            continue
        name = cols[0].lstrip("├─└─│ ")
        if name == disk_base:
            continue
        if cols[-1] not in ("part", "crypt", "lvm"):
            continue
        size = cols[1] if len(cols) > 1 else "?"
        mid = cols[2:-1] if len(cols) > 2 else []
        fstype = mid[0] if mid else ""
        mount = mid[-1] if len(mid) > 1 else ""
        label = f"/dev/{name} {size}"
        if fstype:
            label += f" {fstype}"
        if mount:
            label += f" on {mount}"
        parts.append(label)
    return parts


def parse_size_human(size_str: str) -> float:
    """Parse lsblk SIZE column (e.g. 64G, 1.8T, 500M) to gibibytes."""
    s = str(size_str or "").upper().strip().replace(",", ".")
    m = re.match(r"^([\d.]+)\s*([KMGT])?I?B?$", s)
    if not m:
        return 0.0
    try:
        val = float(m.group(1))
    except ValueError:
        return 0.0
    mult = {"T": 1024, "G": 1, "M": 1 / 1024, "K": 1 / (1024 * 1024)}.get(m.group(2) or "G", 1)
    return val * mult


def check_disk_space(disk, required_gb=20) -> Tuple[bool, str, float]:
    try:
        result = subprocess.run(
            ["blockdev", "--getsize64", disk],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        size_gb = int(result.stdout.strip()) / (1024 ** 3)
        if size_gb < required_gb:
            return False, f"Disk too small: {size_gb:.1f}GB (need {required_gb}GB minimum)", size_gb
        return True, f"Disk OK: {size_gb:.1f}GB", size_gb
    except Exception as exc:
        return False, f"Error checking disk: {exc}", 0.0


def get_partition_name(dev: str, n: int) -> str:
    dev = (dev or "").strip()
    if not dev.startswith("/dev/"):
        raise ValueError(f"Invalid disk path: {dev!r}")
    dev_base = re.sub(r"[p]?\d+$", "", dev)
    if re.match(r"^/dev/nvme\d+n\d+$", dev_base):
        return f"{dev_base}p{n}"
    if re.match(r"^/dev/mmcblk\d+$", dev_base):
        return f"{dev_base}p{n}"
    if re.match(r"^/dev/(sd|hd)[a-z]$", dev_base):
        return f"{dev_base}{n}"
    if re.match(r"^/dev/(vd|xvd)[a-z]$", dev_base):
        return f"{dev_base}{n}"
    if re.match(r"^/dev/loop\d+$", dev_base):
        raise ValueError(f"Loop device not supported for installation: {dev_base}")
    return f"{dev_base}p{n}" if dev_base and dev_base[-1].isdigit() else f"{dev_base}{n}"


def list_partition_paths(disk: str) -> List[str]:
    """Return /dev/... paths for partitions on disk."""
    paths: List[str] = []
    try:
        out = subprocess.check_output(
            ["lsblk", "-ln", "-o", "NAME,TYPE", disk],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=10,
        ).strip()
    except Exception:
        return paths
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 2 or cols[-1] != "part":
            continue
        paths.append(f"/dev/{cols[0]}")
    return paths


def find_esp_partition(disk: str) -> Optional[str]:
    """Find an EFI System Partition on disk (PARTTYPE / flags / vfat+boot)."""
    # GPT type GUID for ESP
    esp_guids = {
        "c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
        "C12A7328-F81F-11D2-BA4B-00A0C93EC93B",
    }
    try:
        out = subprocess.check_output(
            ["lsblk", "-ln", "-o", "NAME,TYPE,FSTYPE,PARTTYPE,PARTFLAGS", disk],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=10,
        ).strip()
    except Exception:
        out = ""

    candidates: List[str] = []
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 2 or cols[1] != "part":
            continue
        name = cols[0]
        fstype = cols[2] if len(cols) > 2 else ""
        parttype = cols[3] if len(cols) > 3 else ""
        flags = " ".join(cols[4:]) if len(cols) > 4 else ""
        path = f"/dev/{name}"
        if parttype in esp_guids or "esp" in flags.lower() or "boot" in flags.lower():
            if fstype in ("", "vfat", "fat32", "fat16", "efi"):
                return path
            candidates.append(path)
        elif fstype in ("vfat", "fat32") and not candidates:
            # Heuristic: first reasonably-sized FAT may be ESP
            try:
                sz = subprocess.check_output(
                    ["blockdev", "--getsize64", path],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=3,
                ).strip()
                mib = int(sz) / (1024 * 1024)
                if 32 <= mib <= 2048:
                    candidates.append(path)
            except Exception:
                pass
    return candidates[0] if candidates else None


def find_largest_free_mib(disk: str) -> Optional[Tuple[int, int, int]]:
    """
    Largest free region on GPT/MSDOS disk via parted machine output.
    Returns (start_mib, end_mib, size_mib) or None.
    """
    try:
        out = subprocess.check_output(
            ["parted", "-m", "-s", disk, "unit", "MiB", "print", "free"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except Exception:
        return None

    best: Optional[Tuple[int, int, int]] = None
    for line in out.splitlines():
        # parted -m: N:start:end:size:free;
        parts = line.strip().rstrip(";").split(":")
        if len(parts) < 5 or parts[4] != "free":
            continue
        try:
            start = int(float(parts[1].replace("MiB", "").replace("MB", "")))
            end = int(float(parts[2].replace("MiB", "").replace("MB", "")))
            size = int(float(parts[3].replace("MiB", "").replace("MB", "")))
        except ValueError:
            continue
        if best is None or size > best[2]:
            best = (start, end, size)
    return best


def disk_has_windows_hint(disk: str) -> bool:
    """True if disk looks like it may contain Windows (NTFS/BitLocker)."""
    try:
        out = subprocess.check_output(
            ["lsblk", "-ln", "-o", "FSTYPE", disk],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=10,
        ).lower()
    except Exception:
        return False
    return any(x in out for x in ("ntfs", "bitlocker", "windows_re"))


def assess_dualboot(disk: str, boot_mode: str, required_gb: float = 20.0) -> Tuple[bool, str, dict]:
    """
    Validate dual-boot install onto free space (keep existing OS).
    Returns (ok, message, info_dict).
    """
    info: dict = {"disk": disk, "boot_mode": boot_mode}
    if boot_mode != "uefi":
        return False, "Dual-boot requires UEFI (BIOS/Legacy Windows dual-boot is not supported)", info

    esp = find_esp_partition(disk)
    info["esp"] = esp
    if not esp:
        return False, "No EFI System Partition found on disk — cannot dual-boot safely", info

    free = find_largest_free_mib(disk)
    info["free"] = free
    if not free:
        return False, "No free (unallocated) space found — shrink Windows volume first", info

    start, end, size_mib = free
    size_gb = size_mib / 1024.0
    info["free_gb"] = size_gb
    if size_gb < required_gb:
        return (
            False,
            f"Free space too small: {size_gb:.1f}GB (need {required_gb:.0f}GB+ unallocated)",
            info,
        )

    info["windows_hint"] = disk_has_windows_hint(disk)
    msg = f"Dual-boot OK: ESP={esp}, free≈{size_gb:.1f}GB ({start}–{end} MiB)"
    if info["windows_hint"]:
        msg += " (Windows-like partitions detected)"
    return True, msg, info
