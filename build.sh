#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  GreenWayOS — master build script v2.0
#  Author: Sergey Karamyshev (Vorsess)
#  GitHub: https://github.com/Vorsess
#  Run this INSIDE a Debian Bookworm guest VM.
#  Usage:
#    chmod +x build.sh
#    sudo ./build.sh
# ══════════════════════════════════════════════════════════════════════

set -Eeuo pipefail

# ── Load theme configuration ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/config/theme.conf" ]; then
    source "$SCRIPT_DIR/config/theme.conf" || true
fi

# ── ANSI colours (with theme fallback) ──────────────────────────────
# Primary brand colors using theme if available, otherwise default
RED='\033[0;31m'
GREEN="${THEME_PRIMARY_DIM:-\033[0;32m}"
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
BOLD="${THEME_BOLD:-\033[1m}"
DIM="${THEME_DIM:-\033[2m}"
ITALIC="${THEME_ITALIC:-\033[3m}"
NC="${THEME_RESET:-\033[0m}"
BG_GREEN='\033[42m'
BG_RED='\033[41m'
BG_DARK='\033[48;5;233m'

# Derived theme colors
PRIMARY_COLOR="${THEME_PRIMARY_HEX:-#1DB954}"
SUCCESS_COLOR="${THEME_COLOR_SUCCESS}"
ERROR_COLOR="${THEME_COLOR_ERROR}"
WARNING_COLOR="${THEME_COLOR_WARNING}"

BUILD_LOG="build.log"
SCRIPT_START_TS="$(date +%s)"
LANG_CHOICE=""
GW_VERSION="2.0"
SKIP_VALIDATE=false
SKIP_PAD=false
VALIDATE_ONLY=false
CLEAN_ONLY=false
MIN_FREE_GB=20

# ── CLI (parse before interactive prompts) ───────────────────────────
usage() {
    cat <<'EOF'
GreenWayOS build.sh — Debian live-build ISO

Usage:
  sudo ./build.sh [options]

Options:
  -h, --help              Show this help
  -l, --lang LANG         Build UI language: ru | en (skip prompt)
  --validate-only         Run pre-checks and exit (no ISO build)
  --clean-only            lb clean --purge and remove local ISO artifacts
  --skip-validate         Skip scripts/validate.sh and installer preflight
  --no-pad                Do not append 10 MB padding to ISO (VMware workaround)
  --min-free-gb N         Require N GiB free on build filesystem (default: 20)

Environment:
  GREENWAYOS_BUILD_LANG=ru|en   Same as --lang
  GREENWAYOS_SKIP_VALIDATE=1    Same as --skip-validate

Examples:
  sudo ./build.sh --lang ru
  sudo ./build.sh --validate-only
  GREENWAYOS_BUILD_LANG=en sudo ./build.sh
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -l|--lang)
                LANG_CHOICE="${2:-}"
                shift 2
                ;;
            --lang=*)
                LANG_CHOICE="${1#*=}"
                shift
                ;;
            --validate-only) VALIDATE_ONLY=true; shift ;;
            --clean-only) CLEAN_ONLY=true; shift ;;
            --skip-validate) SKIP_VALIDATE=true; shift ;;
            --no-pad) SKIP_PAD=true; shift ;;
            --min-free-gb)
                MIN_FREE_GB="${2:-20}"
                shift 2
                ;;
            *)
                err "Unknown option: $1 (try --help)"
                ;;
        esac
    done
    if [[ -z "${LANG_CHOICE}" && -n "${GREENWAYOS_BUILD_LANG:-}" ]]; then
        LANG_CHOICE="${GREENWAYOS_BUILD_LANG}"
    fi
    if [[ "${GREENWAYOS_SKIP_VALIDATE:-}" == "1" ]]; then
        SKIP_VALIDATE=true
    fi
}

# ── Core output helpers ─────────────────────────────────────────────
print_line() { printf "%b\n" "$*"; }
timestamp()  { date '+%H:%M:%S'; }
log()        { printf "[%s] %s\n" "$(timestamp)" "$*" >> "${BUILD_LOG}"; }

# ── Retry logic for transient failures ──────────────────────────────
# Usage: run_with_retry <max_attempts> <display_name> <command...>
run_with_retry() {
    local max_attempts="$1"
    shift
    local display_name="$1"
    shift
    local cmd=("$@")
    local attempt=1
    local backoff=2
    
    while (( attempt <= max_attempts )); do
        info "[Attempt $attempt/$max_attempts] $display_name..."
        if "${cmd[@]}"; then
            step_ok "succeeded"
            return 0
        fi
        
        if (( attempt < max_attempts )); then
            warn "$display_name failed, retrying in ${backoff}s..."
            sleep "$backoff"
            backoff=$((backoff * 2))
        else
            warn "$display_name failed after $max_attempts attempts"
            return 1
        fi
        
        ((attempt++))
    done
    
    return 1
}

