"""Installation constants shared by text and graphical installers."""

INSTALL_STEPS = [
    ("Checking network", 2),
    ("Partitioning disk", 5),
    ("Formatting partitions", 8),
    ("Mounting filesystems", 10),
    ("Installing base system (debootstrap)", 35),
    ("Preparing chroot mounts", 5),
    ("Copying DNS config", 3),
    ("Writing /etc/fstab", 8),
    ("Installing GreenWayOS packages", 20),
    ("Configuring locale/timezone/hostname & user", 10),
    ("Setting up user password (secure)", 3),
    ("Copying GreenWayOS branding & tools", 10),
    ("Applying security hardening", 3),
    ("Configuring SSH host keys & service", 2),
    ("Updating initramfs", 5),
    ("Enabling first-boot service", 2),
    ("Installing GRUB bootloader", 10),
    ("Generating GRUB config", 5),
    ("Final sync", 2),
]

EXPERT_PROFILES = {
    # Only real Debian Bookworm package names (unknown pkgs are skipped in chroot-apt,
    # but bad names still waste time and clutter logs).
    "systems_engineering": [
        "ansible", "terraform", "vagrant", "docker.io", "docker-compose",
        "tmux", "screen", "byobu", "jq", "xmlstarlet", "miller",
        "ethtool", "iperf3", "nethogs", "iftop", "mtr",
        "smartmontools", "ncdu", "lm-sensors", "hwinfo", "inxi",
        "python3-pip", "python3-venv", "python3-dev",
        "git", "git-flow", "cmake", "make", "gcc", "g++", "gdb", "valgrind",
        "strace", "ltrace", "linux-perf",
        "qemu-system-x86", "supervisor", "wget", "curl", "rsync", "pv",
    ],
    "computer_security": [
        "hydra", "sqlmap", "nikto", "aircrack-ng", "wireshark-common",
        "john", "lynis", "rkhunter", "aide", "auditd", "apparmor", "apparmor-utils",
        "ufw", "fail2ban", "nftables",
        "foremost", "sleuthkit", "chkrootkit", "clamav",
        "openssl", "gnupg", "openssh-client", "openssh-server",
        "tor", "privoxy", "proxychains4",
    ],
    "infotecs_corporate": [
        "ansible", "puppet", "salt-minion",
        "jq", "xmlstarlet", "auditd", "aide", "lynis",
        "fail2ban", "ufw", "apparmor", "apparmor-utils", "nftables",
        "apparmor-profiles", "apparmor-profiles-extra",
        "openssh-server", "openssh-client", "openssh-sftp-server",
        "rsyslog", "logrotate", "postgresql-client", "default-mysql-client", "sqlite3",
        "rsync", "bind9-utils", "net-tools", "openvpn", "tinc", "strongswan",
        "git", "python3", "python3-pip", "perl", "ruby", "curl", "wget", "pv", "tmux",
    ],
}

DEFAULT_MIRROR = "http://deb.debian.org/debian"
MIRROR_PRESETS = [
    ("Debian (official HTTP)", "http://deb.debian.org/debian"),
    ("Yandex (RU HTTP)", "http://mirror.yandex.ru/debian"),
    ("Debian CDN", "http://cdn.debian.net/debian"),
]

GUI_PROFILE_MAP = {
    "standard": (False, "standard"),
    "engineering": (True, "systems_engineering"),
    "security": (True, "computer_security"),
    "corporate": (True, "infotecs_corporate"),
}
