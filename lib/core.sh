#!/usr/bin/env bash

# shellcheck disable=SC2034

#######################################
# Defaults / flags
#######################################

FORCE_BREW="${FORCE_BREW:-0}"
DRY_RUN="${DRY_RUN:-0}"
QUIET="${QUIET:-0}"
SCHEDULED="${SCHEDULED:-0}"
PULL_DOTFILES="${PULL_DOTFILES:-0}"
STRICT_OPTIONAL_CONFIGS="${STRICT_OPTIONAL_CONFIGS:-0}"
SETUP_SCHEDULE="${SETUP_SCHEDULE:-1}"
UPGRADE_PACKAGES="${UPGRADE_PACKAGES:-1}"

#######################################
# Paths
#######################################

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_DIR="${LOG_DIR:-$STATE_HOME/dotfiles}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/install.log}"
BACKUP_SUFFIX="${BACKUP_SUFFIX:-.old}"
LOCK_DIR="${LOCK_DIR:-$CACHE_HOME/dotfiles-install.lock}"

#######################################
# Counters / status
#######################################

CREATED_DIRS=0
BACKED_UP_PATHS=0
LINKED_FILES=0
SKIPPED_LINKS=0
INSTALLED_PACKAGES=0
SKIPPED_PACKAGES=0
UPGRADED_PACKAGES=0
REMOVED_PACKAGES=0
CLONED_REPOS=0
SKIPPED_REPOS=0
INSTALLED_FONTS=0
SKIPPED_FONTS=0
VALIDATED_OK=0
VALIDATED_FAIL=0
WARNINGS=0
ERRORS=0

#######################################
# Runtime state
#######################################

ALACRITTY_UPDATED=0
TMUX_CONFIG_CHANGED=0
GIT_BIN=""
GH_INSTALLED_THIS_RUN=0
GH_NEEDS_AUTH_HINT=0
GPG_INSTALLED_THIS_RUN=0
ONEPASSWORD_INSTALLED_THIS_RUN=0
ONEPASSWORD_CLI_INSTALLED_THIS_RUN=0
ONEPASSWORD_SAFARI_NEXT_STEP=0
FINDER_PREFS_CHANGED=0
SAFARI_DEVTOOLS_NEXT_STEP=0

#######################################
# OS detection
#######################################

PLATFORM="unknown"

detect_platform() {
    local uname_out
    uname_out="$(uname -s)"
    case "${uname_out}" in
        Linux*)   PLATFORM="linux" ;;
        Darwin*)  PLATFORM="mac" ;;
        CYGWIN*)  PLATFORM="cygwin" ;;
        MINGW*|MSYS*) PLATFORM="windows" ;;
        *)        PLATFORM="unknown" ;;
    esac
}

is_macos() {
    [ "$PLATFORM" = "mac" ]
}

is_linux() {
    [ "$PLATFORM" = "linux" ]
}

is_interactive() {
    [ "$QUIET" != "1" ] && [ "$SCHEDULED" != "1" ] && [ -t 1 ]
}

#######################################
# Sections
#######################################

SECTIONS=(
    "Environment"
    "Homebrew"
    "Directory setup"
    "Package upgrades"
    "Package checks"
    "Alacritty"
    "Git"
    "Remove neofetch"
    "Cloned tools"
    "Config symlinks"
    "Vim"
    "Fonts"
    "tmux"
    "1Password"
    "GPG"
    "macOS preferences"
    "Scheduling"
    "fastfetch"
    "Summary"
)

TOTAL_SECTIONS=0
CURRENT_SECTION=0

init_sections() {
    TOTAL_SECTIONS="${#SECTIONS[@]}"
    CURRENT_SECTION=0
}

#######################################
# UI / colors
#######################################

USE_COLOR=0
C_RESET=""
C_BOLD=""
C_DIM=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_BLUE=""
C_MAGENTA=""
C_CYAN=""
C_WHITE=""

TAG_RUN="[RUN ]"
TAG_OK="[OK  ]"
TAG_SKIP="[SKIP]"
TAG_WARN="[WARN]"
TAG_FAIL="[FAIL]"
TAG_INFO="[INFO]"