# ── Elapsed time formatter ──────────────────────────────────────────
fmt_duration() {
    local secs="$1"
    if (( secs >= 3600 )); then
        printf "%dh %02dm %02ds" $((secs/3600)) $(((secs%3600)/60)) $((secs%60))
    elif (( secs >= 60 )); then
        printf "%dm %02ds" $((secs/60)) $((secs%60))
    else
        printf "%ds" "${secs}"
    fi
}

# ══════════════════════════════════════════════════════════════════════
#  LOCALISATION — Russian / English
# ══════════════════════════════════════════════════════════════════════
declare -A L

load_lang_en() {
    L[banner_title]="GreenWayOS Distribution Build"
    L[banner_author]="Author: Sergey Karamyshev (Vorsess)"
    L[banner_github]="GitHub: github.com/Vorsess"
    L[banner_ver]="Build Script v2.0"
    L[lang_prompt]="Select build language"
    L[lang_ru]="Русский"
    L[lang_en]="English"
    L[section_env]="Environment"
    L[section_prepare]="Prepare Build Environment"
    L[section_settings]="Build Settings"
    L[section_build]="ISO Build"
    L[section_finalize]="Finalize Output"
    L[work_dir]="Working directory"
    L[cpu_cores]="CPU cores"
    L[ram_total]="Total RAM"
    L[log_file]="Log file"
    L[run_as_root]="Run as root (sudo ./build.sh)"
    L[lb_not_found]="live-build not found. Installing dependencies..."
    L[lb_found]="live-build is already installed."
    L[step_apt_update]="Updating package lists"
    L[step_install_deps]="Installing build dependencies"
    L[step_purge]="Purging old build artifacts"
    L[step_dos2unix]="Sanitizing line endings (CRLF → LF)"
    L[step_chmod_auto]="Setting auto scripts executable"
    L[step_chmod_hooks]="Setting chroot hooks executable"
    L[step_pre_config]="Updating build configuration with version"
    L[step_lb_config]="Running lb config"
    L[deb_build_opts]="DEB_BUILD_OPTIONS"
    L[makeflags]="MAKEFLAGS"
    L[squashfs_opts]="SquashFS compression"
    L[pigz_missing]="pigz not found — using default gzip"
    L[build_start]="Building ISO image... this may take 10-30+ minutes."
    L[build_failed]="lb build failed. Check build.log for details."
    L[build_ok]="lb build completed successfully!"
    L[no_iso]="No .hybrid.iso output found. Check build.log."
    L[no_iso_newest]="Unable to determine newest .hybrid.iso."
    L[multi_iso]="Multiple ISO files found. Using newest"
    L[padding_iso]="Padding ISO (+10 MB) for VMware BIOS compatibility..."
    L[padding_fail]="Failed to pad ISO. Check disk space."
    L[result_title]="BUILD SUCCESSFUL"
    L[result_file]="File"
    L[result_size]="Size"
    L[result_sha256]="SHA256"
    L[result_md5]="MD5"
    L[result_duration]="Duration"
    L[result_log]="Log file"
    L[result_author]="Author"
    L[result_github]="GitHub"
    L[result_ready]="Ready for VMware / QEMU testing."
    L[stage_bootstrap]="Bootstrap (debootstrap)"
    L[stage_mount]="Chroot mounts & prep"
    L[stage_packages]="APT: package lists"
    L[stage_kernel]="Linux kernel (amd64)"
    L[stage_hooks]="Customization hooks"
    L[stage_squashfs]="SquashFS root image"
    L[stage_binary]="Binary live tree"
    L[stage_bootloader]="GRUB bootloaders"
    L[stage_iso]="ISO image (xorriso)"
    L[stage_checksum]="Checksums"
    L[progress_now]="Now"
    L[progress_stages]="stages"
    L[stage_done]="Build finished"
    L[build_aborted]="Build aborted at line"
    L[check_log]="See full log"
    L[elapsed]="Elapsed"
    L[stage_label]="Stage"
    L[completed_stages]="Completed stages"
    L[current_stage]="Current"
    L[events]="events"
    L[complete]="complete"
    L[prep_steps_title]="Preparation Steps"
    L[build_stages_title]="Build Stages"
    L[step_failed]="failed after"
    L[last_log_lines]="Last log lines:"
    L[failed_at_step]="FAILED"
    L[step_validate]="Project validation (scripts/validate.sh)"
    L[step_installer_preflight]="Installer preflight (Python + shared backend)"
    L[step_chmod_bin]="Setting installer scripts executable"
    L[version_label]="Distribution version"
    L[disk_low]="Low disk space on build volume"
    L[disk_ok]="Free disk space"
    L[validate_only_done]="Validation finished (no ISO built)"
    L[clean_only_done]="Clean completed"
    L[skip_validate]="Skipping pre-build validation"
}

