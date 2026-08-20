"""Core installation engine (debootstrap, chroot, GRUB)."""
import shlex
import subprocess
import time

from .constants import DEFAULT_MIRROR, EXPERT_PROFILES, INSTALL_STEPS
from .disk import assess_dualboot, check_disk_space, detect_boot_mode, get_live_boot_disk
from .logutil import INSTALL_LOG, log_header, setup_install_logger
from .network import check_network_ready
from .partition import build_auto_layout, build_lvm_layout
from .password import set_password_securely
from .progress import InstallProgress, format_duration, should_persist_line, should_stream_line
from .state import normalize_install_state

logger = setup_install_logger()


def run_command_live(cmd, log_list, log_cb=None, progress=None):
    try:
        display_cmd = cmd
        if isinstance(cmd, str):
            cmd = ["bash", "-lc", cmd]
        log_list.append(f"$ {display_cmd}")
        if log_cb:
            log_cb(f"$ {display_cmd}")
            logger.debug("Command: %s", display_cmd)

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        for line in proc.stdout:
            line = line.rstrip()
            log_list.append(line)
            if progress:
                progress.feed_line(line)
            if log_cb and should_stream_line(line):
                log_cb(line)
                if should_persist_line(line):
                    logger.info(line)
        proc.wait()
        return proc.returncode == 0
    except Exception as exc:
        log_list.append(str(exc))
        if log_cb:
            log_cb(str(exc))
        logger.exception("Command failed")
        return False