init_colors() {
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "$QUIET" != "1" ]; then
        USE_COLOR=1
    else
        USE_COLOR=0
    fi

    if [ "$USE_COLOR" = "1" ]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_MAGENTA=$'\033[35m'
        C_CYAN=$'\033[36m'
        C_WHITE=$'\033[37m'
    fi
}

#######################################
# Logging
#######################################

FIRST_RUN_LOG="${LOG_DIR}/install.log.first"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

append_log_raw() {
    printf '%s\n' "$1" >>"$LOG_FILE" 2>/dev/null || true
}

append_log() {
    append_log_raw "$(timestamp) $1"
}

rotate_logs() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true

    if [ -f "$LOG_FILE" ] && [ ! -f "$FIRST_RUN_LOG" ]; then
        cp -f "$LOG_FILE" "$FIRST_RUN_LOG" 2>/dev/null || true
    fi

    local i
    for i in 7 6 5 4 3 2 1; do
        if [ -f "${LOG_FILE}.${i}" ]; then
            if [ "$i" -eq 7 ]; then
                rm -f "${LOG_FILE}.${i}"
            else
                mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
            fi
        fi
    done

    if [ -f "$LOG_FILE" ]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

init_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    mkdir -p "$CACHE_HOME" 2>/dev/null || true

    rotate_logs

    : > "$LOG_FILE" 2>/dev/null || {
        printf 'ERROR: Could not create log file: %s\n' "$LOG_FILE" >&2
        exit 1
    }

    append_log "Log initialized"
}

#######################################
# Terminal / display helpers
#######################################

get_term_lines() {
    local lines=""

    if [ -r /dev/tty ]; then
        lines="$(stty size </dev/tty 2>/dev/null | awk '{print $1}')"
    fi

    if [ -z "$lines" ] && [ -n "${LINES:-}" ]; then
        lines="$LINES"
    fi

    if [ -z "$lines" ]; then
        lines="$(tput lines 2>/dev/null || echo 24)"
    fi

    if [ -z "$lines" ] || [ "$lines" -lt 10 ]; then
        lines=24
    fi

    printf '%s\n' "$lines"
}

get_term_width() {
    local cols=""

    if [ -r /dev/tty ]; then
        cols="$(stty size </dev/tty 2>/dev/null | awk '{print $2}')"
    fi

    if [ -z "$cols" ] && [ -n "${COLUMNS:-}" ]; then
        cols="$COLUMNS"
    fi

    if [ -z "$cols" ]; then
        cols="$(tput cols 2>/dev/null || echo 80)"
    fi

    if [ -z "$cols" ] || [ "$cols" -lt 40 ]; then
        cols=80
    fi

    printf '%s\n' "$cols"
}

repeat_char() {
    local char="$1"
    local count="$2"

    if [ "$count" -le 0 ]; then
        return 0
    fi

    printf '%*s' "$count" '' | tr ' ' "$char"
}

print_rule() {
    local char="${1:-─}"
    local cols
    cols="$(get_term_width)"
    repeat_char "$char" "$cols"
    printf '\n'
}

#######################################
# Persistent progress bar
#######################################

PROGRESS_UI_ENABLED=0
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_TITLE="Bootstrap"
CURRENT_NR_LINES=0
CURRENT_NR_COLS=0

progress_ui_enabled() {
    is_interactive
}

progress_setup() {
    progress_ui_enabled || return 0

    shopt -s checkwinsize 2>/dev/null || true

    PROGRESS_UI_ENABLED=1
    PROGRESS_TOTAL="$TOTAL_SECTIONS"
    PROGRESS_CURRENT=0
    PROGRESS_TITLE="Bootstrap"

    CURRENT_NR_LINES="$(get_term_lines)"
    CURRENT_NR_COLS="$(get_term_width)"

    local lines
    lines="$CURRENT_NR_LINES"

    printf '\n'
    tput sc 2>/dev/null || true
    printf '\033[1;%sr' "$((lines - 1))"
    tput rc 2>/dev/null || true

    progress_draw
}