load_lang_ru() {
    L[banner_title]="Сборка дистрибутива GreenWayOS"
    L[banner_author]="Автор: Сергей Карамышев (Vorsess)"
    L[banner_github]="GitHub: github.com/Vorsess"
    L[banner_ver]="Скрипт сборки v2.0"
    L[lang_prompt]="Выберите язык сборки"
    L[lang_ru]="Русский"
    L[lang_en]="English"
    L[section_env]="Окружение"
    L[section_prepare]="Подготовка окружения сборки"
    L[section_settings]="Параметры сборки"
    L[section_build]="Сборка ISO"
    L[section_finalize]="Финализация"
    L[work_dir]="Рабочая директория"
    L[cpu_cores]="Ядра CPU"
    L[ram_total]="Всего RAM"
    L[log_file]="Лог-файл"
    L[run_as_root]="Запустите от root (sudo ./build.sh)"
    L[lb_not_found]="live-build не найден. Устанавливаю зависимости..."
    L[lb_found]="live-build уже установлен."
    L[step_apt_update]="Обновление списков пакетов"
    L[step_install_deps]="Установка зависимостей сборки"
    L[step_purge]="Очистка старых артефактов"
    L[step_dos2unix]="Нормализация переносов строк (CRLF → LF)"
    L[step_chmod_auto]="Права на auto-скрипты"
    L[step_chmod_hooks]="Права на chroot-хуки"
    L[step_pre_config]="Обновление конфигурации со версией"
    L[step_lb_config]="Запуск lb config"
    L[deb_build_opts]="DEB_BUILD_OPTIONS"
    L[makeflags]="MAKEFLAGS"
    L[squashfs_opts]="Сжатие SquashFS"
    L[pigz_missing]="pigz не найден — используется gzip по умолчанию"
    L[build_start]="Сборка ISO-образа... это может занять 10-30+ минут."
    L[build_failed]="lb build завершился с ошибкой. Проверьте build.log."
    L[build_ok]="lb build завершён успешно!"
    L[no_iso]="Не найден .hybrid.iso. Проверьте build.log."
    L[no_iso_newest]="Не удалось определить новейший .hybrid.iso."
    L[multi_iso]="Найдено несколько ISO-файлов. Используется новейший"
    L[padding_iso]="Дополнение ISO (+10 МБ) для совместимости с VMware BIOS..."
    L[padding_fail]="Не удалось дополнить ISO. Проверьте место на диске."
    L[result_title]="СБОРКА УСПЕШНА"
    L[result_file]="Файл"
    L[result_size]="Размер"
    L[result_sha256]="SHA256"
    L[result_md5]="MD5"
    L[result_duration]="Длительность"
    L[result_log]="Лог-файл"
    L[result_author]="Автор"
    L[result_github]="GitHub"
    L[result_ready]="Готово к тестированию в VMware / QEMU."
    L[stage_bootstrap]="Bootstrap (debootstrap)"
    L[stage_mount]="Монтирование chroot"
    L[stage_packages]="APT: списки пакетов"
    L[stage_kernel]="Ядро Linux (amd64)"
    L[stage_hooks]="Хуки настройки"
    L[stage_squashfs]="Образ SquashFS"
    L[stage_binary]="Дерево binary live"
    L[stage_bootloader]="Загрузчики GRUB"
    L[stage_iso]="ISO-образ (xorriso)"
    L[stage_checksum]="Контрольные суммы"
    L[progress_now]="Сейчас"
    L[progress_stages]="этапов"
    L[stage_done]="Сборка завершена"
    L[build_aborted]="Сборка прервана на строке"
    L[check_log]="Полный лог"
    L[elapsed]="Прошло"
    L[stage_label]="Этап"
    L[completed_stages]="Завершённые этапы"
    L[current_stage]="Текущий"
    L[events]="событий"
    L[complete]="готово"
    L[prep_steps_title]="Этапы подготовки"
    L[build_stages_title]="Этапы сборки"
    L[step_failed]="ошибка через"
    L[last_log_lines]="Последние строки лога:"
    L[failed_at_step]="ОШИБКА"
    L[step_validate]="Проверка проекта (scripts/validate.sh)"
    L[step_installer_preflight]="Префлайт установщиков (Python + общий backend)"
    L[step_chmod_bin]="Права на скрипты установщика"
    L[version_label]="Версия дистрибутива"
    L[disk_low]="Мало места на диске сборки"
    L[disk_ok]="Свободное место на диске"
    L[validate_only_done]="Проверка завершена (ISO не собирался)"
    L[clean_only_done]="Очистка завершена"
    L[skip_validate]="Пропуск предварительной проверки"
}