def cleanup_install_mounts(log_cb):
    log_cb(">>> Running install cleanup...")
    logger.info("Running install cleanup")
    subprocess.run(["sync"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    for mp in ["/mnt/boot/efi", "/mnt/run", "/mnt/sys", "/mnt/proc", "/mnt/dev", "/mnt"]:
        subprocess.run(["umount", mp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def install_system(state, progress_cb, log_cb, done_cb, error_cb):
    """Run full installation; callbacks match TUI/GUI threading."""
    state = normalize_install_state(state)
    log_header(logger, state)

    disk = state.get("disk", "/dev/sda")
    tz = state.get("timezone", "UTC")
    locale = state.get("locale", "en_US.UTF-8")
    hostname = state.get("hostname", "greenwayos")
    username = state.get("username", "user")
    password = state.get("password") or ""
    if not password:
        error_cb("Password is required")
        return

    expert_mode = bool(state.get("expert_mode", False))
    expert_profile = state.get("expert_profile", "standard")
    install_ssh = bool(state.get("install_ssh", False))
    hardening_level = state.get("hardening_level", "none")
    boot_mode = state.get("boot_mode") or detect_boot_mode()
    partition_method = state.get("partition_method", "quick")
    mirror = state.get("debootstrap_mirror", DEFAULT_MIRROR)
    mirror_q = shlex.quote(mirror)
    disk_q = shlex.quote(disk)

    live_disk = get_live_boot_disk()
    if live_disk and disk == live_disk:
        error_cb(f"Refusing to install to live boot device: {disk}")
        return

    progress = InstallProgress(INSTALL_STEPS, progress_cb, log_cb, file_log=logger.info)

    log_cb(f">>> Install log: {INSTALL_LOG}")
    log_cb(f">>> Total steps: {len(INSTALL_STEPS)} (typical time: 25–45 min, packages: 15–45 min)")
    if partition_method == "dualboot":
        ok_db, msg_db, info_db = assess_dualboot(disk, boot_mode or detect_boot_mode())
        if not ok_db:
            error_cb(msg_db)
            return
        space_ok, space_msg, _size_gb = True, msg_db, float(info_db.get("free_gb") or 0)
    else:
        space_ok, space_msg, _size_gb = check_disk_space(disk, required_gb=20)
    if not space_ok:
        error_cb(space_msg)
        return
    log_cb(f">>> {space_msg}")

    net_ok, net_msg = check_network_ready(state)
    if not net_ok:
        error_cb(net_msg)
        return
    log_cb(f">>> {net_msg}")

    try:
        if partition_method == "lvm":
            build_lvm_layout(disk_q, disk, boot_mode)
        if partition_method == "dualboot":
            log_cb(">>> Dual-boot: existing OS partitions will be KEPT (ESP reused)")
        else:
            log_cb(">>> Guided wipe: ALL data on the selected disk will be erased")

        (
            partition_cmd,
            format_cmd,
            _efi_part,
            root_part,
            fstab_cmd,
            mount_root_cmd,
            grub_install_cmd,
        ) = build_auto_layout(disk_q, disk, boot_mode, partition_method)
    except NotImplementedError as exc:
        error_cb(str(exc))
        return
    except ValueError as exc:
        error_cb(str(exc))
        return

    hostname_q = shlex.quote(hostname)
    username_q = shlex.quote(username)
    tz_q = shlex.quote(tz)
    locale_q = shlex.quote(locale)
    user_cfg_host_path_q = shlex.quote(f"/mnt/home/{username}/.config")
    user_cfg_chroot_path_q = shlex.quote(f"/home/{username}/.config")
    safe_hosts_hostname = hostname.replace("\n", "").replace("\r", "")

    extra_packages = list(state.get("packages") or [])
    if expert_mode:
        profile_pkgs = EXPERT_PROFILES.get(expert_profile, [])
        extra_packages.extend(profile_pkgs)
        log_cb(f">>> Expert profile '{expert_profile}': +{len(profile_pkgs)} optional packages")
    if install_ssh and "openssh-server" not in extra_packages:
        extra_packages.append("openssh-server")
    extra_packages = list(dict.fromkeys(extra_packages))
    ssh_allow_cmd = "ufw allow OpenSSH || true; " if install_ssh else ""
    ssh_setup_cmd = (
        "chroot /mnt bash -lc \""
        "rm -f /etc/ssh/ssh_host_*_key* 2>/dev/null || true; "
        "dpkg-reconfigure openssh-server 2>/dev/null || true; "
        "systemctl enable ssh 2>/dev/null || true; "
        "true\""
        if install_ssh
        else "true"
    )
    if hardening_level == "balanced":
        hardening_cmd = (
            "chroot /mnt bash -lc \""
            "systemctl enable fail2ban 2>/dev/null || true; "
            "systemctl enable auditd 2>/dev/null || true; "
            "ufw --force reset || true; "
            "ufw default deny incoming || true; "
            "ufw default allow outgoing || true; "
            f"{ssh_allow_cmd}"
            "ufw --force enable || true; "
            "true\""
        )
    elif hardening_level == "strict":
        hardening_cmd = (
            "chroot /mnt bash -lc \""
            "systemctl enable fail2ban 2>/dev/null || true; "
            "systemctl enable auditd 2>/dev/null || true; "
            "ufw --force reset || true; "
            "ufw default deny incoming || true; "
            "ufw default allow outgoing || true; "
            f"{ssh_allow_cmd}"
            "ufw --force enable || true; "
            "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true; "
            "sed -i 's/^#\\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config 2>/dev/null || true; "
            "systemctl enable apparmor 2>/dev/null || true; "
            "true\""
        )
    else:
        hardening_cmd = "true"

    boot_mode_q = shlex.quote(boot_mode)
    extra_packages_q = shlex.quote(" ".join(extra_packages))
    # Prefer HTTP mirror for install reliability (HTTPS hangs on some RU networks)
    if mirror.startswith("https://"):
        mirror_http = "http://" + mirror[len("https://") :]
        log_cb(f">>> Using HTTP mirror for apt: {mirror_http} (from {mirror})")
        mirror = mirror_http
        mirror_q = shlex.quote(mirror)
    log_cb(f">>> Boot mode: {boot_mode.upper()} | layout: {partition_method} | mirror: {mirror}")

    step_cmds = [
        "true",
        partition_cmd,
        format_cmd,
        mount_root_cmd,
        (
            f"debootstrap --arch amd64 bookworm /mnt {mirror_q}"
            " && [ -d /mnt/etc ] && [ -d /mnt/usr/bin ] && [ -d /mnt/var ] && [ -x /mnt/bin/bash ]"
        ),
        "mount --bind /dev /mnt/dev && mount -t proc proc /mnt/proc && mount --bind /sys /mnt/sys && mount --bind /run /mnt/run",
        "cp /etc/resolv.conf /mnt/etc/resolv.conf",
        fstab_cmd,
        (
            "cp /usr/local/lib/greenwayos/install/chroot-apt.sh /mnt/tmp/chroot-apt.sh && "
            "chmod +x /mnt/tmp/chroot-apt.sh && "
            f"chroot /mnt /tmp/chroot-apt.sh {boot_mode_q} {extra_packages_q} {mirror_q}"
        ),
        f"chroot /mnt bash -lc \""
        f"ln -sf /usr/share/zoneinfo/{tz_q} /etc/localtime; "
        f"echo {tz_q} > /etc/timezone; "
        f"echo {locale_q} UTF-8 > /etc/locale.gen; "
        f"locale-gen; "
        f"update-locale LANG={locale_q}; "
        f"echo {hostname_q} > /etc/hostname; "
        "cat > /etc/hosts <<'EOF'\n"
        "127.0.0.1   localhost\n"
        "127.0.1.1   " + safe_hosts_hostname + "\n"
        "::1         localhost ip6-localhost ip6-loopback\n"
        "EOF\n"
        f"useradd -m -s /bin/bash -G sudo {username_q}; "
        "passwd -l root 2>/dev/null || true; usermod -L root 2>/dev/null || true; "
        f"true\"",
        "true",
        # Copy ctOS HUD theme + branding so installed OS matches Live
        "mkdir -p /mnt/usr/share/icons/hicolor/64x64/apps "
        "/mnt/etc/xdg/autostart /mnt/usr/local/bin /mnt/usr/share/greenwayos "
        "/mnt/usr/share/themes /mnt/etc/skel /mnt/etc/lightdm "
        "/mnt/home && true; "
        "cp /etc/os-release /mnt/etc/os-release; "
        "cp /etc/lsb-release /mnt/etc/lsb-release 2>/dev/null || true; "
        "cp /etc/issue /mnt/etc/issue 2>/dev/null || true; "
        "cp /etc/issue.net /mnt/etc/issue.net 2>/dev/null || true; "
        "cp /etc/motd /mnt/etc/motd 2>/dev/null || true; "
        "cp /etc/sysctl.d/99-greenwayos.conf /mnt/etc/sysctl.d/99-greenwayos.conf 2>/dev/null || true; "
        "mkdir -p /mnt/etc/iptables && cp /etc/iptables/rules.v4 /mnt/etc/iptables/rules.v4 2>/dev/null || true; "
        # Theme package
        "rsync -a /usr/share/greenwayos/ /mnt/usr/share/greenwayos/ 2>/dev/null || true; "
        "rsync -a /usr/share/themes/GreenWay-ctOS/ /mnt/usr/share/themes/GreenWay-ctOS/ 2>/dev/null || true; "
        "if [ -d /etc/xdg/xfce4 ]; then "
        "  mkdir -p /mnt/etc/xdg; rsync -a /etc/xdg/xfce4/ /mnt/etc/xdg/xfce4/ 2>/dev/null || true; "
        "fi; "
        "if [ -d /etc/skel ]; then "
        "  rsync -a /etc/skel/ /mnt/etc/skel/ 2>/dev/null || true; "
        "fi; "
        "if [ -d /etc/lightdm/lightdm-gtk-greeter.conf.d ]; then "
        "  mkdir -p /mnt/etc/lightdm/lightdm-gtk-greeter.conf.d; "
        "  rsync -a /etc/lightdm/lightdm-gtk-greeter.conf.d/ /mnt/etc/lightdm/lightdm-gtk-greeter.conf.d/ 2>/dev/null || true; "
        "fi; "
        "cp /etc/xdg/autostart/greenwayos-welcome.desktop /mnt/etc/xdg/autostart/greenwayos-welcome.desktop 2>/dev/null || true; "
        "cp /etc/xdg/autostart/greenwayos-audio.desktop /mnt/etc/xdg/autostart/greenwayos-audio.desktop 2>/dev/null || true; "
        "cp /usr/local/bin/greenwayos-audio-setup /mnt/usr/local/bin/greenwayos-audio-setup 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/greenwayos-audio-setup 2>/dev/null || true; "
        "cp /usr/local/bin/neofetch /mnt/usr/local/bin/neofetch 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/neofetch 2>/dev/null || true; "
        "cp /usr/local/bin/greenwayos-about /mnt/usr/local/bin/greenwayos-about 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/greenwayos-about 2>/dev/null || true; "
        "cp /usr/local/bin/greenwayos-welcome /mnt/usr/local/bin/greenwayos-welcome 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/greenwayos-welcome 2>/dev/null || true; "
        "cp /usr/local/bin/greenwayos-ctos-hud /mnt/usr/local/bin/greenwayos-ctos-hud 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/greenwayos-ctos-hud 2>/dev/null || true; "
        "cp /usr/local/bin/greenwayos-welcome-legacy /mnt/usr/local/bin/greenwayos-welcome-legacy 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/greenwayos-welcome-legacy 2>/dev/null || true; "
        "cp /usr/local/bin/greenwayos-firstboot /mnt/usr/local/bin/greenwayos-firstboot 2>/dev/null || true; "
        "chmod +x /mnt/usr/local/bin/greenwayos-firstboot 2>/dev/null || true; "
        "mkdir -p /mnt/etc/systemd/system && cp /etc/systemd/system/greenwayos-firstboot.service /mnt/etc/systemd/system/greenwayos-firstboot.service 2>/dev/null || true; "
        "mkdir -p /mnt/usr/share/applications && cp /usr/share/applications/greenwayos-about.desktop /mnt/usr/share/applications/greenwayos-about.desktop 2>/dev/null || true; "
        # GRUB ctOS theme + distributor for installed system
        "mkdir -p /mnt/usr/share/grub/themes /mnt/boot/grub /mnt/etc/default/grub.d; "
        "rsync -a /usr/share/grub/themes/GreenWay-ctOS/ /mnt/usr/share/grub/themes/GreenWay-ctOS/ 2>/dev/null || true; "
        "if [ ! -f /mnt/usr/share/grub/themes/GreenWay-ctOS/background.png ] && [ -f /usr/share/greenwayos/ctos/wallpaper.png ]; then "
        "  cp -f /usr/share/greenwayos/ctos/wallpaper.png /mnt/usr/share/grub/themes/GreenWay-ctOS/background.png; "
        "fi; "
        "cp /etc/default/grub.d/99-greenwayos.cfg /mnt/etc/default/grub.d/99-greenwayos.cfg 2>/dev/null || true; "
        "cp /etc/default/grub.d/10-os-prober.cfg /mnt/etc/default/grub.d/10-os-prober.cfg 2>/dev/null || true; "
        "cp /boot/grub/custom.cfg /mnt/boot/grub/custom.cfg 2>/dev/null || true; "
        "if [ -f /mnt/etc/default/grub ]; then "
        "  sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR=\"GreenWayOS\"/' /mnt/etc/default/grub; "
        "  grep -q '^GRUB_DISTRIBUTOR=' /mnt/etc/default/grub || echo 'GRUB_DISTRIBUTOR=\"GreenWayOS\"' >> /mnt/etc/default/grub; "
        "  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /mnt/etc/default/grub; "
        "  if grep -q '^GRUB_THEME=' /mnt/etc/default/grub; then "
        "    sed -i 's|^GRUB_THEME=.*|GRUB_THEME=\"/usr/share/grub/themes/GreenWay-ctOS/theme.txt\"|' /mnt/etc/default/grub; "
        "  else "
        "    echo 'GRUB_THEME=\"/usr/share/grub/themes/GreenWay-ctOS/theme.txt\"' >> /mnt/etc/default/grub; "
        "  fi; "
        "fi; "
        "cp /etc/default/keyboard /mnt/etc/default/keyboard 2>/dev/null || true; "
        "cp /usr/share/icons/hicolor/64x64/apps/greenwayos-logo.svg /mnt/usr/share/icons/hicolor/64x64/apps/greenwayos-logo.svg 2>/dev/null || true; "
        # Apply skel theme into new user home
        f"if [ -d /mnt/etc/skel/.config ]; then "
        f"  mkdir -p {user_cfg_host_path_q}; "
        f"  cp -a /mnt/etc/skel/.config/. {user_cfg_host_path_q}/ 2>/dev/null || true; "
        f"  chroot /mnt chown -R {username_q}:{username_q} {user_cfg_chroot_path_q} 2>/dev/null || true; "
        "fi; "
        "if [ -d /root/.config ]; then "
        "  mkdir -p /mnt/root/.config; cp -a /root/.config/* /mnt/root/.config/ 2>/dev/null || true; "
        "fi; "
        "chroot /mnt bash -lc '"
        "mkdir -p /etc/systemd/system; "
        "systemctl enable lightdm.service 2>/dev/null || true; "
        "systemctl set-default graphical.target 2>/dev/null || true; "
        "ln -sfn /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service; "
        "ln -sfn /lib/systemd/system/graphical.target /etc/systemd/system/default.target; "
        "echo /usr/sbin/lightdm > /etc/X11/default-display-manager; "
        "dpkg -l lightdm 2>/dev/null | grep -q \"^ii\" || { echo E: lightdm missing; exit 1; }; "
        "command -v lightdm >/dev/null || { echo E: lightdm binary missing; exit 1; }; "
        "test -L /etc/systemd/system/default.target || test -e /etc/systemd/system/default.target || { echo E: no default.target; exit 1; }; "
        "echo GUI_OK"
        "'; ",
        hardening_cmd,
        ssh_setup_cmd,
        "chroot /mnt update-initramfs -u -k all",
        "chroot /mnt systemctl enable greenwayos-firstboot.service 2>/dev/null || true",
        grub_install_cmd,
        # Enable os-prober then generate GRUB (Windows / other OS entries)
        "chroot /mnt bash -lc \""
        "mkdir -p /etc/default/grub.d; "
        "printf '%s\\n' 'GRUB_DISABLE_OS_PROBER=false' > /etc/default/grub.d/10-os-prober.cfg; "
        "if [ -f /etc/default/grub ]; then "
        "  sed -i 's/^#\\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub; "
        "  grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub || "
        "    echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub; "
        "fi; "
        "command -v os-prober >/dev/null && os-prober || true; "
        "grub-mkconfig -o /boot/grub/grub.cfg\"",
        "sync",
    ]

    log = []
    ok = True
    fail_msg = None

    for i, ((label, weight), cmd) in enumerate(zip(INSTALL_STEPS, step_cmds)):
        if not ok:
            break
        progress.begin_step(i, label, weight)
        logger.info("Step %d/%d: %s", i + 1, len(INSTALL_STEPS), label)

        if "password" in label.lower():
            log_cb(">>> Setting password via chpasswd (non-interactive)…")
            ok = set_password_securely(username, password, "/mnt")
            password = None
            state["password"] = None
            if not ok:
                fail_msg = f"Step failed: {label}"
        else:
            ok = run_command_live(cmd, log, log_cb=log_cb, progress=progress)

        progress.end_step(weight, ok=ok)
        if not ok:
            tail = [ln for ln in log[-40:] if ln.strip()]
            detail = "\n".join(tail[-20:]) if tail else "(no command output captured)"
            fail_msg = f"Step failed: {label}\n{detail}"
            break

    cleanup_install_mounts(log_cb)
    if fail_msg:
        error_cb(fail_msg)
        return

    progress_cb(100, f"Complete · {format_duration(time.monotonic() - progress.install_start)} total")
    log_cb(">>> Installation finished successfully")
    logger.info("Installation finished successfully")
    done_cb()
