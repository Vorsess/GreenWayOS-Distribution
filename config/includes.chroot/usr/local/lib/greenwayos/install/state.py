"""Normalize GUI/TUI install state before running the engine."""
from .constants import GUI_PROFILE_MAP


def normalize_install_state(state: dict) -> dict:
    s = dict(state)

    profile = s.get("profile")
    if profile and profile in GUI_PROFILE_MAP:
        expert_mode, expert_profile = GUI_PROFILE_MAP[profile]
        s.setdefault("expert_mode", expert_mode)
        s.setdefault("expert_profile", expert_profile)

    if s.get("boot_mode") == "auto":
        s.pop("boot_mode", None)

    sec = s.get("hardening_level")
    if sec is None and "security_level" in s:
        levels = ["none", "balanced", "strict"]
        idx = int(s.get("security_level", 1))
        s["hardening_level"] = levels[min(max(idx, 0), 2)]

    s.setdefault("partition_method", "quick")
    s.setdefault("debootstrap_mirror", s.get("mirror", "http://deb.debian.org/debian"))
    s.setdefault("network_mode", "local")
    s.setdefault("network_type", "dhcp")

    if s.get("network_type") == "static" and s.get("ip_address"):
        s.setdefault("static_network", {
            "ip": s.get("ip_address"),
            "netmask": s.get("netmask"),
            "gateway": s.get("gateway"),
            "dns": s.get("dns_servers"),
        })

    return s