msg() { printf "%s" "${L[$1]:-$1}"; }

# ── Styled output functions ─────────────────────────────────────────
info()  { print_line "${GREEN}  ✓${NC}  $*"; }
warn()  { print_line "${YELLOW}  ⚠${NC}  $*"; }
step_start() { printf "%b" "${CYAN}  →${NC}  $*"; }
step_ok()    { printf "%b\n" " ${GREEN}✔${NC} ${DIM}($*)${NC}"; }
err()   { print_line "${RED}  ✗${NC}  $*"; exit 1; }

hr() {
    print_line "${DIM}  ────────────────────────────────────────────────────────────────${NC}"
}

section() {
    print_line ""
    print_line "${BG_DARK}${GREEN}${BOLD}  ▸ $* ${NC}"
    hr
    log "SECTION: $*"
}

# ══════════════════════════════════════════════════════════════════════
#  BANNER
# ══════════════════════════════════════════════════════════════════════
banner() {
    print_line ""
    print_line "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${WHITE}${BOLD}██████╗ ██████╗ ███████╗███████╗███╗   ██╗${NC}                     ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${WHITE}${BOLD}██╔════╝ ██╔══██╗██╔════╝██╔════╝████╗  ██║${NC}                    ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${GREEN}${BOLD}██║  ███╗██████╔╝█████╗  █████╗  ██╔██╗ ██║${NC}                    ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${GREEN}██║   ██║██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║${NC}                    ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${DIM}╚██████╔╝██║  ██║███████╗███████╗██║ ╚████║${NC}                    ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${DIM} ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝${NC}                    ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${WHITE}${BOLD}██╗    ██╗ █████╗ ██╗   ██╗ ██████╗ ███████╗${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${WHITE}${BOLD}██║    ██║██╔══██╗╚██╗ ██╔╝██╔═══██╗██╔════╝${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${GREEN}${BOLD}██║ █╗ ██║███████║ ╚████╔╝ ██║   ██║███████╗${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${GREEN}██║███╗██║██╔══██║  ╚██╔╝  ██║   ██║╚════██║${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${DIM}╚███╔███╔╝██║  ██║   ██║   ╚██████╔╝███████║${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${DIM} ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚══════╝${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ╠══════════════════════════════════════════════════════════════════╣${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}  $(printf "%-62s" "$(msg banner_author)")                      ${GREEN}${BOLD}║${NC}"                    
    print_line "${GREEN}${BOLD}  ║${NC}  $(printf "%-62s" "$(msg banner_github)")  ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}  $(printf "%-62s" "$(msg banner_ver)")              ${GREEN}${BOLD}║${NC}"        
    print_line "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    print_line ""
}

# ══════════════════════════════════════════════════════════════════════
#  LANGUAGE SELECTION
# ══════════════════════════════════════════════════════════════════════
select_language() {
    case "${LANG_CHOICE}" in
        ru|RU|рус) LANG_CHOICE="ru"; load_lang_ru; info "Язык: Русский"; return ;;
        en|EN|eng) LANG_CHOICE="en"; load_lang_en; info "Language: English"; return ;;
        "") ;;
        *) warn "Unknown --lang '${LANG_CHOICE}', showing menu"; LANG_CHOICE="" ;;
    esac
    print_line "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}   ${WHITE}${BOLD}Select build language / Выберите язык сборки${NC}                   ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ╠══════════════════════════════════════════════════════════════════╣${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}       ${CYAN}${BOLD}[1]${NC}  🇷🇺  Русский                                           ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}       ${CYAN}${BOLD}[2]${NC}  🇬🇧  English                                           ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    print_line "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    print_line ""
    printf "  ${CYAN}${BOLD}▸${NC} ${WHITE}Choice / Выбор [1/2]:${NC} "
    local choice
    read -r choice
    case "${choice}" in
        1|р|Р) LANG_CHOICE="ru"; load_lang_ru ;;
        *)     LANG_CHOICE="en"; load_lang_en ;;
    esac
    print_line ""
    if [[ "${LANG_CHOICE}" == "ru" ]]; then
        info "Выбран язык: ${CYAN}Русский${NC}"
    else
        info "Language selected: ${CYAN}English${NC}"
    fi
}

# ══════════════════════════════════════════════════════════════════════
#  PREPARATION STEPS with visible progress
# ══════════════════════════════════════════════════════════════════════
PREP_STEP_NO=0
PREP_TOTAL_STEPS=0
PREP_TIMES=()
PREP_NAMES=()
PREP_STATUSES=()

