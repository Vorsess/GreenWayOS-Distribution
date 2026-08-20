"""Network checks and Wi-Fi setup for installers (nmcli / NetworkManager)."""
from __future__ import annotations

import shutil
import subprocess
import time
from typing import List, Optional, Tuple
from urllib.parse import urlparse

from .constants import DEFAULT_MIRROR


def check_internet(host: str = "8.8.8.8", count: int = 1, timeout: int = 3) -> bool:
    try:
        result = subprocess.run(
            ["ping", "-c", str(count), "-W", str(timeout), host],
            capture_output=True,
            timeout=timeout + 2,
        )
        return result.returncode == 0
    except Exception:
        return False


def mirror_host(mirror_url: str) -> str:
    parsed = urlparse(mirror_url or DEFAULT_MIRROR)
    return parsed.hostname or "deb.debian.org"


def check_network_ready(state: dict) -> Tuple[bool, str]:
    if state.get("skip_network_check"):
        return True, "Network check skipped"

    # Local / Ethernet path: user chose not to configure Wi-Fi
    if state.get("network_mode") == "local":
        if check_internet("8.8.8.8", count=1, timeout=3) or check_internet(
            mirror_host(state.get("debootstrap_mirror", DEFAULT_MIRROR)), count=1, timeout=4
        ):
            return True, "Local/Ethernet network OK"
        return False, (
            "No internet on local/Ethernet path. "
            "Connect a cable or go back and use Wi-Fi."
        )

    mirror = state.get("debootstrap_mirror", DEFAULT_MIRROR)
    host = mirror_host(mirror)

    if not check_internet(host, count=2, timeout=4):
        if not check_internet("8.8.8.8", count=1, timeout=3):
            return False, (
                f"No network reachability (cannot ping {host} or 8.8.8.8). "
                "Use Wi-Fi setup in the installer or connect Ethernet."
            )
        return True, f"Mirror host {host} unreachable; using general internet (8.8.8.8 OK)"

    return True, f"Network OK — mirror {mirror}"


def _run(cmd: List[str], timeout: int = 30) -> Tuple[int, str, str]:
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except Exception as exc:
        return 1, "", str(exc)


def nmcli_available() -> bool:
    return shutil.which("nmcli") is not None


def ensure_networkmanager() -> Tuple[bool, str]:
    """Start NetworkManager if present (needed for Wi-Fi in live/install)."""
    if not nmcli_available():
        return False, "nmcli/NetworkManager not installed"

    _run(["rfkill", "unblock", "wifi"], timeout=5)
    _run(["rfkill", "unblock", "wlan"], timeout=5)

    rc, _, err = _run(["nmcli", "general", "status"], timeout=8)
    if rc == 0:
        return True, "NetworkManager ready"

    _run(["systemctl", "unmask", "NetworkManager.service"], timeout=10)
    _run(["systemctl", "start", "NetworkManager.service"], timeout=30)
    time.sleep(1.5)

    rc, _, err = _run(["nmcli", "general", "status"], timeout=8)
    if rc == 0:
        return True, "NetworkManager started"
    return False, err or "NetworkManager failed to start"


def wifi_radio_on() -> None:
    _run(["nmcli", "radio", "wifi", "on"], timeout=10)


def scan_wifi(rescan: bool = True) -> List[dict]:
    """
    Return list of Wi-Fi networks:
      {"ssid": str, "signal": int, "security": str, "in_use": bool}
    """
    ok, msg = ensure_networkmanager()
    if not ok:
        return []

    wifi_radio_on()
    if rescan:
        _run(["nmcli", "device", "wifi", "rescan"], timeout=20)
        time.sleep(2)

    # --terse fields: SSID:SIGNAL:SECURITY:IN-USE
    rc, out, _ = _run(
        [
            "nmcli",
            "-t",
            "-f",
            "SSID,SIGNAL,SECURITY,IN-USE",
            "device",
            "wifi",
            "list",
        ],
        timeout=25,
    )
    if rc != 0 or not out:
        return []

    seen = set()
    networks: List[dict] = []
    for line in out.splitlines():
        # nmcli -t escapes ':' as '\:'
        parts: List[str] = []
        buf = ""
        esc = False
        for ch in line:
            if esc:
                buf += ch
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == ":":
                parts.append(buf)
                buf = ""
            else:
                buf += ch
        parts.append(buf)
        while len(parts) < 4:
            parts.append("")

        ssid = parts[0].strip()
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        try:
            signal = int(parts[1] or "0")
        except ValueError:
            signal = 0
        security = parts[2].strip() or "--"
        in_use = parts[3].strip() == "*"
        networks.append(
            {
                "ssid": ssid,
                "signal": signal,
                "security": security,
                "in_use": in_use,
            }
        )

    networks.sort(key=lambda n: (-int(n["in_use"]), -n["signal"], n["ssid"].lower()))
    return networks


def connect_wifi(ssid: str, password: Optional[str] = None, timeout: int = 45) -> Tuple[bool, str]:
    """Connect to Wi-Fi via nmcli. Empty password = open network."""
    ok, msg = ensure_networkmanager()
    if not ok:
        return False, msg

    wifi_radio_on()
    ssid = (ssid or "").strip()
    if not ssid:
        return False, "SSID is empty"

    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd.extend(["password", password])

    rc, out, err = _run(cmd, timeout=timeout)
    if rc != 0:
        detail = err or out or "connection failed"
        # Retry after delete stale connection profile
        _run(["nmcli", "connection", "delete", ssid], timeout=10)
        rc, out, err = _run(cmd, timeout=timeout)
        if rc != 0:
            return False, err or out or detail

    # Wait for connectivity
    for _ in range(15):
        if check_internet("8.8.8.8", count=1, timeout=2):
            return True, f"Connected to {ssid}"
        time.sleep(1)

    # Connected to AP but no internet yet — still OK for installer retry
    rc2, _, _ = _run(["nmcli", "-t", "-f", "GENERAL.STATE", "device", "show"], timeout=8)
    return True, f"Associated with {ssid} (waiting for internet…)"


def network_status_summary() -> str:
    if check_internet("8.8.8.8", count=1, timeout=2):
        return "Internet: OK"
    ok, _ = ensure_networkmanager()
    if not ok:
        return "Internet: no (NetworkManager missing)"
    rc, out, _ = _run(
        ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
        timeout=8,
    )
    if rc == 0 and out:
        lines = [ln for ln in out.splitlines() if ":connected:" in ln or ":connected (" in ln]
        if lines:
            return "Link up, no internet yet"
    return "Internet: offline"
