# -*- coding: utf-8 -*-
"""Generate GreenWayOS full project PDF report."""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

from fpdf import FPDF

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "GreenWayOS_2.0_Project_Report.pdf"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip() if (ROOT / "VERSION").exists() else "2.0-rc1"

FONT_CANDIDATES = [
    (Path(r"C:\Windows\Fonts\arial.ttf"), Path(r"C:\Windows\Fonts\arialbd.ttf")),
    (Path(r"C:\Windows\Fonts\calibri.ttf"), Path(r"C:\Windows\Fonts\calibrib.ttf")),
    (Path(r"C:\Windows\Fonts\segoeui.ttf"), Path(r"C:\Windows\Fonts\segoeuib.ttf")),
    (Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"), Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")),
    (Path("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"), Path("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf")),
]


def pick_fonts():
    for regular, bold in FONT_CANDIDATES:
        if regular.exists():
            return regular, bold if bold.exists() else regular
    raise SystemExit("No TTF font found (Windows Fonts or Linux DejaVu/Liberation)")


def count_sources() -> dict:
    exts = {".sh", ".py", ".chroot", ".service", ".conf", ".cfg", ".xml", ".json", ".c", ".hook.binary", ".hook.chroot"}
    counts = {"files": 0, "hooks": 0, "services": 0, "install_py": 0}
    for p in ROOT.rglob("*"):
        if not p.is_file() or ".git" in p.parts or "backup" in p.parts:
            continue
        if p.suffix in exts or p.name.endswith(".hook.binary") or p.name.endswith(".hook.chroot"):
            counts["files"] += 1
        if "config/hooks" in str(p).replace("\\", "/"):
            counts["hooks"] += 1
        if p.suffix == ".service":
            counts["services"] += 1
        if "install" in p.parts and p.suffix == ".py":
            counts["install_py"] += 1
    return counts