run_prep_step() {
    local title="$1"
    local cmd="$2"
    PREP_STEP_NO=$((PREP_STEP_NO + 1))
    local label="(${PREP_STEP_NO}/${PREP_TOTAL_STEPS}) ${title}"
    step_start "${label}..."
    log "STEP START: ${title}"
    local started_at ended_at elapsed
    started_at="$(date +%s)"
    if eval "${cmd}" >> "${BUILD_LOG}" 2>&1; then
        ended_at="$(date +%s)"
        elapsed=$((ended_at - started_at))
        step_ok "$(fmt_duration ${elapsed})"
        log "STEP OK: ${title} (${elapsed}s)"
        PREP_TIMES+=("${elapsed}")
        PREP_NAMES+=("${title}")
        PREP_STATUSES+=("ok")
    else
        ended_at="$(date +%s)"
        elapsed=$((ended_at - started_at))
        log "STEP FAIL: ${title} (${elapsed}s)"
        print_line ""
        print_line "${RED}${BOLD}  ✗ ${title} — $(msg step_failed) $(fmt_duration ${elapsed})${NC}"
        print_line "${YELLOW}  $(msg last_log_lines)${NC}"
        tail -n 25 "${BUILD_LOG}" | sed 's/^/    /' || true
        PREP_TIMES+=("${elapsed}")
        PREP_NAMES+=("${title}")
        PREP_STATUSES+=("fail")
        exit 1
    fi
}

# Print a summary table of all completed prep steps
print_prep_summary() {
    print_line ""
    print_line "  ${GREEN}${BOLD}$(msg prep_steps_title)${NC}"
    hr
    local total_prep_time=0
    for i in "${!PREP_NAMES[@]}"; do
        local status_icon="${GREEN}✓${NC}"
        if [[ "${PREP_STATUSES[$i]}" == "fail" ]]; then
            status_icon="${RED}✗${NC}"
        fi
        local t="${PREP_TIMES[$i]}"
        total_prep_time=$((total_prep_time + t))
        printf "  %b  %-44s %b\n" "${status_icon}" "${PREP_NAMES[$i]}" "${DIM}$(fmt_duration ${t})${NC}"
    done
    hr
    print_line "  ${BOLD}$(msg elapsed): $(fmt_duration ${total_prep_time})${NC}"
}

# ══════════════════════════════════════════════════════════════════════
#  ERROR HANDLER
# ══════════════════════════════════════════════════════════════════════
on_error() {
    local line_no="$1"
    print_line ""
    print_line "${BG_RED}${WHITE}${BOLD}  $(msg build_aborted) ${line_no}.  ${NC}"
    print_line "${YELLOW}  $(msg check_log): ${BUILD_LOG}${NC}"
}
trap 'on_error ${LINENO}' ERR

# ══════════════════════════════════════════════════════════════════════
#  MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

load_lang_en
parse_args "$@"

if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
    GW_VERSION="$(tr -d '\r\n' < "${SCRIPT_DIR}/VERSION")"
fi

# Must be root (after --help)
[[ "${EUID}" -ne 0 ]] && err "$(msg run_as_root)"

if [[ -f "${BUILD_LOG}" ]]; then
    cp -f "${BUILD_LOG}" "${BUILD_LOG}.prev" 2>/dev/null || true
fi
: > "${BUILD_LOG}"

select_language
banner
info "$(msg version_label): ${CYAN}${GW_VERSION}${NC}"

if [[ "${CLEAN_ONLY}" == true ]]; then
    section "$(msg step_purge)"
    lb clean --purge 2>/dev/null || true
    rm -f greenwayos*.iso greenwayos*.hybrid.iso 2>/dev/null || true
    info "$(msg clean_only_done)"
    exit 0
fi

check_disk_space() {
    local need_mb=$((MIN_FREE_GB * 1024))
    local avail_kb avail_mb
    avail_kb="$(df -Pk "${SCRIPT_DIR}" | awk 'NR==2 {print $4}')"
    avail_mb=$((avail_kb / 1024))
    if (( avail_mb < need_mb )); then
        warn "$(msg disk_low): ${avail_mb} MB free, need ~${need_mb} MB"
        log "DISK WARN: ${avail_mb}MB free on $(df -Pk "${SCRIPT_DIR}" | awk 'NR==2 {print $1}')"
    else
        info "$(msg disk_ok): ${CYAN}${avail_mb} MB${NC}"
    fi
}
check_disk_space

# ── Environment ─────────────────────────────────────────────────────
section "$(msg section_env)"
log "Build started in ${SCRIPT_DIR}"
log "Kernel: $(uname -sr)"