progress_destroy() {
    [ "${PROGRESS_UI_ENABLED:-0}" -eq 1 ] || return 0

    local lines
    lines="$CURRENT_NR_LINES"

    tput sc 2>/dev/null || true
    tput cup $((lines - 1)) 0 2>/dev/null || true
    tput el 2>/dev/null || true
    printf '\033[0;%sr' "$lines"
    tput rc 2>/dev/null || true

    PROGRESS_UI_ENABLED=0
}

progress_draw() {
    [ "${PROGRESS_UI_ENABLED:-0}" -eq 1 ] || return 0

    local cols lines label counter reserved width filled empty
    cols="$CURRENT_NR_COLS"
    lines="$CURRENT_NR_LINES"

    label="${PROGRESS_TITLE} "
    counter=" ${PROGRESS_CURRENT}/${PROGRESS_TOTAL}"
    reserved=$(( ${#label} + ${#counter} + 3 ))
    width=$(( cols - reserved ))
    if [ "$width" -lt 10 ]; then
        width=10
    fi

    if [ "$PROGRESS_TOTAL" -gt 0 ]; then
        filled=$(( PROGRESS_CURRENT * width / PROGRESS_TOTAL ))
    else
        filled=0
    fi
    empty=$(( width - filled ))

    tput sc 2>/dev/null || true
    tput cup $((lines - 1)) 0 2>/dev/null || true
    tput el 2>/dev/null || true

    printf '%s%s%s ' "${C_BOLD}${C_CYAN}" "$PROGRESS_TITLE" "${C_RESET}"
    printf '%s[' "${C_MAGENTA}"
    repeat_char '█' "$filled"
    repeat_char '░' "$empty"
    printf ']%s %d/%d' "${C_RESET}" "$PROGRESS_CURRENT" "$PROGRESS_TOTAL"

    tput rc 2>/dev/null || true
}

progress_advance() {
    [ "${PROGRESS_UI_ENABLED:-0}" -eq 1 ] || return 0
    PROGRESS_CURRENT="$CURRENT_SECTION"
    progress_draw
}

#######################################
# Pretty output helpers
#######################################

print_info() {
    local msg="$1"
    if [ "$QUIET" != "1" ]; then
        printf '%s%s%s %s\n' "${C_DIM}" "$TAG_INFO" "${C_RESET}" "$msg"
    fi
    append_log "$TAG_INFO $msg"
}

print_ok() {
    local msg="$1"
    if [ "$QUIET" != "1" ]; then
        printf '%s%s%s %s\n' "${C_GREEN}" "$TAG_OK" "${C_RESET}" "$msg"
    fi
    append_log "$TAG_OK $msg"
}

print_skip() {
    local msg="$1"
    if [ "$QUIET" != "1" ]; then
        printf '%s%s%s %s\n' "${C_DIM}" "$TAG_SKIP" "${C_RESET}" "$msg"
    fi
    append_log "$TAG_SKIP $msg"
}

print_warn() {
    local msg="$1"
    WARNINGS=$((WARNINGS + 1))
    if [ "$QUIET" != "1" ]; then
        printf '%s%s%s %s\n' "${C_YELLOW}" "$TAG_WARN" "${C_RESET}" "$msg" >&2
    fi
    append_log "$TAG_WARN $msg"
}

print_error() {
    local msg="$1"
    ERRORS=$((ERRORS + 1))
    if [ "$QUIET" != "1" ]; then
        printf '%s%s%s %s\n' "${C_RED}" "$TAG_FAIL" "${C_RESET}" "$msg" >&2
    fi
    append_log "$TAG_FAIL $msg"
}

#######################################
# Section headers / spinner
#######################################

start_section() {
    local title="$1"

    CURRENT_SECTION=$((CURRENT_SECTION + 1))

    if [ "$QUIET" != "1" ]; then
        printf '\n%s──[%s %s %s]──%s\n\n' \
            "${C_BOLD}${C_CYAN}" \
            "${C_WHITE}" \
            "$title" \
            "${C_CYAN}" \
            "${C_RESET}"
    fi

    append_log ""
    append_log "━━ $title"

    progress_advance
}

spinner_run() {
    local description="$1"
    shift

    if [ "$DRY_RUN" = "1" ]; then
        local rendered
        rendered="$(printf '%q ' "$@")"
        if [ "$QUIET" != "1" ]; then
            printf '%s%s%s %s\n' "${C_MAGENTA}" "$TAG_RUN" "${C_RESET}" "$description"
            printf '      %s\n' "$rendered"
        fi
        append_log "[DRY ] $description"
        append_log "       $rendered"
        return 0
    fi

    append_log "$TAG_RUN $description"
    append_log "       $(printf '%q ' "$@")"

    if [ "$QUIET" = "1" ]; then
        "$@" >>"$LOG_FILE" 2>&1
        local status=$?
        if [ "$status" -eq 0 ]; then
            append_log "$TAG_OK $description"
        else
            append_log "$TAG_FAIL $description (exit $status)"
        fi
        return "$status"
    fi

    "$@" >>"$LOG_FILE" 2>&1 &
    local pid=$!
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    printf '%s%s%s %s\n' "${C_WHITE}" "$TAG_RUN" "${C_RESET}" "$description"
    printf '      '

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r      %s%s%s working...' "${C_CYAN}" "${spin:i++%${#spin}:1}" "${C_RESET}"
        sleep 0.1
    done

    wait "$pid"
    local status=$?

    printf '\r\033[K'

    if [ "$status" -eq 0 ]; then
        printf '%s%s%s %s\n' "${C_GREEN}" "$TAG_OK" "${C_RESET}" "$description"
        append_log "$TAG_OK $description"
        return 0
    else
        printf '%s%s%s %s\n' "${C_RED}" "$TAG_FAIL" "${C_RESET}" "$description"
        append_log "$TAG_FAIL $description (exit $status)"
        return "$status"
    fi
}

#######################################
# Lock / cleanup
#######################################

cleanup() {
    progress_destroy
    rm -rf "$LOCK_DIR"
}

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        trap cleanup EXIT INT TERM
    else
        print_warn "Another install run appears to be in progress: $LOCK_DIR"
        exit 1
    fi
}

#######################################
# Validation helpers
#######################################

mark_validated_ok() {
    VALIDATED_OK=$((VALIDATED_OK + 1))
}

mark_validated_fail() {
    VALIDATED_FAIL=$((VALIDATED_FAIL + 1))
}

verify_command_present() {
    local command_name="$1"
    if command -v "$command_name" >/dev/null 2>&1; then
        mark_validated_ok
        return 0
    fi
    mark_validated_fail
    return 1
}

verify_symlink_target() {
    local target="$1"
    local expected_source="$2"

    if [ -L "$target" ]; then
        local current
        current="$(readlink "$target" 2>/dev/null || true)"
        if [ "$current" = "$expected_source" ]; then
            mark_validated_ok
            return 0
        fi
    fi

    mark_validated_fail
    return 1
}

verify_path_exists() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        mark_validated_ok
        return 0
    fi
    mark_validated_fail
    return 1
}

verify_xattr_absent() {
    local path="$1"
    local attr="$2"

    if xattr "$path" 2>/dev/null | grep -Fxq "$attr"; then
        mark_validated_fail
        return 1
    fi

    mark_validated_ok
    return 0
}

verify_permission_not_group_other_writable() {
    local path="$1"

    if [ ! -e "$path" ]; then
        mark_validated_fail
        return 1
    fi

    local perms
    perms="$(stat -f '%Mp%Lp' "$path" 2>/dev/null || true)"
    if [ -z "$perms" ]; then
        mark_validated_fail
        return 1
    fi

    local last_two
    last_two="${perms#${perms%??}}"

    case "$last_two" in
        [2367][2367]|[2367][2367]) mark_validated_fail; return 1 ;;
    esac

    mark_validated_ok
    return 0
}