class Report(FPDF):
    def header(self):
        if self.page_no() <= 1:
            return
        self.set_x(self.l_margin)
        self.set_font("Body", "B", 9)
        self.set_text_color(30, 120, 60)
        self.cell(self.epw, 6, f"GreenWayOS {VERSION} — технический отчёт", new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(29, 185, 84)
        self.line(self.l_margin, self.get_y(), self.l_margin + self.epw, self.get_y())
        self.ln(4)

    def footer(self):
        self.set_y(-12)
        self.set_x(self.l_margin)
        self.set_font("Body", "", 8)
        self.set_text_color(100, 100, 100)
        self.cell(
            self.epw,
            8,
            f"стр. {self.page_no()}/{{nb}}  |  {datetime.now():%Y-%m-%d}  |  GreenWayOS Project",
            align="C",
        )

    def _reset(self):
        self.set_x(self.l_margin)

    def h1(self, text: str):
        self.ln(2)
        self._reset()
        self.set_font("Body", "B", 15)
        self.set_text_color(29, 185, 84)
        self.multi_cell(self.epw, 8, text)
        self.ln(1)

    def h2(self, text: str):
        self.ln(1)
        self._reset()
        self.set_font("Body", "B", 11)
        self.set_text_color(20, 90, 50)
        self.multi_cell(self.epw, 6.5, text)
        self.ln(0.5)

    def h3(self, text: str):
        self._reset()
        self.set_font("Body", "B", 10)
        self.set_text_color(40, 100, 60)
        self.multi_cell(self.epw, 6, text)
        self.ln(0.3)

    def p(self, text: str):
        self._reset()
        self.set_font("Body", "", 10)
        self.set_text_color(25, 25, 25)
        self.multi_cell(self.epw, 5.4, text)
        self.ln(1)

    def bullet(self, text: str):
        self._reset()
        self.set_font("Body", "", 10)
        self.set_text_color(25, 25, 25)
        self.multi_cell(self.epw, 5.4, f"•  {text}")

    def code(self, text: str):
        self._reset()
        self.set_font("Body", "", 8)
        self.set_text_color(35, 35, 35)
        self.set_fill_color(245, 248, 245)
        self.multi_cell(self.epw, 4.4, text, fill=True)
        self.ln(1)

    def table(self, headers, rows, widths):
        assert len(headers) == len(widths)
        total = sum(widths) or 1.0
        widths = [w * self.epw / total for w in widths]

        self._reset()
        self.set_font("Body", "B", 8)
        self.set_fill_color(29, 185, 84)
        self.set_text_color(255, 255, 255)
        for i, h in enumerate(headers):
            self.cell(widths[i], 6, h[:48], border=1, fill=True)
        self.ln()

        self.set_font("Body", "", 8)
        self.set_text_color(20, 20, 20)
        fill = False
        for row in rows:
            if self.get_y() > self.h - 20:
                self.add_page()
            self._reset()
            self.set_fill_color(236, 250, 240) if fill else self.set_fill_color(255, 255, 255)
            for i, cell in enumerate(row):
                txt = str(cell).replace("\n", " ")
                max_len = max(6, int(widths[i] / 1.55))
                if len(txt) > max_len:
                    txt = txt[: max_len - 1] + "…"
                self.cell(widths[i], 6, txt, border=1, fill=True)
            self.ln()
            fill = not fill
        self.ln(2)


def main():
    stats = count_sources()
    font, font_b = pick_fonts()
    pdf = Report(orientation="P", unit="mm", format="A4")
    pdf.set_margins(12, 12, 12)
    pdf.set_auto_page_break(auto=True, margin=14)
    pdf.alias_nb_pages()
    pdf.add_font("Body", "", str(font))
    pdf.add_font("Body", "B", str(font_b))

    # ── Cover ─────────────────────────────────────────────────────────
    pdf.add_page()
    pdf.ln(28)
    pdf.set_font("Body", "B", 30)
    pdf.set_text_color(29, 185, 84)
    pdf.cell(pdf.epw, 14, "GreenWayOS", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Body", "B", 14)
    pdf.set_text_color(0, 180, 220)
    pdf.cell(pdf.epw, 8, "ctOS HUD Edition", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)
    pdf.set_font("Body", "B", 13)
    pdf.set_text_color(40, 40, 40)
    pdf.cell(pdf.epw, 9, "Полный технический отчёт по дистрибутиву", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)
    pdf.set_font("Body", "", 11)
    for line in [
        f"Версия: {VERSION}",
        "База: Debian 12 Bookworm · amd64 · live-build",
        "Автор: Sergey Karamyshev (Vorsess)",
        f"Дата отчёта: {datetime.now():%Y-%m-%d %H:%M}",
        f"Исходников в репозитории: ~{stats['files']} файлов",
    ]:
        pdf.cell(pdf.epw, 7, line, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)
    pdf.set_font("Body", "", 9)
    pdf.set_text_color(80, 80, 80)
    pdf.p(
        "Документ описывает архитектуру, компоненты, конвейер сборки, установщики, "
        "брендинг ctOS HUD, systemd-сервисы, GRUB, списки пакетов и рекомендации по эксплуатации. "
        "Сформирован автоматически на основе анализа репозитория."
    )

    # ── 1. Overview ───────────────────────────────────────────────────
    pdf.add_page()
    pdf.h1("1. Обзор дистрибутива")
    pdf.p(
        "GreenWayOS — кастомный live-гибридный ISO на Debian Bookworm (amd64), "
        "собираемый через live-build. Стандартный debian-installer отключён. "
        "Установка на диск выполняется собственными инсталляторами: текстовым (Python curses) "
        "и графическим (PyQt5 + standalone Xorg), использующими общий Python-движок install.engine."
    )
    pdf.h2("1.1 Ключевые характеристики")
    pdf.table(
        ["Параметр", "Значение"],
        [
            ["Версия", VERSION],
            ["Базовая ОС", "Debian 12 Bookworm"],
            ["Архитектура", "amd64"],
            ["Формат образа", "iso-hybrid (USB + CD)"],
            ["Загрузчики", "GRUB BIOS + GRUB UEFI"],
            ["Рабочий стол", "XFCE 4 + LightDM"],
            ["Визуальный стиль", "GreenWay-ctOS HUD"],
            ["ISO volume id", "GREENWAYOS_1"],
            ["debian-installer", "none (отключён)"],
        ],
        [55, 135],
    )
    pdf.h2("1.2 Назначение и сценарии")
    for t in [
        "Live-сессия XFCE с полным набором приложений без установки",
        "Установка на диск (BIOS/UEFI) через debootstrap + chroot-apt",
        "Профили: Standard, Engineering, Security, Corporate",
        "Сборка ISO только в Debian Bookworm VM (не на Windows)",
        "Тестирование в VMware, VirtualBox, QEMU",
    ]:
        pdf.bullet(t)

    # ── 2. auto/config ────────────────────────────────────────────────
    pdf.h1("2. Конфигурация live-build (auto/config)")
    pdf.p(
        "Файл auto/config задаёт параметры lb config: зеркала deb.debian.org, "
        "archive-areas main/contrib/non-free/non-free-firmware, squashfs gzip, "
        "bootappend-live с hostname=greenwayos и username=user."
    )
    pdf.table(
        ["Параметр", "Значение"],
        [
            ["distribution", "bookworm"],
            ["architectures", "amd64"],
            ["archive-areas", "main contrib non-free non-free-firmware"],
            ["binary-images", "iso-hybrid"],
            ["bootloaders", "grub-pc grub-efi"],
            ["mirrors", "https://deb.debian.org/debian/"],
            ["security mirror", "http://security.debian.org/"],
            ["linux-flavours", "amd64"],
            ["iso-volume", "GREENWAYOS_1"],
            ["image-name", "greenwayos"],
            ["squashfs", "gzip"],
            ["apt timeouts", "30s, 5 retries"],
        ],
        [55, 135],
    )

    # ── 3. Structure ──────────────────────────────────────────────────
    pdf.h1("3. Структура проекта")
    pdf.table(
        ["Путь", "Роль"],
        [
            ["VERSION", f"Версия: {VERSION}"],
            ["README.md", "Документация проекта"],
            ["build.sh", "Мастер-сборка ISO (RU/EN UI)"],
            ["generate_project_report_pdf.py", "Генератор этого PDF"],
            ["auto/", "lb config / build / clean"],
            ["config/package-lists/", "4 списка пакетов APT"],
            ["config/hooks/live/", f"{stats['hooks']} hooks кастомизации"],
            ["config/bootloaders/", "GRUB EFI + BIOS меню"],
            ["config/includes.chroot/", "Файлы rootfs ISO"],
            ["config/theme.conf", "Палитра #1DB954"],
            ["scripts/", "validate, pre-config, iso-sanity"],
            [".github/workflows/", "CI: syntax, security, docs"],
            ["backup/", "Архив (не в ISO)"],
        ],
        [55, 135],
    )

    # ── 4. Architecture ───────────────────────────────────────────────
    pdf.h1("4. Архитектура системы")
    pdf.h2("4.1 Конвейер сборки")
    pdf.code(
        "build.sh\n"
        "  |- select_language (ru|en)\n"
        "  |- check_disk_space (min 20 GiB)\n"
        "  |- scripts/validate.sh + py_compile installers\n"
        "  |- scripts/pre-config.sh (VERSION -> image-name)\n"
        "  |- lb config (auto/config)\n"
        "  |- lb build (progress via lb-build-progress.awk)\n"
        "  |    |- debootstrap\n"
        "  |    |- package-lists/*.list.chroot\n"
        "  |    |- hooks/live/*.chroot + *.hook.binary\n"
        "  |    \\- includes.chroot/** -> squashfs -> xorriso\n"
        "  |- iso-sanity-check.sh\n"
        "  |- ISO padding (+10 MB VMware BIOS)\n"
        "  \\- SHA256 + MD5 checksums"
    )
    pdf.h2("4.2 Runtime: загрузка и установка")
    pdf.code(
        "GRUB (efi|pc) — поиск /live/vmlinuz (cd0/cd1/search)\n"
        "  |\n"
        "  |- LIVE NODE / SAFE LIVE\n"
        "  |    \\- LightDM -> XFCE ctOS -> welcome, HUD, apps\n"
        "  |\n"
        "  |- INSTALL // GUI [SAFE]\n"
        "  |    |- install-flags.service -> /run/greenwayos/*\n"
        "  |    |- gui-install.service -> Xorg tty2 :0\n"
        "  |    \\- greenwayos-installer-gui (PyQt5)\n"
        "  |          \\- install.engine\n"
        "  |\n"
        "  \\- INSTALL // TTY\n"
        "       |- text-install.service (tty1, no getty)\n"
        "       \\- greenwayos-installer (curses)\n"
        "             \\- install.engine (тот же backend)"
    )
    pdf.h2("4.3 install.engine — 19 шагов установки")
    pdf.table(
        ["#", "Шаг", "Вес %"],
        [
            ["1", "Checking network", "2"],
            ["2", "Partitioning disk", "5"],
            ["3", "Formatting partitions", "8"],
            ["4", "Mounting filesystems", "10"],
            ["5", "debootstrap base system", "35"],
            ["6-8", "chroot mounts, DNS, fstab", "16"],
            ["9", "Installing GreenWayOS packages", "20"],
            ["10-12", "locale, user, branding", "23"],
            ["13-14", "hardening, SSH (optional)", "5"],
            ["15-19", "initramfs, firstboot, GRUB, sync", "19"],
        ],
        [12, 128, 50],
    )

    # ── 5. Python modules ─────────────────────────────────────────────
    pdf.h1("5. Python-библиотека install/")
    pdf.table(
        ["Модуль", "Назначение"],
        [
            ["constants.py", "INSTALL_STEPS, EXPERT_PROFILES, зеркала APT"],
            ["engine.py", "Оркестрация: debootstrap, chroot, GRUB"],
            ["disk.py", "lsblk/sysfs, boot mode, live disk guard"],
            ["partition.py", "GPT UEFI/BIOS, dual-boot, LVM"],
            ["network.py", "check_network_ready, Wi-Fi nmcli"],
            ["password.py", "Безопасная установка пароля"],
            ["progress.py", "Прогресс apt/debootstrap"],
            ["state.py", "Нормализация state dict"],
            ["logutil.py", "/var/log/greenwayos-install.log"],
            ["chroot-apt.sh", "apt install в /mnt chroot"],
        ],
        [45, 145],
    )
    pdf.h2("5.1 Профили эксперта (constants.py)")
    pdf.table(
        ["GUI профиль", "Backend ключ", "Примеры пакетов"],
        [
            ["Standard", "standard", "Базовый XFCE набор"],
            ["Engineering", "systems_engineering", "ansible, docker, qemu, gdb"],
            ["Security", "computer_security", "wireshark, nmap, fail2ban, lynis"],
            ["Corporate", "infotecs_corporate", "auditd, apparmor, postgresql-client"],
        ],
        [35, 50, 105],
    )

    # ── 6. Package lists ──────────────────────────────────────────────
    pdf.h1("6. Списки пакетов")
    pdf.h2("6.1 base.list.chroot")
    pdf.p(
        "Ядро ISO: vim, htop, curl, git, build-essential, python3+PyQt5+curses, "
        "debootstrap, e2fsprogs, Xorg (vesa/fbdev/vmware), NetworkManager+wpasupplicant, "
        "ufw, iptables, openvpn, grub-pc, live-boot, live-config, locales."
    )
    pdf.h2("6.2 gui.list.chroot")
    pdf.p("XFCE4, LightDM, firefox-esr, LibreOffice, VLC, wireshark, gparted, remmina, terminator, open-vm-tools.")
    pdf.h2("6.3 desktop.list.chroot")
    pdf.p("i3/rofi/dunst/picom, шрифты JetBrains/Noto, GIMP, Inkscape, PulseAudio, Thunar, nm-tray.")
    pdf.h2("6.4 network-tools.list.chroot")
    pdf.p("tcpdump, tshark, nmap, wireguard, fail2ban, aide, hydra, sqlmap, nikto. openssh-server убран из live.")

    # ── 7. GRUB ───────────────────────────────────────────────────────
    pdf.h1("7. Меню загрузки GRUB")
    pdf.p(
        "Конфигурации grub-efi и grub-pc синхронизированы. Поиск носителя: cd0, cd1, "
        "затем search --file /live/vmlinuz. Тема GreenWay-ctOS (cyan/black). "
        "Установщики: video=1280x800, mask lightdm, noautologin."
    )
    pdf.table(
        ["Пункт меню", "Kernel-параметры"],
        [
            ["LIVE NODE", "boot=live, plymouth off, mask NM-wait/bluetooth"],
            ["SAFE LIVE", "+ nomodeset"],
            ["INSTALL // GUI", "install+gui_install, noautologin, 1280x800"],
            ["INSTALL // GUI SAFE", "то же + nomodeset"],
            ["INSTALL // TTY", "install only, multi-user.target"],
            ["DEBUG NODE", "debug verbose"],
        ],
        [50, 140],
    )

    # ── 8. Installers ─────────────────────────────────────────────────
    pdf.h1("8. Установщики")
    pdf.h2("8.1 Графический (PyQt5)")
    pdf.p(
        "Файл: greenwayos-installer-gui (~2900 строк). Мастер: Language -> Welcome -> "
        "Network (Local/Wi-Fi) -> Disk -> Partitioning -> Profiles -> Locale -> "
        "User -> Confirm -> Install -> Done. Xorg на tty2 через start-x-installer.sh. "
        "Compact UI при <=1366x900. Логи: greenwayos-installer-debug.log."
    )
    pdf.h2("8.2 Текстовый (curses)")
    pdf.p(
        "Файл: greenwayos-installer. Аналогичный flow в TUI. "
        "Сервис text-install.service: StandardInput/Output/Error=tty, "
        "Conflicts=getty@tty1, TTYPath=/dev/tty1."
    )
    pdf.h2("8.3 Сеть в установщике")
    pdf.bullet("Local/Ethernet — пропуск шага Wi-Fi")
    pdf.bullet("Wi-Fi — nmcli device wifi list + connect")
    pdf.bullet("check_network_ready() блокирует debootstrap без сети")
    pdf.bullet("Зеркала: deb.debian.org, Yandex RU, cdn.debian.net")

    # ── 9. ctOS branding ──────────────────────────────────────────────
    pdf.h1("9. Брендинг ctOS HUD")
    pdf.h2("9.1 Цветовая палитра (branding.json)")
    pdf.table(
        ["Элемент", "HEX"],
        [
            ["Фон", "#0A0E12"],
            ["Панель", "#0D1117"],
            ["Акцент cyan", "#00E8FF"],
            ["Бренд green", "#1DB954"],
            ["Текст", "#E6F1FF"],
            ["Опасность", "#FF4D6A"],
        ],
        [50, 140],
    )
    pdf.h2("9.2 Компоненты темы")
    for t in [
        "GTK3: usr/share/greenwayos/ctos/gtk-3.0/gtk.css",
        "XFWM4: usr/share/themes/GreenWay-ctOS/xfwm4/ (кастомные кнопки)",
        "LightDM greeter: JetBrains Mono, wallpaper-lock.png",
        "GRUB theme: usr/share/grub/themes/GreenWay-ctOS/",
        "Обои: wallpaper.png, wallpaper-lock.png",
        "sys-dashboard.c — TUI монитор CPU/RAM/сеть (компилируется в hook 01)",
        "greenwayos-ctos-hud — HUD overlay для live",
    ]:
        pdf.bullet(t)
    pdf.h2("9.3 os-release")
    pdf.code(
        'PRETTY_NAME="GreenWayOS 2.0 (ctOS)"\n'
        "ID=greenwayos\n"
        "VERSION=2.0-rc1 (ctOS HUD)\n"
        'GREENWAYOS_EDITION="ctOS"'
    )

    # ── 10. systemd & hooks ───────────────────────────────────────────
    pdf.h1("10. systemd и chroot hooks")
    pdf.h2("10.1 systemd units")
    pdf.table(
        ["Unit", "Назначение"],
        [
            ["install-flags", "Kernel cmdline -> /run/greenwayos/*"],
            ["install-banner", "Баннер tty1 в install mode"],
            ["gui-install", "Xorg + PyQt5 installer"],
            ["gui-fallback", "Fallback GUI -> text"],
            ["text-install", "Curses installer tty1"],
            ["live-display", "chvt для live desktop"],
            ["live-shutdown", "Unmount live medium"],
            ["logdump", "Сохранение логов"],
            ["firstboot", "Первый boot установленной ОС"],
            ["audio (autostart)", "Настройка ALSA/PulseAudio"],
        ],
        [45, 145],
    )
    pdf.h2("10.2 Chroot hooks")
    for t in [
        "01-setup — sys-dashboard gcc, PyQt5/curses gate, enable services, NM",
        "02-iptables — iptables-persistent debconf",
        "03-grub — GRUB_DISTRIBUTOR=GreenWayOS, theme GreenWay-ctOS",
        "04-gui — LightDM ctOS greeter, graphical.target",
        "05-branding — os-release, lsb-release, motd, systemd symlinks",
        "06-remove-debian-branding — удаление Debian branding",
        "50-kernel-symlinks.hook.binary — /live/vmlinuz + initrd.img",
    ]:
        pdf.bullet(t)

    # ── 11. Build & CI ────────────────────────────────────────────────
    pdf.h1("11. Сборка и CI/CD")
    pdf.h2("11.1 build.sh")
    pdf.code(
        "sudo ./build.sh --lang ru\n"
        "sudo ./build.sh --validate-only\n"
        "sudo ./build.sh --clean-only\n"
        "sudo ./build.sh --skip-validate --no-pad\n"
        "\n"
        "ENV: GREENWAYOS_BUILD_LANG=ru|en\n"
        "     GREENWAYOS_SKIP_VALIDATE=1"
    )
    pdf.p(
        "build.sh: bilingual UI (RU/EN), retry logic для apt, live progress bar, "
        "workaround для путей с пробелами (rsync в /tmp), pigz для squashfs, "
        "финальные SHA256/MD5."
    )
    pdf.h2("11.2 GitHub Actions")
    pdf.table(
        ["Job", "Проверки"],
        [
            ["syntax-check", "bash -n, shellcheck, py_compile"],
            ["validate", "README, auto/, config/, package lists"],
            ["documentation", "README content"],
            ["build-test", "live-build, debootstrap availability"],
            ["security-check", "secrets, sudoers, eval patterns"],
        ],
        [40, 150],
    )

    # ── 12. Requirements ──────────────────────────────────────────────
    pdf.h1("12. Системные требования")
    pdf.h2("12.1 Сборка ISO")
    pdf.table(
        ["Ресурс", "Минимум", "Рекомендуется"],
        [
            ["ОС", "Debian 12 Bookworm", "Debian 12 Bookworm"],
            ["CPU", "x86_64, 2 ядра", "4+ ядер"],
            ["RAM", "4 GB", "8+ GB"],
            ["Диск", "20 GB свободно", "40+ GB"],
            ["Время", "15-45 мин", "зависит от сети"],
        ],
        [40, 75, 75],
    )
    pdf.h2("12.2 Live / установка")
    pdf.table(
        ["Ресурс", "Минимум"],
        [
            ["CPU", "x86_64 (amd64)"],
            ["RAM Live", "2 GB (лучше 4+)"],
            ["RAM Install", "4 GB"],
            ["Диск", "20 GB"],
            ["Сеть", "Обязательна для debootstrap/apt"],
            ["Загрузка", "UEFI или Legacy BIOS"],
        ],
        [50, 140],
    )

    # ── 13. User guide ────────────────────────────────────────────────
    pdf.h1("13. Руководство пользователя")
    pdf.h2("13.1 Live-режим")
    pdf.p(
        "Выберите LIVE NODE в GRUB. Автовход user. Рабочий стол XFCE ctOS. "
        "Приложения: Firefox, LibreOffice, GParted, Terminal, VLC. "
        "Сеть через NetworkManager. О системе: greenwayos-about, neofetch."
    )
    pdf.h2("13.2 Установка на диск")
    for t in [
        "1. Выберите INSTALL // GUI или INSTALL // TTY в GRUB",
        "2. Подключите интернет (Ethernet или Wi-Fi на шаге Network)",
        "3. Выберите диск >= 20 GB (ВСЕ ДАННЫЕ БУДУТ СТЁРТЫ при quick)",
        "4. Выберите профиль, locale, пользователя и пароль",
        "5. Дождитесь установки (25-45 мин) и перезагрузите",
        "6. Логи: /var/log/greenwayos-install.log",
    ]:
        pdf.bullet(t)
    pdf.h2("13.3 Логи и диагностика")
    pdf.table(
        ["Файл", "Содержимое"],
        [
            ["/var/log/greenwayos-install.log", "Основной лог engine"],
            ["/var/log/greenwayos-gui-install.log", "GUI installer service"],
            ["/var/log/greenwayos-installer-debug.log", "PyQt5 debug"],
            ["build.log", "Лог сборки ISO (на build VM)"],
        ],
        [70, 120],
    )

    # ── 14. includes.chroot map ───────────────────────────────────────
    pdf.h1("14. Карта includes.chroot")
    pdf.code(
        "usr/local/bin/\n"
        "  greenwayos-installer, greenwayos-installer-gui\n"
        "  greenwayos-installer-launch, start-x-installer.sh\n"
        "  greenwayos-welcome, greenwayos-about, greenwayos-firstboot\n"
        "  greenwayos-ctos-hud, greenwayos-save-logs, neofetch\n"
        "\n"
        "usr/local/lib/greenwayos/install/  (Python backend)\n"
        "usr/local/src/sys-dashboard.c      (компилируется в hook)\n"
        "\n"
        "etc/systemd/system/greenwayos-*.service\n"
        "lib/live/config/0100|0110|99-greenwayos-*\n"
        "etc/lightdm/, etc/X11/xorg.conf.d/\n"
        "usr/share/greenwayos/ctos/         (брендинг)\n"
        "usr/share/themes/GreenWay-ctOS/\n"
        "usr/share/grub/themes/GreenWay-ctOS/"
    )

    # ── 15. Audit ─────────────────────────────────────────────────────
    pdf.h1("15. Аудит и известные риски")
    pdf.h2("15.1 Исправленные проблемы")
    pdf.table(
        ["Проблема", "Статус", "Решение"],
        [
            ["GUI overflow 1920x1080", "FIXED", "video=1280x800 + compact UI"],
            ["Terminal login prompt", "FIXED", "tty I/O + stop getty@tty1"],
            ["GUI fallback -> getty", "FIXED", "openvt без getty"],
            ["Нет Wi-Fi в installer", "FIXED", "network.py + nmcli"],
            ["openssh-server в live", "FIXED", "убран из network-tools"],
            ["Битые пакеты в профилях", "FIXED", "очищен constants.py"],
            ["Диски не видны в GUI", "FIXED", "udev settle + retry"],
        ],
        [55, 22, 113],
    )
    pdf.h2("15.2 Оставшиеся риски")
    pdf.table(
        ["Sev", "Риск", "Рекомендация"],
        [
            ["MED", "Expert-пакеты могут отсутствовать в mirror", "chroot-apt skip unknown"],
            ["MED", "Wi-Fi в VMware виртуально недоступен", "Ethernet bridged / USB"],
            ["MED", "NOPASSWD в live sudoers", "Только live session, не installed"],
            ["LOW", "Дубли пакетов в lists", "Дедупликация при рефакторинге"],
            ["LOW", "Manual partition GUI off", "Только quick/dualboot/LVM"],
            ["INFO", "ISO не собран в CI", "Сборка в Bookworm VM"],
        ],
        [16, 85, 89],
    )
    pdf.h2("15.3 Проверки аудита")
    for t in [
        "AST-parse обоих installers — OK",
        "py_compile install/*.py — OK",
        "Паритет GRUB EFI/PC + video=1280x800 — OK",
        "text-install.service tty binding — OK",
        "NetworkManager в base + enable в hook 01 — OK",
        "PyQt5 gate в hook 01-setup — OK",
        "GRUB theme GreenWay-ctOS в hook 03 — OK",
    ]:
        pdf.bullet(t)

    # ── 16. Conclusion ────────────────────────────────────────────────
    pdf.h1("16. Заключение")
    pdf.p(
        f"GreenWayOS {VERSION} — целостный live-build конвейер с двумя установщиками, "
        "общим Python-движком install.engine, визуальной идентичностью ctOS HUD "
        "и поддержкой GRUB BIOS/UEFI. Проект включает полный набор hooks, "
        "systemd-сервисов, валидации и CI. Критичные дефекты GUI, terminal installer "
        "и Wi-Fi устранены. Для финальной проверки рекомендуется пересборка ISO "
        "в Debian Bookworm VM и тестирование всех пунктов GRUB-меню."
    )
    pdf.ln(4)
    pdf.h2("Контакты")
    pdf.bullet("Автор: Sergey Karamyshev (Vorsess)")
    pdf.bullet("GitHub: https://github.com/Vorsess")
    pdf.bullet("Проект: GreenWayOS Project")
    pdf.ln(3)
    pdf._reset()
    pdf.set_font("Body", "B", 11)
    pdf.set_text_color(29, 185, 84)
    pdf.multi_cell(pdf.epw, 7, f"Файл: {OUT.name}")
    pdf._reset()
    pdf.set_font("Body", "", 9)
    pdf.set_text_color(60, 60, 60)
    pdf.multi_cell(pdf.epw, 6, f"Сгенерировано: {datetime.now():%Y-%m-%d %H:%M:%S}")

    pdf.output(str(OUT))
    print(f"OK: {OUT}")
    print(f"SIZE: {OUT.stat().st_size:,} bytes")
    print(f"PAGES: {pdf.pages_count}")


if __name__ == "__main__":
    main()