NCPUS="$(nproc)"
TOTAL_MEM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
BUILD_MEM_MB=$((TOTAL_MEM_MB - 512))
[[ "${BUILD_MEM_MB}" -lt 512 ]] && BUILD_MEM_MB=512

info "$(msg work_dir)  : ${CYAN}${SCRIPT_DIR}${NC}"
info "$(msg cpu_cores)     : ${CYAN}${NCPUS}${NC}"
info "$(msg ram_total)      : ${CYAN}${TOTAL_MEM_MB} MB${NC}"
info "$(msg log_file)       : ${CYAN}${BUILD_LOG}${NC}"

# ── Prepare build environment ──────────────────────────────────────
section "$(msg section_prepare)"

# Count total prep steps (base 9: purge, dos2unix, chmod auto/hooks/bin, validate?, preflight?, pre-config, lb config)
PREP_TOTAL_STEPS=9
[[ "${SKIP_VALIDATE}" == true ]] && PREP_TOTAL_STEPS=$((PREP_TOTAL_STEPS - 2))
if ! command -v lb >/dev/null 2>&1; then
    PREP_TOTAL_STEPS=$((PREP_TOTAL_STEPS + 2))
    warn "$(msg lb_not_found)"
    run_with_retry 3 "apt-get update" apt-get update -qq
    run_with_retry 3 "Install build dependencies" apt-get install -y \
        live-build debootstrap squashfs-tools xorriso isolinux syslinux-efi gcc dos2unix pigz
else
    info "$(msg lb_found)"
fi

run_prep_step "$(msg step_purge)" \
    "lb clean --purge 2>/dev/null || true; rm -f greenwayos*.iso greenwayos*.hybrid.iso; rm -rf cache/bootstrap cache/packages.chroot cache/packages.binary"

run_prep_step "$(msg step_dos2unix)" \
    "find config/ auto/ scripts/ -type f -exec dos2unix -q {} + 2>/dev/null || true; dos2unix -q build.sh 2>/dev/null || true"

run_prep_step "$(msg step_chmod_auto)" \
    "chmod +x auto/config auto/clean auto/build 2>/dev/null || true"

run_prep_step "$(msg step_chmod_hooks)" \
    "find config/hooks -type f \( -name '*.chroot' -o -name '*.binary' -o -name '*.hook.chroot' -o -name '*.hook.binary' \) -exec chmod +x {} + 2>/dev/null || true"

run_prep_step "$(msg step_chmod_bin)" \
    "find config/includes.chroot/usr/local/bin -type f -exec chmod +x {} + 2>/dev/null || true; chmod +x config/includes.chroot/usr/local/bin/greenwayos-gui-x-fallback.sh 2>/dev/null || true; find scripts -maxdepth 1 -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true"

if [[ "${SKIP_VALIDATE}" != true ]]; then
    run_prep_step "$(msg step_validate)" \
        "bash scripts/validate.sh"

    run_prep_step "$(msg step_installer_preflight)" \
        "python3 -m py_compile config/includes.chroot/usr/local/bin/greenwayos-installer config/includes.chroot/usr/local/bin/greenwayos-installer-gui && PYTHONPATH=config/includes.chroot/usr/local/lib/greenwayos python3 -c 'from install.engine import install_system; from install.constants import INSTALL_STEPS; assert len(INSTALL_STEPS) > 10'"
else
    warn "$(msg skip_validate)"
fi

run_prep_step "$(msg step_pre_config)" \
    "bash scripts/pre-config.sh"

run_prep_step "$(msg step_lb_config)" "lb config"

print_prep_summary

if [[ "${VALIDATE_ONLY}" == true ]]; then
    info "$(msg validate_only_done)"
    exit 0
fi

# ── Build settings ──────────────────────────────────────────────────
section "$(msg section_settings)"
export DEB_BUILD_OPTIONS="parallel=${NCPUS} nocheck"
export MAKEFLAGS="-j${NCPUS}"
info "$(msg deb_build_opts) = ${CYAN}${DEB_BUILD_OPTIONS}${NC}"
info "$(msg makeflags)      = ${CYAN}${MAKEFLAGS}${NC}"

if command -v pigz >/dev/null 2>&1; then
    export MKSQUASHFS_OPTIONS="-Xcompression-level 1 -processors ${NCPUS}"
    info "$(msg squashfs_opts) = ${CYAN}${MKSQUASHFS_OPTIONS}${NC}"
else
    warn "$(msg pigz_missing)"
fi

# ══════════════════════════════════════════════════════════════════════
#  ISO BUILD with rich live progress
# ══════════════════════════════════════════════════════════════════════
section "$(msg section_build)"
print_line "  ${CYAN}${ITALIC}$(msg build_start)${NC}"
print_line ""
log "Starting lb build"

