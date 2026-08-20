"""Shared GreenWayOS installation backend (TUI + GUI)."""
from .engine import INSTALL_STEPS, install_system, run_command_live, cleanup_install_mounts
from .disk import (
    assess_dualboot,
    check_disk_space,
    detect_boot_mode,
    get_disks,
    get_live_boot_disk,
)
from .password import set_password_securely
from .constants import EXPERT_PROFILES
from .network import check_network_ready, check_internet
from .state import normalize_install_state

__all__ = [
    "INSTALL_STEPS",
    "install_system",
    "run_command_live",
    "cleanup_install_mounts",
    "check_disk_space",
    "detect_boot_mode",
    "get_disks",
    "get_live_boot_disk",
    "assess_dualboot",
    "set_password_securely",
    "EXPERT_PROFILES",
    "check_network_ready",
    "check_internet",
    "normalize_install_state",
]