#######################################
# Generic utility helpers
#######################################

clear_quarantine_if_present() {
    local path="$1"
    local quarantine_attr="${2:-com.apple.quarantine}"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        print_error "Cannot clear quarantine; path not found: $path"
        mark_validated_fail
        return 1
    fi

    if verify_xattr_absent "$path" "$quarantine_attr"; then
        return 0
    fi

    if spinner_run "Clear quarantine: $path" xattr -dr "$quarantine_attr" "$path"; then
        if verify_xattr_absent "$path" "$quarantine_attr"; then
            print_ok "Cleared quarantine: $path"
            return 0
        fi

        print_error "Quarantine attribute still present after clear attempt: $path"
        mark_validated_fail
        return 1
    fi

    print_error "Failed to clear quarantine: $path"
    mark_validated_fail
    return 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

homebrew_available() { command_exists brew; }
apt_available() { command_exists apt-get; }
dnf_available() { command_exists dnf; }
pacman_available() { command_exists pacman; }
cron_available() { command_exists crontab; }

ensure_dir() {
    local dir="$1"

    if [ -d "$dir" ]; then
        print_skip "Directory exists: $dir"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Create directory: $dir" mkdir -p "$dir"; then
        if [ -d "$dir" ]; then
            CREATED_DIRS=$((CREATED_DIRS + 1))
            print_ok "Directory created: $dir"
            mark_validated_ok
            return 0
        fi
    fi

    print_error "Failed to create directory: $dir"
    mark_validated_fail
    return 1
}

backup_if_exists() {
    local target="$1"

    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ ! -e "${target}${BACKUP_SUFFIX}" ] && [ ! -L "${target}${BACKUP_SUFFIX}" ]; then
            if spinner_run "Back up $target" mv -f "$target" "${target}${BACKUP_SUFFIX}"; then
                if verify_path_exists "${target}${BACKUP_SUFFIX}"; then
                    BACKED_UP_PATHS=$((BACKED_UP_PATHS + 1))
                    print_ok "Backed up: $target"
                    return 0
                fi
            fi
            print_error "Failed backup verification: $target"
            return 1
        else
            if spinner_run "Remove existing path $target" rm -rf "$target"; then
                if [ ! -e "$target" ] && [ ! -L "$target" ]; then
                    mark_validated_ok
                    return 0
                fi
            fi
            print_error "Failed to remove current path: $target"
            mark_validated_fail
            return 1
        fi
    fi

    return 0
}