# live-build hard limitation: it refuses to build from paths containing spaces.
# Work around by building in a temporary directory without spaces and copying artifacts back.
ORIG_DIR="$(pwd)"
TEMP_BUILD_DIR=""
if [[ "${ORIG_DIR}" == *" "* ]]; then
    warn "live-build cannot run from a path containing spaces."
    step_start "Creating temporary build directory (no spaces)..."
    TEMP_BUILD_DIR="/tmp/greenwayos-build-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${TEMP_BUILD_DIR}" || { err "Failed to create ${TEMP_BUILD_DIR}"; exit 1; }
    step_ok "${TEMP_BUILD_DIR}"

    step_start "Copying project into temporary build directory..."
    rsync -a --delete \
        --exclude 'binary/' \
        --exclude 'chroot/' \
        --exclude 'cache/' \
        --exclude '.cache/' \
        --exclude '.lb' \
        --exclude 'build.log' \
        --exclude '*.iso' \
        --exclude '*.hybrid.iso' \
        --exclude '*.hybrid.iso.*' \
        ./ "${TEMP_BUILD_DIR}/" || { err "rsync copy failed"; exit 1; }
    step_ok "Project copied"

    cd "${TEMP_BUILD_DIR}" || { err "Failed to cd to temp build dir"; exit 1; }
    log "Build dir switched to ${TEMP_BUILD_DIR} (origin: ${ORIG_DIR})"
fi

TERM_COLS="$(tput cols 2>/dev/null || echo 120)"
if [[ -z "${TERM_COLS}" || ! "${TERM_COLS}" =~ ^[0-9]+$ ]]; then
    TERM_COLS=120
fi
if [[ "${TERM_COLS}" -lt 80 ]]; then
    TERM_COLS=80
fi

# Live progress: scripts/lb-build-progress.awk (parses real lb build lines)
PROGRESS_AWK="${SCRIPT_DIR}/scripts/lb-build-progress.awk"
[[ -f "${PROGRESS_AWK}" ]] || err "Missing ${PROGRESS_AWK}"

S1="$(msg stage_bootstrap)"
S2="$(msg stage_mount)"
S3="$(msg stage_packages)"
S4="$(msg stage_kernel)"
S5="$(msg stage_hooks)"
S6="$(msg stage_squashfs)"
S7="$(msg stage_binary)"
S8="$(msg stage_bootloader)"
S9="$(msg stage_iso)"
S10="$(msg stage_checksum)"
S_DONE="$(msg stage_done)"
L_NOW="$(msg progress_now)"
L_STAGES="$(msg progress_stages)"

set +e
stdbuf -oL lb build 2>&1 | awk -f "${PROGRESS_AWK}" \
    -v logfile="${BUILD_LOG}" \
    -v term_cols="${TERM_COLS}" \
    -v s1="${S1}" -v s2="${S2}" -v s3="${S3}" -v s4="${S4}" -v s5="${S5}" \
    -v s6="${S6}" -v s7="${S7}" -v s8="${S8}" -v s9="${S9}" -v s10="${S10}" \
    -v s_done="${S_DONE}" \
    -v l_now="${L_NOW}" \
    -v l_stages="${L_STAGES}"
LB_EXIT=${PIPESTATUS[0]}
set -e

