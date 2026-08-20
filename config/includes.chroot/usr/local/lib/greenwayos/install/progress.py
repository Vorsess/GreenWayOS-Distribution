"""Install progress tracking, ETA, and output parsing."""
import re
import time
from typing import Callable, Optional, Tuple

GWOS_STAGE_RE = re.compile(
    r"GWOS_APT_STAGE\s+(\d+)/(\d+)\s+(\S+)\s+(start|done|failed)"
    r"(?:\s+packages=(\d+))?(?:\s+elapsed=(\S+))?"
)
GWOS_EXTRA_RE = re.compile(r"GWOS_APT_EXTRA\s+(\d+)/(\d+)\s+(\S+)")
APT_UNPACK_RE = re.compile(r"^Unpacking\s+(\S+)")
APT_SETUP_RE = re.compile(r"^Setting up\s+(\S+)")

DEBOOTSTRAP_MARKERS = [
    ("Retrieving", 8, "downloading release"),
    ("Validating", 15, "validating release"),
    ("Installing core", 30, "core packages"),
    ("Unpacking the base system", 50, "unpacking base"),
    ("Configuring the base system", 72, "configuring base"),
    ("Configuring apt", 88, "configuring apt"),
    ("Cleaning up", 96, "finishing"),
]


def format_duration(seconds: Optional[float]) -> str:
    if seconds is None or seconds < 0:
        return "?"
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    minutes, secs = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m {secs:02d}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes:02d}m"


def should_stream_line(line: str) -> bool:
    s = line.strip()
    if not s:
        return False
    if s.startswith(">>> GWOS_"):
        return True
    if s.startswith("I:") or s.startswith("E:"):
        return True
    if s.startswith(("Get:", "Hit:", "Ign:", "Fetched", "Reading package", "Building dependency")):
        return True
    if s.startswith(("Unpacking ", "Setting up ", "Processing triggers", "Preparing to unpack")):
        return True
    if s.startswith("[apt-get attempt"):
        return True
    if s.startswith(("W:", "E: ", "ERROR", "debconf:")):
        return True
    if "GWOS_APT_" in s:
        return True
    return False


def should_persist_line(line: str) -> bool:
    s = line.strip()
    if not s or s.startswith("$"):
        return False
    return should_stream_line(s) or s.startswith(">>>")