prompt_yes_no_default_yes() {
    local prompt="$1"
    local answer=""

    if ! is_interactive; then
        return 1
    fi

    printf '%s%s%s [Y/n] ' "${C_DIM}" "$prompt" "${C_RESET}"
    read -r answer
    answer="${answer:-Y}"

    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}


ensure_sudo_cached() {
    if [ "$DRY_RUN" = "1" ]; then
        return 0
    fi

    if [ ! -t 1 ]; then
        print_error "sudo required, but no interactive terminal is available"
        return 1
    fi

    printf '\n'
    sudo -v
}

#######################################
# Task runner
#######################################

task_should_run() {
    local platform_scope="$1"
    local interactive_required="$2"

    case "$platform_scope" in
        all) ;;
        mac) [ "$PLATFORM" = "mac" ] || return 1 ;;
        linux) [ "$PLATFORM" = "linux" ] || return 1 ;;
        *) return 1 ;;
    esac

    if [ "$interactive_required" = "1" ] && ! is_interactive; then
        return 1
    fi

    return 0
}

run_tasks() {
    local task_record=""
    local section_name=""
    local function_name=""
    local platform_scope=""
    local interactive_required=""

    for task_record in "$@"; do
        IFS='|' read -r section_name function_name platform_scope interactive_required <<< "$task_record"

        if ! task_should_run "$platform_scope" "$interactive_required"; then
            continue
        fi

        start_section "$section_name"

        if declare -F "$function_name" >/dev/null 2>&1; then
            "$function_name"
        else
            print_error "Task function not found: $function_name"
            mark_validated_fail
        fi
    done
}