# If we built in a temp directory, copy artifacts back to original directory.
if [[ -n "${TEMP_BUILD_DIR}" ]]; then
    step_start "Copying artifacts back to original directory..."
    shopt -s nullglob
    iso_out=( *.iso *.hybrid.iso *.hybrid.iso.sha256 *.hybrid.iso.md5 *.iso.sha256 *.iso.md5 )
    shopt -u nullglob
    if [[ ${#iso_out[@]} -gt 0 ]]; then
        cp -f -- "${iso_out[@]}" "${ORIG_DIR}/" 2>/dev/null || true
        step_ok "${ORIG_DIR}"
    else
        warn "No ISO artifacts found in temp build dir"
    fi
    cd "${ORIG_DIR}" || true
fi

if [[ "${LB_EXIT}" -ne 0 ]]; then
    print_line ""
    print_line "${BG_RED}${WHITE}${BOLD}  $(msg build_failed)  ${NC}"
    print_line "${YELLOW}  $(msg last_log_lines)${NC}"
    tail -n 30 "${BUILD_LOG}" | sed 's/^/    /' || true
    exit 1
fi

print_line ""
info "${GREEN}${BOLD}$(msg build_ok)${NC}"

if grep -E '^P: Begin |Running hook ' "${BUILD_LOG}" >/dev/null 2>&1; then
    print_line ""
    print_line "  ${GREEN}${BOLD}$(msg build_stages_title)${NC} ${DIM}(from build.log)${NC}"
    hr
    grep -E '^P: Begin |Running hook ' "${BUILD_LOG}" | sed 's/^/    /' | tail -n 20 || true
    hr
fi

# ══════════════════════════════════════════════════════════════════════
#  FINALIZE OUTPUT
# ══════════════════════════════════════════════════════════════════════
section "$(msg section_finalize)"

shopt -s nullglob
iso_candidates=( *.hybrid.iso )
shopt -u nullglob
if [[ ${#iso_candidates[@]} -eq 0 ]]; then
    err "$(msg no_iso)"
fi
ISO="$(ls -t -- "${iso_candidates[@]}" 2>/dev/null | awk 'NR==1 {print; exit}')"
if [[ -z "${ISO}" ]]; then
    err "$(msg no_iso_newest)"
fi
if [[ ${#iso_candidates[@]} -gt 1 ]]; then
    warn "$(msg multi_iso): ${ISO}"
fi

# ── ISO sanity check (fast, before padding) ─────────────────────────
if [[ -x scripts/iso-sanity-check.sh ]]; then
    step_start "ISO sanity check..."
    if scripts/iso-sanity-check.sh "${ISO}" >> "${BUILD_LOG}" 2>&1; then
        step_ok "PASS"
    else
        print_line ""
        warn "ISO sanity check failed. See ${BUILD_LOG} for details."
    fi
fi

if [[ "${SKIP_PAD}" == true ]]; then
    warn "ISO padding skipped (--no-pad)"
else
    step_start "$(msg padding_iso)"
    if dd if=/dev/zero bs=1M count=10 >> "${ISO}" 2>/dev/null; then
        step_ok "10 MB"
    else
        print_line ""
        err "$(msg padding_fail)"
    fi
fi

SIZE="$(du -sh "${ISO}" | cut -f1)"
SHA256="$(sha256sum "${ISO}" | awk "{print \$1}")"
MD5="$(md5sum "${ISO}" | awk "{print \$1}")"
END_TS="$(date +%s)"
TOTAL_ELAPSED="$((END_TS - SCRIPT_START_TS))"

# ── Generate checksum files ─────────────────────────────────────────
step_start "Generating checksum files..."
echo "${SHA256}  ${ISO}" > "${ISO}.sha256"
echo "${MD5}  ${ISO}" > "${ISO}.md5"
chmod 644 "${ISO}.sha256" "${ISO}.md5"
step_ok "Done"
log "Checksum files generated: ${ISO}.sha256 and ${ISO}.md5"
print_line ""
print_line "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
# Use standard centering for title, no printf with ansi
print_line "${GREEN}${BOLD}  ║${NC}               ${WHITE}${BOLD}$(msg result_title): GreenWayOS${NC}                   ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ╠══════════════════════════════════════════════════════════════════╣${NC}"
print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf '%-14s' "$(msg result_file)")  ${CYAN}$(printf "%-45s" "${ISO}")${NC}  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf '%-14s' "$(msg result_size)")  ${CYAN}$(printf "%-45s" "${SIZE}")${NC}  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf '%-14s' "$(msg result_sha256)")  ${CYAN}$(printf "%-45s" "${SHA256}")${NC}  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf '%-14s' "$(msg result_md5)")  ${CYAN}$(printf "%-45s" "${MD5}")${NC}  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf '%-14s' "$(msg result_duration)")  ${CYAN}$(printf "%-45s" "$(fmt_duration ${TOTAL_ELAPSED})")${NC}  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf '%-14s' "$(msg result_log)")  ${CYAN}$(printf "%-45s" "${BUILD_LOG}")${NC}  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ╠══════════════════════════════════════════════════════════════════╣${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf "%-61s" "$(msg result_author): Sergey Karamyshev")  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}   $(printf "%-61s" "$(msg result_github): github.com/Vorsess")  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
print_line "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
print_line ""

# ── Preparation stages table ────────────────────────────────────────
print_line "  ${GREEN}${BOLD}$(msg prep_steps_title)${NC}"
hr
for i in "${!PREP_NAMES[@]}"; do
    local_icon="${GREEN}✓${NC}"
    [[ "${PREP_STATUSES[$i]}" == "fail" ]] && local_icon="${RED}✗${NC}"
    printf "  %b  %-44s %b\n" "${local_icon}" "${PREP_NAMES[$i]}" "${DIM}$(fmt_duration ${PREP_TIMES[$i]})${NC}"
done
hr

print_line ""
info "${GREEN}${BOLD}$(msg result_ready)${NC}"
print_line ""