class InstallProgress:
    """Weighted step progress with sub-stage updates and ETA."""

    def __init__(
        self,
        steps: list,
        progress_cb: Callable[[int, str], None],
        log_cb: Callable[[str], None],
        file_log: Optional[Callable[[str], None]] = None,
    ):
        self.steps = steps
        self.total_weight = sum(w for _, w in steps)
        self.step_total = len(steps)
        self.progress_cb = progress_cb
        self.log_cb = log_cb
        self.file_log = file_log or (lambda _msg: None)
        self.install_start = time.monotonic()
        self.step_start = self.install_start
        self.cumulative = 0
        self.current_weight = 0
        self.current_label = ""
        self.step_index = 0
        self.sub_pct = 0.0
        self.sub_detail = ""
        self._apt_stage_total = 0
        self._apt_stage_num = 0
        self._apt_pkg_total = 0
        self._apt_pkg_done = 0

    def _emit(self, label: Optional[str] = None):
        effective = self.cumulative + self.current_weight * (self.sub_pct / 100.0)
        pct = min(99, int(effective * 100 / self.total_weight)) if self.total_weight else 0
        eta = self._eta()
        parts = [f"Step {self.step_index + 1}/{self.step_total}"]
        parts.append(label or self.current_label)
        if self.sub_detail:
            parts.append(self.sub_detail)
        if eta is not None:
            parts.append(f"~{format_duration(eta)} left")
        self.progress_cb(pct, " · ".join(parts))

    def _eta(self) -> Optional[float]:
        effective = self.cumulative + self.current_weight * (self.sub_pct / 100.0)
        if effective <= 0:
            return None
        elapsed = time.monotonic() - self.install_start
        remaining_weight = self.total_weight - effective
        if remaining_weight <= 0:
            return 0
        return elapsed * remaining_weight / effective

    def begin_step(self, index: int, label: str, weight: int):
        self.step_index = index
        self.current_label = label
        self.current_weight = weight
        self.sub_pct = 0.0
        self.sub_detail = ""
        self._apt_stage_total = 0
        self._apt_stage_num = 0
        self._apt_pkg_total = 0
        self._apt_pkg_done = 0
        self.step_start = time.monotonic()
        elapsed = self.step_start - self.install_start
        eta = self._eta()
        eta_txt = format_duration(eta) if eta is not None else "?"
        msg = (
            f">>> Step {index + 1}/{self.step_total}: {label} — started "
            f"(elapsed {format_duration(elapsed)}, ~{eta_txt} remaining)"
        )
        self._log(msg)

    def end_step(self, weight: int, ok: bool = True):
        step_elapsed = time.monotonic() - self.step_start
        total_elapsed = time.monotonic() - self.install_start
        status = "done" if ok else "FAILED"
        self._log(
            f">>> Step {self.step_index + 1}/{self.step_total}: {self.current_label} — "
            f"{status} (step {format_duration(step_elapsed)}, total {format_duration(total_elapsed)})"
        )
        self.cumulative += weight
        self.sub_pct = 100.0
        self._emit()

    def feed_line(self, line: str):
        parsed = self._parse_line(line)
        if parsed:
            sub_pct, detail = parsed
            self.sub_pct = sub_pct
            if detail:
                self.sub_detail = detail
            self._emit()

    def _parse_line(self, line: str) -> Optional[Tuple[float, str]]:
        s = line.strip()

        m = GWOS_STAGE_RE.search(s)
        if m:
            stage_num = int(m.group(1))
            stage_total = int(m.group(2))
            stage_name = m.group(3)
            phase = m.group(4)
            pkg_count = m.group(5)
            elapsed = m.group(6)
            self._apt_stage_num = stage_num
            self._apt_stage_total = stage_total
            if pkg_count:
                self._apt_pkg_total = int(pkg_count)
                self._apt_pkg_done = 0
            if phase == "start":
                detail = f"[{stage_num}/{stage_total} {stage_name}]"
                if pkg_count:
                    detail += f" {pkg_count} packages"
                return self._apt_stage_pct(stage_num, stage_total, 0), detail
            if phase in ("done", "failed"):
                detail = f"[{stage_num}/{stage_total} {stage_name} {phase}]"
                if elapsed:
                    detail += f" {elapsed}"
                return self._apt_stage_pct(stage_num, stage_total, 100), detail

        m = GWOS_EXTRA_RE.search(s)
        if m:
            n, total, pkg = int(m.group(1)), int(m.group(2)), m.group(3)
            base = self._apt_stage_pct(self._apt_stage_total or 4, self._apt_stage_total or 4, 0)
            extra_pct = (n / max(total, 1)) * 15
            return min(99.0, base + extra_pct), f"expert {n}/{total}: {pkg}"

        for prefix in (APT_UNPACK_RE, APT_SETUP_RE):
            m = prefix.match(s)
            if m and self._apt_pkg_total > 0:
                self._apt_pkg_done = min(self._apt_pkg_total, self._apt_pkg_done + 1)
                pkg_pct = (self._apt_pkg_done / self._apt_pkg_total) * 100
                stage_pct = self._apt_stage_pct(
                    self._apt_stage_num or 1,
                    self._apt_stage_total or 3,
                    pkg_pct,
                )
                return stage_pct, f"{self._apt_pkg_done}/{self._apt_pkg_total} {m.group(1)}"

        if "debootstrap" in self.current_label.lower() or s.startswith("I:"):
            for marker, pct, detail in DEBOOTSTRAP_MARKERS:
                if marker in s:
                    return float(pct), detail

        return None

    def _apt_stage_pct(self, stage_num: int, stage_total: int, within_stage_pct: float) -> float:
        if stage_total <= 0:
            return within_stage_pct
        stage_span = 100.0 / stage_total
        return min(99.0, (stage_num - 1) * stage_span + stage_span * (within_stage_pct / 100.0))

    def _log(self, msg: str):
        self.log_cb(msg)
        if should_persist_line(msg):
            self.file_log(msg.lstrip("> ").strip() if msg.startswith(">>>") else msg)
