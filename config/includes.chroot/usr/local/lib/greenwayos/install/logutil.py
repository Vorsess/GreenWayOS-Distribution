"""Unified install logging."""
import logging
import os
from datetime import datetime

INSTALL_LOG = "/var/log/greenwayos-install.log"


def setup_install_logger(name: str = "greenwayos.install") -> logging.Logger:
    os.makedirs(os.path.dirname(INSTALL_LOG), exist_ok=True)
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    fh = logging.FileHandler(INSTALL_LOG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)
    return logger


def log_header(logger: logging.Logger, state: dict) -> None:
    logger.info("=== GreenWayOS install started %s ===", datetime.now().isoformat())
    logger.info("disk=%s boot=%s mirror=%s", state.get("disk"), state.get("boot_mode"), state.get("debootstrap_mirror"))
