<p align="center">
  <strong>GreenWayOS 2.0-rc1</strong><br>
  <em>Debian Bookworm live ISO · ctOS HUD · dual installers · advanced modules</em>
</p>

<p align="center">
  <img src="config/includes.chroot/usr/share/icons/hicolor/64x64/apps/greenwayos-logo.svg" alt="GreenWayOS" width="72">
</p>

---

**GreenWayOS** — кастомный live-гибридный дистрибутив на базе **Debian 12 (Bookworm) amd64**, собираемый через **live-build**. Вместо стандартного Debian Installer используются собственные установщики: **текстовый (curses)** и **графический (PyQt5 + standalone Xorg)** с общим Python-движком `install.engine`.

| | |
|---|---|
| **Версия** | `2.0-rc1` |
| **База** | Debian Bookworm · amd64 |
| **Сборка** | live-build · iso-hybrid · GRUB BIOS + UEFI |
| **Рабочий стол** | XFCE 4 + LightDM · тема **GreenWay-ctOS** |
| **Автор** | Sergey Karamyshev ([Vorsess](https://github.com/Vorsess)) |
| **ISO volume id** | `GREENWAYOS_1` |
| **Модули** | Theme Engine · Recovery · Security · Performance · Package Manager |

> Полный технический отчёт: [`GreenWayOS_2.0_Project_Report.pdf`](GreenWayOS_2.0_Project_Report.pdf)

---

## Содержание

- [Обзор](#обзор)
- [Ключевые возможности](#ключевые-возможности)
- [Архитектура](#архитектура)
- [Меню загрузки GRUB](#меню-загрузки-grub)
- [Установщики](#установщики)
- [Продвинутые модули](#продвинутые-модули)
- [Live-сессия](#live-сессия)
- [Быстрый старт (сборка ISO)](#быстрый-старт-сборка-iso)
- [Структура репозитория](#структура-репозитория)
- [Конвейер сборки](#конвейер-сборки)
- [Списки пакетов](#списки-пакетов)
- [Скрипты и валидация](#скрипты-и-валидация)
- [CI/CD](#cicd)
- [Системные требования](#системные-требования)
- [Устранение неполадок](#устранение-неполадок)
- [Лицензия и брендинг](#лицензия-и-брендинг)

---

## Обзор

GreenWayOS — это полноценная live-среда с рабочим столом XFCE и инструментами для установки системы на диск. Проект ориентирован на:

- **Live-режим** — загрузка с USB/CD без установки, полноценный рабочий стол
- **Установку на диск** — BIOS и UEFI через `debootstrap` + `chroot-apt`
- **Профили эксперта** — дополнительные пакеты (инженерия, безопасность, корпоративный стек)
- **Визуальный стиль ctOS HUD** — тёмная тема в духе Watch Dogs, кастомные обои, GRUB-тема, GTK/XFWM4

Стандартный **debian-installer отключён** (`--debian-installer none`). Вся установка выполняется собственным кодом в `usr/local/lib/greenwayos/install/`.

---

## Ключевые возможности

### Два установщика — один движок

| Установщик | Интерфейс | Запуск |
|---|---|---|
| **Graphical Installer** | PyQt5, standalone Xorg на tty2 | GRUB → `greenwayos.gui_install=1` |
| **Terminal Installer** | Python curses на tty1 | GRUB → `greenwayos.install=1` |

Оба используют общий модуль `install.engine` — одинаковая логика разметки, debootstrap, chroot-apt и GRUB.

### Профили установки

| Профиль | Описание |
|---|---|
| **Standard** | Базовый набор пакетов XFCE + офис + браузер |
| **Engineering** | Ansible, Docker, QEMU, отладка, мониторинг |
| **Security** | Wireshark, nmap, fail2ban, Lynis, forensics |
| **Corporate** | SSH, auditd, AppArmor, PostgreSQL client, VPN |

### ctOS HUD — визуальная идентичность

- Тема **GreenWay-ctOS** (GTK3, XFWM4, LightDM greeter)
- Палитра: фон `#0A0E12`, акцент `#00E8FF`, бренд `#1DB954`
- Кастомные обои, иконки, GRUB-тема с фоном ctOS
- HUD-утилиты: `greenwayos-ctos-hud`, `sys-dashboard` (C, компилируется в hook)
- Шрифты: JetBrains Mono, DejaVu Sans Mono

### Сеть в установщике

- Ethernet / «локальная сеть» — без дополнительной настройки
- **Wi-Fi** — сканирование и подключение через `nmcli` (NetworkManager)
- Проверка `check_network_ready()` перед debootstrap

### Разметка диска

- **Quick** — полное стирание диска, GPT, ESP + root (UEFI) или BIOS boot + root
- **Dual-boot** — сохранение существующих разделов, использование свободного места
- **LVM** — опциональная LVM-разметка
- Защита от установки на live-носитель (`get_live_boot_disk()`)

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                        GRUB (BIOS + UEFI)                        │
├──────────────┬────────────────────┬─────────────────────────────┤
│  Live Node   │  Install GUI       │  Install TTY                │
│  XFCE+LightDM│  Xorg :0 + PyQt5   │  curses на tty1             │
└──────┬───────┴─────────┬──────────┴──────────────┬──────────────┘
       │                 │                         │
       ▼                 ▼                         ▼
┌──────────────┐  ┌──────────────────────────────────────────────┐
│ Live desktop │  │         install.engine (Python)               │
│ welcome, HUD │  │  disk · partition · network · password        │
└──────────────┘  │  debootstrap → chroot-apt → GRUB → firstboot  │
                  └──────────────────────────────────────────────┘
```

### Python-модули установщика

| Модуль | Назначение |
|---|---|
| `engine.py` | Оркестрация полной установки (19 шагов) |
| `partition.py` | GPT-разметка, UEFI/BIOS, dual-boot, LVM |
| `disk.py` | Обнаружение дисков (lsblk/sysfs), boot mode |
| `network.py` | Проверка сети, Wi-Fi через nmcli |
| `password.py` | Безопасная установка пароля пользователя |
| `progress.py` | Прогресс debootstrap/apt |
| `constants.py` | Шаги, профили, зеркала APT |
| `chroot-apt.sh` | Установка пакетов в chroot `/mnt` |

### systemd-сервисы (live / install)

| Unit | Роль |
|---|---|
| `greenwayos-install-flags.service` | Парсинг kernel cmdline → `/run/greenwayos/*` |
| `greenwayos-install-banner.service` | Баннер на tty1 в режиме установки |
| `greenwayos-gui-install.service` | Запуск X + GUI installer |
| `greenwayos-gui-fallback.service` | Fallback GUI → text installer |
| `greenwayos-text-install.service` | Curses installer на tty1 |
| `greenwayos-live-display.service` | Переключение VT для live desktop |
| `greenwayos-live-shutdown.service` | Очистка live medium при shutdown |
| `greenwayos-logdump.service` | Сохранение логов установки |
| `greenwayos-firstboot.service` | Первый запуск установленной ОС |

---

## Меню загрузки GRUB

Пункты меню (EFI и BIOS идентичны по смыслу):

| Пункт GRUB | Назначение |
|---|---|
| **LIVE NODE** | Live XFCE, autologin user |
| **SAFE LIVE** | Live + `nomodeset` (без KMS) |
| **INSTALL // GUI** | Графический установщик, `video=1280x800` |
| **INSTALL // GUI SAFE** | GUI + `nomodeset` |
| **INSTALL // TTY** | Текстовый установщик, `multi-user.target` |
| **DEBUG NODE** | Verbose boot для отладки |

**Kernel-параметры установщика:**

```
greenwayos.install=1          # режим установки
greenwayos.gui_install=1      # графический установщик
noautologin                   # без autologin в install mode
systemd.mask=lightdm.service  # LightDM не мешает Xorg installer
video=1280x800                # фиксированное разрешение GUI
```

Конфигурация: `config/bootloaders/grub-efi/grub.cfg`, `config/bootloaders/grub-pc/grub.cfg`.

---

## Установщики

### Графический (PyQt5)

**Файл:** `config/includes.chroot/usr/local/bin/greenwayos-installer-gui`

Мастер установки:

1. Выбор языка (RU / EN)
2. Welcome + предупреждение о стирании данных
3. Сеть (Local / Wi-Fi)
4. Выбор диска (udev settle + retry)
5. Метод разметки
6. Профиль (Standard / Engineering / Security / Corporate)
7. Локаль, часовой пояс, hostname
8. Пользователь и пароль
9. Подтверждение → установка → Done

Xorg запускается на **tty2** через `greenwayos-start-x-installer.sh`. Compact UI при разрешении ≤ 1366×900.

### Текстовый (curses)

**Файл:** `config/includes.chroot/usr/local/bin/greenwayos-installer`

Аналогичный flow в TUI. Сервис `text-install.service` привязан к tty1, конфликтует с `getty@tty1`.

### Логи установки

| Файл | Содержимое |
|---|---|
| `/var/log/greenwayos-install.log` | Основной лог engine |
| `/var/log/greenwayos-gui-install.log` | GUI installer |
| `/var/log/greenwayos-installer-debug.log` | Debug PyQt5 |

Сохранение на USB: `greenwayos-save-logs`.

---

## Продвинутые модули

GreenWayOS включает набор продвинутых системных модулей для управления темой, восстановлением, безопасностью, производительностью и пакетами.

### 🎨 Dynamic Theme Engine (`greenway-theme-engine`)

Полноценная система управления темами в стиле Watch Dogs ctOS HUD:

- **Автоматическое переключение тем** по времени суток (утро/день/вечер/ночь)
- **Сканирование и установка тем** из `/usr/local/share/greenway/themes` и `~/.local/share/greenway/themes`
- **Экспорт/импорт пользовательских тем** в формате JSON
- **Применение всех аспектов темы**: GTK3, XFWM4, иконки, курсоры, шрифты, обои, звуки
- **Конфигурация**: `/etc/greenway/current_theme.json`

**Использование:**
```bash
greenway-theme-engine list           # Список доступных тем
greenway-theme-engine apply <name>   # Применить тему
greenway-theme-engine export <path>  # Экспорт текущей темы
greenway-theme-engine import <path>  # Импорт темы
greenway-theme-engine auto-toggle    # Авто-переключение по времени
```

### 🔄 System Recovery & Backup (`greenway-recovery`)

Мощная система резервного копирования и восстановления:

- **Типы снимков**: full (вся система), system (только система), home (домашние каталоги), config (конфигурации)
- **Восстановление из снимков** с проверкой целостности SHA256
- **Factory reset** — сброс к заводским настройкам
- **Emergency mode** — аварийный режим с минимальными зависимостями
- **Автоматическое логирование** всех операций

**Использование:**
```bash
greenway-recovery create full        # Создать полный снимок
greenway-recovery list               # Показать доступные снимки
greenway-recovery restore <id>       # Восстановить из снимка
greenway-recovery factory-reset      # Сброс к заводским настройкам
greenway-recovery emergency          # Запуск в аварийном режиме
```

### 🛡️ Security Module (`greenway-security`)

Комплексный модуль безопасности с несколькими режимами:

- **Режим паники (Panic Mode)**: экстренное закрытие приложений, отключение сети, блокировка USB, очистка временных данных
- **Анонимный режим**: рандомизация MAC-адреса, приватные DNS, отключение телеметрии, защита от fingerprinting
- **Уровни безопасности**: normal → elevated → high → critical → panic
- **Мониторинг статуса** в реальном времени

**Использование:**
```bash
greenway-security status             # Текущий статус безопасности
greenway-security set <level>        # Установить уровень (normal/elevated/high/critical/panic)
greenway-security panic              # Активировать режим паники
greenway-security anonymous enable   # Включить анонимный режим
greenway-security audit              # Аудит безопасности системы
```

### ⚡ Performance Manager (`greenway-performance`)

Управление производительностью системы и драйверами:

- **Профили производительности**: power_save, balanced, performance, gaming, low_latency
- **Авто-определение оборудования**: CPU, GPU, диски, сеть
- **Установка драйверов**: NVIDIA, AMD, Intel, Wi-Fi адаптеры
- **HUD мониторинг** в стиле Watch Dogs: CPU/GPU/RAM/TEMP/FAN в реальном времени
- **Оптимизация ядра**: настройки scheduler, IRQ affinity, vm.swappiness

**Использование:**
```bash
greenway-performance profile         # Текущий профиль
greenway-performance set <profile>   # Установить профиль
greenway-performance drivers install # Авто-установка драйверов
greenway-performance hud start       # Запустить HUD мониторинг
greenway-performance optimize        # Автоматическая оптимизация
```

### 📦 Package Manager (`greenway-pkg`)

Графический и консольный менеджер пакетов с расширенными возможностями:

- **Магазин приложений (store)**: категоризированный список популярных пакетов
- **Поиск и установка** через APT с красивым выводом
- **Изолированные среды (sandbox)**: тестирование пакетов без влияния на основную систему
- **Управление репозиториями**: добавление пользовательских источников
- **Рекомендации**: умные рекомендации на основе установленных пакетов

**Использование:**
```bash
greenway-pkg store                   # Графический магазин приложений
greenway-pkg search <query>          # Поиск пакетов
greenway-pkg install <package>       # Установка пакета
greenway-pkg remove <package>        # Удаление пакета
greenway-pkg sandbox test <pkg>      # Тест в изолированной среде
greenway-pkg repo add <url>          # Добавить репозиторий
```

### Расположение файлов модулей

```
/usr/local/bin/
├── greenway-theme-engine      # Тема движок
├── greenway-recovery          # Восстановление
├── greenway-security          # Безопасность
├── greenway-performance       # Производительность
└── greenway-pkg               # Менеджер пакетов

/usr/local/share/greenway/
├── MANUAL.md                  # Полная документация
└── themes/
    └── ctos-hud-default/
        ├── theme.json         # Конфигурация темы
        ├── gtk-3.0/           # GTK стили
        ├── xfwm4/             # XFWM4 стили
        ├── icons/             # Иконки
        ├── wallpapers/        # Обои
        └── sounds/            # Звуковая схема

/etc/greenway/
├── current_theme.json         # Активная тема
├── performance/               # Настройки производительности
├── security/                  # Настройки безопасности
└── packages/                  # Настройки пакетов
```

---

## Live-сессия

После выбора **LIVE NODE**:

- Автовход пользователя `user` (пароль не требуется в live)
- Рабочий стол XFCE с темой ctOS
- Приложения: Firefox ESR, LibreOffice, GParted, VLC, Wireshark, Remmina, Terminator
- Сеть: NetworkManager (Wi-Fi + Ethernet)
- Приветствие: `greenwayos-welcome` (autostart)
- О системе: `greenwayos-about`, `neofetch`

---

## Быстрый старт (сборка ISO)

> **Важно:** сборка выполняется **только внутри Debian Bookworm** (VM или bare metal). На Windows напрямую собрать нельзя — используйте VirtualBox, VMware или QEMU.

### 1. Подготовка VM

```bash
# Debian 12 Bookworm, amd64
# Рекомендуется: 4+ CPU, 8+ GB RAM, 40+ GB диск
sudo apt-get update
sudo apt-get install -y live-build debootstrap squashfs-tools xorriso \
  isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dos2unix pigz gcc
```

### 2. Клонирование и сборка

```bash
git clone https://github.com/Vorsess/GreenWayOS-Distribution.git
cd "GreenWayOS Distribution"   # путь без пробелов предпочтителен (live-build)

chmod +x build.sh auto/config auto/build auto/clean
sudo ./build.sh --lang ru
```

### 3. Опции build.sh

| Флаг | Описание |
|---|---|
| `--lang ru\|en` | Язык интерфейса сборки |
| `--validate-only` | Только проверки, без ISO |
| `--clean-only` | `lb clean --purge` + удаление артефактов |
| `--skip-validate` | Пропустить `scripts/validate.sh` |
| `--no-pad` | Не добавлять 10 MB padding (VMware workaround) |
| `--min-free-gb N` | Минимум свободного места (по умолчанию 20) |

**Переменные окружения:** `GREENWAYOS_BUILD_LANG`, `GREENWAYOS_SKIP_VALIDATE=1`

### 4. Результат

```
greenwayos-<version>-amd64.hybrid.iso
greenwayos-<version>-amd64.hybrid.iso.sha256
greenwayos-<version>-amd64.hybrid.iso.md5
build.log
```

### 5. Тестирование

```bash
# QEMU
qemu-system-x86_64 -m 4096 -smp 2 -cdrom greenwayos-*.hybrid.iso -boot d

# VMware / VirtualBox — записать ISO на USB или подключить как CD
```

### 6. Генерация PDF-отчёта (Windows / Linux)

```bash
pip install fpdf2
python generate_project_report_pdf.py
# → GreenWayOS_2.0_Project_Report.pdf
```

---

## Структура репозитория

```
GreenWayOS Distribution/
├── VERSION                    # Версия дистрибутива (2.0-rc1)
├── README.md                  # Этот файл
├── build.sh                   # Мастер-скрипт сборки ISO
├── generate_project_report_pdf.py
├── GreenWayOS_2.0_Project_Report.pdf
│
├── auto/                      # live-build обёртки
│   ├── config                 # lb config (Bookworm, amd64, hybrid ISO)
│   ├── build
│   └── clean
│
├── config/
│   ├── package-lists/         # Списки пакетов APT
│   │   ├── base.list.chroot   # Ядро ISO: Python, Xorg, NM, debootstrap
│   │   ├── gui.list.chroot    # XFCE, LightDM, офис, мультимедиа
│   │   ├── desktop.list.chroot
│   │   └── network-tools.list.chroot
│   ├── hooks/live/            # Chroot/binary hooks
│   │   ├── 01-setup.chroot    # sys-dashboard, проверка installers
│   │   ├── 02-iptables.chroot
│   │   ├── 03-grub.chroot     # GRUB theme GreenWay-ctOS
│   │   ├── 04-gui.chroot      # LightDM, graphical.target
│   │   ├── 05-branding.chroot # os-release, motd
│   │   ├── 06-remove-debian-branding.chroot
│   │   └── 50-kernel-symlinks.hook.binary
│   ├── bootloaders/           # GRUB EFI + BIOS меню
│   ├── includes.chroot/       # Файлы, копируемые в rootfs ISO
│   │   ├── usr/local/bin/     # greenwayos-* скрипты
│   │   ├── usr/local/lib/greenwayos/install/  # Python backend
│   │   ├── etc/systemd/system/  # greenwayos-*.service
│   │   ├── usr/share/greenwayos/ctos/  # Брендинг, обои, тема
│   │   └── lib/live/config/   # live-config hooks
│   └── theme.conf             # Палитра #1DB954
│
├── scripts/
│   ├── validate.sh            # Pre-build проверки
│   ├── pre-config.sh          # Версия в image-name
│   ├── validate-grub.sh
│   ├── iso-sanity-check.sh
│   └── lb-build-progress.awk  # Live progress при lb build
│
├── .github/workflows/build.yml  # CI: syntax, validate, security
└── backup/                    # Архив (не входит в ISO)
```

---

## Конвейер сборки

```
build.sh
  ├─ scripts/validate.sh          # структура, синтаксис, пакеты, security
  ├─ py_compile installers         # greenwayos-installer + GUI
  ├─ scripts/pre-config.sh         # VERSION → image-name
  ├─ lb config  (auto/config)      # Bookworm amd64 iso-hybrid
  └─ lb build
       ├─ debootstrap               # базовый rootfs
       ├─ package-lists/*.chroot   # APT пакеты
       ├─ hooks/live/*.chroot      # кастомизация
       ├─ includes.chroot/**       # скрипты, темы, сервисы
       ├─ squashfs                 # сжатый root
       └─ xorriso                  # hybrid ISO
  └─ iso-sanity-check + padding + checksums
```

**Параметры `auto/config`:**

| Параметр | Значение |
|---|---|
| distribution | bookworm |
| architectures | amd64 |
| archive-areas | main contrib non-free non-free-firmware |
| binary-images | iso-hybrid |
| bootloaders | grub-pc grub-efi |
| debian-installer | none |
| mirrors | deb.debian.org |
| iso-volume | GREENWAYOS_1 |
| squashfs | gzip (pigz при наличии) |

---

## Списки пакетов

| Файл | Назначение |
|---|---|
| `base.list.chroot` | Утилиты, Python3+PyQt5, debootstrap, Xorg, NetworkManager, GRUB, live-boot |
| `gui.list.chroot` | XFCE4, LightDM, Firefox, LibreOffice, VLC, GParted, Wireshark |
| `desktop.list.chroot` | i3/rofi/picom, шрифты, GIMP, PulseAudio, Thunar |
| `network-tools.list.chroot` | nmap, tcpdump, VPN, security toolkit, мониторинг |

`python3-pyqt5` находится в **base** — GUI installer доступен даже без desktop profile.

---

## Скрипты и валидация

```bash
# Полная pre-build проверка
bash scripts/validate.sh

# Только валидация через build.sh
sudo ./build.sh --validate-only

# Проверка GRUB
bash scripts/validate-grub.sh

# Sanity check готового ISO
bash scripts/iso-sanity-check.sh greenwayos-*.hybrid.iso
```

`validate.sh` проверяет: структуру проекта, bash/python синтаксис, права hooks, наличие пакетов в APT, NOPASSWD/sudoers, дисковое пространство, согласованность GRUB.

---

## CI/CD

GitHub Actions (`.github/workflows/build.yml`):

| Job | Проверки |
|---|---|
| syntax-check | `bash -n`, ShellCheck, `py_compile` installers |
| validate | README, auto/, config/, package lists |
| documentation | README содержит GreenWayOS |
| build-test | live-build, debootstrap availability |
| security-check | hardcoded secrets, sudoers, dangerous patterns |

Полная сборка ISO в CI **не выполняется** (требует Debian VM с 20+ GB).

---

## Системные требования

### Для сборки ISO

| Ресурс | Минимум | Рекомендуется |
|---|---|---|
| ОС | Debian 12 Bookworm | Debian 12 Bookworm |
| CPU | x86_64, 2 ядра | 4+ ядер |
| RAM | 4 GB | 8+ GB |
| Диск | 20 GB свободно | 40+ GB |
| Время | 15–45 мин | зависит от сети и CPU |

### Для live / установки

| Ресурс | Минимум |
|---|---|
| CPU | x86_64 (amd64) |
| RAM | 2 GB (live), 4 GB (установка) |
| Диск | 20 GB для установки |
| Сеть | Нужна для debootstrap/apt |
| Загрузка | UEFI или Legacy BIOS |

---

## Устранение неполадок

### `lb build` падает на пути с пробелами

`build.sh` автоматически копирует проект в `/tmp/greenwayos-build-*` без пробелов.

### GUI installer не запускается

- Проверьте `video=1280x800` в GRUB
- Логи: `/var/log/greenwayos-gui-install.log`
- Попробуйте **INSTALL // GUI SAFE** (nomodeset)
- Fallback: `greenwayos-gui-fallback.service` → text installer

### Wi-Fi в VMware

Виртуальный Wi-Fi часто недоступен. Используйте bridged Ethernet или USB Wi-Fi адаптер.

### Нет сети при установке

Установка требует интернет для `debootstrap` и `apt`. Подключите Ethernet или настройте Wi-Fi на шаге Network.

### `validate.sh` — package not found

```bash
sudo apt-get update
sudo ./build.sh --validate-only
```

### Очистка после неудачной сборки

```bash
sudo ./build.sh --clean-only
```

---

## Лицензия и брендинг

- **Проект:** GreenWayOS Project
- **Автор:** Sergey Karamyshev (Vorsess)
- **GitHub:** https://github.com/Vorsess
- **ISO preparer:** Sergey Karamyshev (Vorsess)
- **ISO publisher:** GreenWayOS Project

Компоненты Debian и сторонние пакеты распространяются на условиях их собственных лицензий. Брендинг GreenWayOS / ctOS — собственность проекта GreenWayOS.

---

<p align="center">
  <sub>GreenWayOS 2.0-rc1 · Debian Bookworm · Built with live-build</sub>
</p>
