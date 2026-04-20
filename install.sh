#!/usr/bin/env bash

set -uo pipefail

#######################################
# Defaults / flags
#######################################

FORCE_BREW=0
DRY_RUN=0
QUIET=0
SCHEDULED=0
PULL_DOTFILES=0
STRICT_OPTIONAL_CONFIGS=0
SETUP_SCHEDULE=1
UPGRADE_PACKAGES=1

#######################################
# Paths
#######################################

DOTFILES_DIR="${HOME}/dotfiles"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_DIR="${STATE_HOME}/dotfiles"
LOG_FILE="${LOG_DIR}/install.log"
BACKUP_SUFFIX=".old"
LOCK_DIR="${CACHE_HOME}/dotfiles-install.lock"

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

#######################################
# OS detection
#######################################

PLATFORM="unknown"

uname_out="$(uname -s)"
case "${uname_out}" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="mac" ;;
    CYGWIN*)  PLATFORM="cygwin" ;;
    MINGW*|MSYS*) PLATFORM="windows" ;;
    *)        PLATFORM="unknown" ;;
esac

#######################################
# Sections (dynamic progress count)
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
    "Scheduling"
    "Runtime notices"
    "fastfetch"
    "Summary"
)

TOTAL_SECTIONS="${#SECTIONS[@]}"
CURRENT_SECTION=0

#######################################
# Argument parsing
#######################################

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --force-brew               Install configured Homebrew formulas even if command already exists
  --dry-run                  Print actions without executing them
  --quiet                    Reduce terminal output
  --scheduled                Non-interactive maintenance mode; implies --pull-dotfiles and skips runtime reloads/prompts
  --pull-dotfiles            Run git pull --ff-only in ~/dotfiles before applying changes
  --strict-optional-configs  Treat missing optional config sources as warnings
  --no-schedule              Do not create/check weekly scheduled run
  --no-upgrade               Skip package-manager update/upgrade step
  -h, --help                 Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force-brew) FORCE_BREW=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --quiet) QUIET=1 ;;
        --scheduled) SCHEDULED=1; PULL_DOTFILES=1; QUIET=1 ;;
        --pull-dotfiles) PULL_DOTFILES=1 ;;
        --strict-optional-configs) STRICT_OPTIONAL_CONFIGS=1 ;;
        --no-schedule) SETUP_SCHEDULE=0 ;;
        --no-upgrade) UPGRADE_PACKAGES=0 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

#######################################
# UI / colors
#######################################

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
else
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
fi

TAG_RUN="[RUN ]"
TAG_OK="[OK  ]"
TAG_SKIP="[SKIP]"
TAG_WARN="[WARN]"
TAG_FAIL="[FAIL]"
TAG_INFO="[INFO]"

#######################################
# Logging bootstrap
#######################################

init_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    mkdir -p "$CACHE_HOME" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || {
        printf 'ERROR: Could not create log file: %s\n' "$LOG_FILE" >&2
        exit 1
    }
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

append_log() {
    printf '%s\n' "$1" >>"$LOG_FILE" 2>/dev/null || true
}

#######################################
# Terminal / display helpers
#######################################

get_term_width() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
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
# Sections / progress / spinner
#######################################

render_progress_bar() {
    local current="$1"
    local total="$2"
    local cols
    local reserved
    local width
    local filled=0
    local empty=0

    cols="$(get_term_width)"
    reserved=10
    width=$(( cols - reserved ))

    if [ "$width" -lt 20 ]; then
        width=20
    fi

    if [ "$total" -gt 0 ]; then
        filled=$(( current * width / total ))
    fi
    empty=$(( width - filled ))

    printf '%s[' "${C_MAGENTA}"
    repeat_char '█' "$filled"
    repeat_char '░' "$empty"
    printf ']%s %d/%d\n' "${C_RESET}" "$current" "$total"
}

start_section() {
    local title="$1"
    local cols
    local title_text
    local title_len
    local side_len
    local left
    local right

    CURRENT_SECTION=$((CURRENT_SECTION + 1))

    cols="$(get_term_width)"
    title_text="  ${title}  "
    title_len=${#title_text}
    side_len=$(( (cols - title_len) / 2 ))

    if [ "$side_len" -lt 2 ]; then
        side_len=2
    fi

    left="$(repeat_char '━' "$side_len")"
    right="$(repeat_char '━' "$side_len")"

    if [ "$QUIET" != "1" ]; then
        printf '\n%s%s%s%s%s\n\n' \
            "${C_BOLD}${C_CYAN}" \
            "$left" \
            "$title_text" \
            "$right" \
            "${C_RESET}"
    fi

    append_log ""
    append_log "━━ $title [$(timestamp)]"
}

end_section() {
    if [ "$QUIET" != "1" ]; then
        printf '\n'
        render_progress_bar "$CURRENT_SECTION" "$TOTAL_SECTIONS"
    fi
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
# Cleanup / lock
#######################################

cleanup() {
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
# Utility helpers
#######################################

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

homebrew_available() { command_exists brew; }
apt_available() { command_exists apt-get; }
dnf_available() { command_exists dnf; }
pacman_available() { command_exists pacman; }
cron_available() { command_exists crontab; }

brew_formula_installed() { brew list --formula "$1" >/dev/null 2>&1; }
apt_package_installed() { dpkg -s "$1" >/dev/null 2>&1; }
dnf_package_installed() { dnf list installed "$1" >/dev/null 2>&1; }
pacman_package_installed() { pacman -Q "$1" >/dev/null 2>&1; }

ensure_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        print_skip "Directory exists: $dir"
    else
        if spinner_run "Create directory: $dir" mkdir -p "$dir"; then
            CREATED_DIRS=$((CREATED_DIRS + 1))
        else
            print_error "Could not create directory: $dir"
        fi
    fi
}

backup_if_exists() {
    local target="$1"

    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ ! -e "${target}${BACKUP_SUFFIX}" ] && [ ! -L "${target}${BACKUP_SUFFIX}" ]; then
            if spinner_run "Back up $target" mv -f "$target" "${target}${BACKUP_SUFFIX}"; then
                BACKED_UP_PATHS=$((BACKED_UP_PATHS + 1))
            else
                print_error "Could not back up: $target"
                return 1
            fi
        else
            if spinner_run "Remove existing path $target" rm -rf "$target"; then
                :
            else
                print_error "Could not remove current path: $target"
                return 1
            fi
        fi
    fi
    return 0
}

link_file() {
    local source="$1"
    local target="$2"
    local optional="${3:-0}"

    if [ ! -e "$source" ]; then
        if [ "$optional" = "1" ] && [ "$STRICT_OPTIONAL_CONFIGS" != "1" ]; then
            SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
            print_skip "Optional source missing: $source"
            return 0
        fi
        SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
        print_warn "Source file missing: $source"
        return 1
    fi

    ensure_dir "$(dirname "$target")"

    if [ -L "$target" ]; then
        local current_link
        current_link="$(readlink "$target" || true)"
        if [ "$current_link" = "$source" ]; then
            SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
            print_skip "Symlink already correct: $target"
            return 0
        fi
    fi

    backup_if_exists "$target" || return 1

    if spinner_run "Link $target" ln -s "$source" "$target"; then
        LINKED_FILES=$((LINKED_FILES + 1))
        if [ "$target" = "${CONFIG_HOME}/tmux/tmux.conf" ]; then
            TMUX_CONFIG_CHANGED=1
        fi
    else
        print_error "Could not link $target -> $source"
    fi
}

#######################################
# Package managers
#######################################

install_homebrew_if_needed() {
    if [ "$PLATFORM" != "mac" ]; then
        print_skip "Not macOS; skipping Homebrew setup"
        return 0
    fi

    if homebrew_available; then
        print_skip "Homebrew already installed"
    else
        spinner_run "Install Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || print_error "Homebrew install failed"
    fi

    if homebrew_available; then
        local brew_share
        brew_share="$(brew --prefix)/share"
        if [ -d "$brew_share" ]; then
            spinner_run "Fix Homebrew permissions" chmod go-w "$brew_share" || print_warn "Could not adjust Homebrew permissions"
        fi
    fi
}

upgrade_packages() {
    if [ "$UPGRADE_PACKAGES" != "1" ]; then
        print_skip "Package upgrades disabled"
        return 0
    fi

    case "$PLATFORM" in
        mac)
            if homebrew_available; then
                spinner_run "brew update" brew update && UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + 1)) || print_warn "brew update failed"
                spinner_run "brew upgrade" brew upgrade && UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + 1)) || print_warn "brew upgrade failed"
            else
                print_warn "Homebrew unavailable; skipping upgrades"
            fi
            ;;
        linux)
            if apt_available; then
                spinner_run "apt-get update" sudo apt-get update && UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + 1)) || print_warn "apt-get update failed"
                spinner_run "apt-get upgrade" sudo apt-get upgrade -y && UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + 1)) || print_warn "apt-get upgrade failed"
            elif dnf_available; then
                spinner_run "dnf upgrade" sudo dnf upgrade -y && UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + 1)) || print_warn "dnf upgrade failed"
            elif pacman_available; then
                spinner_run "pacman -Syu" sudo pacman -Syu --noconfirm && UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + 1)) || print_warn "pacman upgrade failed"
            else
                print_warn "No supported Linux package manager found for upgrade"
            fi
            ;;
        *)
            print_skip "Package upgrade not implemented for platform: $PLATFORM"
            ;;
    esac
}

ensure_command() {
    local command_name="$1"
    local package_name="$2"

    case "$PLATFORM" in
        mac)
            if [ "$FORCE_BREW" = "1" ]; then
                if ! homebrew_available; then
                    print_warn "Homebrew unavailable; cannot force-install $package_name"
                    return 1
                fi
                if brew_formula_installed "$package_name"; then
                    SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
                    print_skip "Homebrew formula already installed: $package_name"
                else
                    if spinner_run "Install $package_name via Homebrew" brew install "$package_name"; then
                        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                        if [ "$command_name" = "gh" ]; then
                            GH_INSTALLED_THIS_RUN=1
                        fi
                    else
                        print_error "Could not install $package_name"
                    fi
                fi
                return 0
            fi

            if command_exists "$command_name"; then
                SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
                print_skip "Command available: $command_name ($(command -v "$command_name"))"
            else
                if ! homebrew_available; then
                    print_warn "Homebrew unavailable; missing command: $command_name"
                    return 1
                fi
                if spinner_run "Install missing command $package_name" brew install "$package_name"; then
                    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                    if [ "$command_name" = "gh" ]; then
                        GH_INSTALLED_THIS_RUN=1
                    fi
                else
                    print_error "Could not install missing command: $command_name"
                fi
            fi
            ;;
        linux)
            if command_exists "$command_name"; then
                SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
                print_skip "Command available: $command_name ($(command -v "$command_name"))"
                return 0
            fi

            if apt_available; then
                if spinner_run "Install $package_name via apt" sudo apt-get install -y "$package_name"; then
                    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                    [ "$command_name" = "gh" ] && GH_INSTALLED_THIS_RUN=1
                else
                    print_error "Could not install $package_name"
                fi
            elif dnf_available; then
                if spinner_run "Install $package_name via dnf" sudo dnf install -y "$package_name"; then
                    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                    [ "$command_name" = "gh" ] && GH_INSTALLED_THIS_RUN=1
                else
                    print_error "Could not install $package_name"
                fi
            elif pacman_available; then
                if spinner_run "Install $package_name via pacman" sudo pacman -S --noconfirm "$package_name"; then
                    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                    [ "$command_name" = "gh" ] && GH_INSTALLED_THIS_RUN=1
                else
                    print_error "Could not install $package_name"
                fi
            else
                print_warn "No supported package manager for missing command: $command_name"
            fi
            ;;
        *)
            print_warn "Package install not implemented for platform: $PLATFORM"
            ;;
    esac
}

remove_neofetch_if_installed() {
    case "$PLATFORM" in
        mac)
            if homebrew_available && brew_formula_installed "neofetch"; then
                spinner_run "Remove neofetch" brew uninstall neofetch && REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1)) || print_warn "Could not remove neofetch"
            else
                print_skip "neofetch not installed via Homebrew"
            fi
            ;;
        linux)
            if apt_available && apt_package_installed "neofetch"; then
                spinner_run "Remove neofetch via apt" sudo apt-get remove -y neofetch && REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1)) || print_warn "Could not remove neofetch"
            elif dnf_available && dnf_package_installed "neofetch"; then
                spinner_run "Remove neofetch via dnf" sudo dnf remove -y neofetch && REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1)) || print_warn "Could not remove neofetch"
            elif pacman_available && pacman_package_installed "neofetch"; then
                spinner_run "Remove neofetch via pacman" sudo pacman -Rns --noconfirm neofetch && REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1)) || print_warn "Could not remove neofetch"
            else
                print_skip "neofetch not installed through supported package manager"
            fi
            ;;
        *)
            print_skip "neofetch removal not implemented for platform: $PLATFORM"
            ;;
    esac
}

#######################################
# Git helpers
#######################################

get_preferred_git_path() {
    local github_desktop_git=""

    if command_exists git; then
        command -v git
        return
    fi

    if [ "$PLATFORM" = "mac" ]; then
        github_desktop_git="/Applications/GitHub Desktop.app/Contents/Resources/app/git/bin/git"
        if [ -x "$github_desktop_git" ]; then
            printf '%s\n' "$github_desktop_git"
            return
        fi
    fi

    printf '\n'
}

update_dotfiles_repo() {
    local git_bin="$1"

    if [ -z "$git_bin" ]; then
        print_warn "No git executable available; cannot pull dotfiles"
        return 1
    fi
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        print_skip "Dotfiles repo not found at $DOTFILES_DIR"
        return 0
    fi

    if spinner_run "Pull dotfiles repo" "$git_bin" -C "$DOTFILES_DIR" pull --ff-only; then
        :
    else
        print_warn "Dotfiles pull failed"
        command_exists gh && GH_NEEDS_AUTH_HINT=1
    fi
}

clone_repo_if_missing() {
    local git_bin="$1"
    local repo_url="$2"
    local target_dir="$3"
    local clone_args="${4:-}"

    if [ -d "$target_dir" ]; then
        SKIPPED_REPOS=$((SKIPPED_REPOS + 1))
        print_skip "Repo present: $target_dir"
        return 0
    fi

    ensure_dir "$(dirname "$target_dir")"

    if [ -n "$clone_args" ]; then
        if spinner_run "Clone $(basename "$repo_url")" bash -lc "\"$git_bin\" clone $clone_args \"$repo_url\" \"$target_dir\""; then
            CLONED_REPOS=$((CLONED_REPOS + 1))
        else
            print_error "Could not clone $repo_url"
        fi
    else
        if spinner_run "Clone $(basename "$repo_url")" "$git_bin" clone "$repo_url" "$target_dir"; then
            CLONED_REPOS=$((CLONED_REPOS + 1))
        else
            print_error "Could not clone $repo_url"
        fi
    fi
}

configure_git() {
    local git_bin="$1"
    if [ -n "$git_bin" ] && command_exists vim; then
        spinner_run "Set git editor to vim" "$git_bin" config --global core.editor "vim" || print_warn "Could not set git editor"
    else
        print_skip "Skipping git editor config"
    fi
}

#######################################
# Alacritty
#######################################

get_installed_alacritty_version_macos() {
    local app_bin="/Applications/Alacritty.app/Contents/MacOS/alacritty"
    if [ -x "$app_bin" ]; then
        "$app_bin" --version 2>/dev/null | awk '{print $2}'
    fi
}

install_alacritty_macos() {
    local api_url="https://api.github.com/repos/alacritty/alacritty/releases/latest"
    local tmp_dir=""
    local dmg_url=""
    local dmg_path=""
    local mount_point=""
    local app_source=""
    local latest_tag=""
    local latest_version=""
    local installed_version=""

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would check latest Alacritty GitHub release"
        print_info "[dry-run] Would compare installed version and install/update /Applications/Alacritty.app if needed"
        return 0
    fi

    print_info "Checking latest Alacritty release from GitHub"
    latest_tag="$(curl -fsSL "$api_url" 2>>"$LOG_FILE" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -z "$latest_tag" ]; then
        print_warn "Could not determine latest Alacritty release tag"
        return 1
    fi
    latest_version="${latest_tag#v}"

    dmg_url="$(curl -fsSL "$api_url" 2>>"$LOG_FILE" | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -n1)"
    if [ -z "$dmg_url" ]; then
        print_warn "Could not find Alacritty DMG asset"
        return 1
    fi

    installed_version="$(get_installed_alacritty_version_macos || true)"
    if [ -n "$installed_version" ] && [ "$installed_version" = "$latest_version" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "Alacritty already up to date: $installed_version"
        return 0
    fi

    tmp_dir="$(mktemp -d)"
    dmg_path="${tmp_dir}/alacritty.dmg"
    mount_point="${tmp_dir}/mnt"
    mkdir -p "$mount_point"

    spinner_run "Download Alacritty DMG" curl -fL "$dmg_url" -o "$dmg_path" || {
        rm -rf "$tmp_dir"
        print_error "Could not download Alacritty DMG"
        return 1
    }

    spinner_run "Mount Alacritty DMG" hdiutil attach -nobrowse -quiet -mountpoint "$mount_point" "$dmg_path" || {
        rm -rf "$tmp_dir"
        print_error "Could not mount Alacritty DMG"
        return 1
    }

    app_source="$(find "$mount_point" -maxdepth 2 -name 'Alacritty.app' -type d | head -n1)"
    if [ -z "$app_source" ]; then
        hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
        rm -rf "$tmp_dir"
        print_error "Could not find Alacritty.app in mounted DMG"
        return 1
    fi

    rm -rf "/Applications/Alacritty.app"
    spinner_run "Install Alacritty.app" ditto "$app_source" "/Applications/Alacritty.app" || {
        hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
        rm -rf "$tmp_dir"
        print_error "Could not copy Alacritty.app"
        return 1
    }

    xattr -dr com.apple.quarantine "/Applications/Alacritty.app" >>"$LOG_FILE" 2>&1 || true
    hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
    rm -rf "$tmp_dir"

    ALACRITTY_UPDATED=1
    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
    print_ok "Installed/updated Alacritty to $latest_version"
    return 0
}

install_alacritty_linux() {
    if command_exists alacritty; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "Alacritty already available: $(command -v alacritty)"
        return 0
    fi

    if apt_available; then
        spinner_run "Install Alacritty via apt" sudo apt-get install -y alacritty && INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1)) || print_error "Could not install Alacritty"
    elif dnf_available; then
        spinner_run "Install Alacritty via dnf" sudo dnf install -y alacritty && INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1)) || print_error "Could not install Alacritty"
    elif pacman_available; then
        spinner_run "Install Alacritty via pacman" sudo pacman -S --noconfirm alacritty && INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1)) || print_error "Could not install Alacritty"
    else
        print_warn "No supported package manager available to install Alacritty"
    fi
}

install_or_update_alacritty() {
    case "$PLATFORM" in
        mac) install_alacritty_macos ;;
        linux) install_alacritty_linux ;;
        windows|cygwin) print_warn "Automatic Alacritty install not implemented for Windows yet" ;;
        *) print_warn "Alacritty install not implemented for platform: $PLATFORM" ;;
    esac
}

#######################################
# Vim
#######################################

install_vim_plug() {
    local plug_path="${HOME}/.vim/autoload/plug.vim"

    if [ -f "$plug_path" ]; then
        print_skip "vim-plug already installed"
        return 0
    fi

    ensure_dir "$(dirname "$plug_path")"
    spinner_run "Install vim-plug" curl -fLo "$plug_path" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim || print_warn "Could not install vim-plug"
}

install_vim_plugins() {
    local vim_log="${HOME}/.vim/plug-install.log"

    if ! command_exists vim; then
        print_skip "vim not available"
        return 0
    fi
    if [ ! -f "${HOME}/.vimrc" ]; then
        print_skip ".vimrc not found"
        return 0
    fi
    if [ ! -f "${HOME}/.vim/autoload/plug.vim" ]; then
        print_skip "vim-plug not found"
        return 0
    fi

    ensure_dir "${HOME}/.vim"
    append_log "Vim plugin log: $vim_log"

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would run vim -N -V1${vim_log} -E -s -u ${HOME}/.vimrc '+PlugInstall --sync' '+qa!'"
        return 0
    fi

    if vim -N -V1"${vim_log}" -E -s -u "${HOME}/.vimrc" "+PlugInstall --sync" "+qa!" >>"$LOG_FILE" 2>&1; then
        print_ok "Vim plugins installed/updated"
    else
        print_warn "Vim plugin installation failed; see $vim_log"
    fi
}

#######################################
# Fonts
#######################################

install_fonts() {
    local fonts_source_dir="${DOTFILES_DIR}/fonts"
    local fonts_dest_dir=""

    if [ ! -d "$fonts_source_dir" ]; then
        print_skip "No fonts directory at $fonts_source_dir"
        return 0
    fi

    case "$PLATFORM" in
        mac) fonts_dest_dir="${HOME}/Library/Fonts" ;;
        linux) fonts_dest_dir="${HOME}/.local/share/fonts" ;;
        *)
            print_warn "Font installation not implemented for platform: $PLATFORM"
            return 1
            ;;
    esac

    ensure_dir "$fonts_dest_dir"

    local found_any=0
    while IFS= read -r -d '' font_file; do
        found_any=1
        local filename
        filename="$(basename "$font_file")"

        if [ -e "${fonts_dest_dir}/${filename}" ]; then
            SKIPPED_FONTS=$((SKIPPED_FONTS + 1))
            print_skip "Font present: ${filename}"
        else
            if spinner_run "Install font ${filename}" cp "$font_file" "${fonts_dest_dir}/${filename}"; then
                INSTALLED_FONTS=$((INSTALLED_FONTS + 1))
            else
                print_error "Could not install font: ${filename}"
            fi
        fi
    done < <(find "$fonts_source_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)

    if [ "$found_any" = "0" ]; then
        print_skip "No font files found under $fonts_source_dir"
    fi

    if [ "$PLATFORM" = "linux" ] && [ "$INSTALLED_FONTS" -gt 0 ] && command_exists fc-cache; then
        spinner_run "Refresh font cache" fc-cache -f "$fonts_dest_dir" || print_warn "Could not refresh font cache"
    fi
}

#######################################
# tmux
#######################################

install_tmux_plugins() {
    if [ -x "${HOME}/.tmux/plugins/tpm/bin/install_plugins" ]; then
        spinner_run "Install tmux plugins" "${HOME}/.tmux/plugins/tpm/bin/install_plugins" || print_warn "tmux plugin install failed"
    else
        print_skip "TPM installer not found"
    fi
}

reload_tmux_config_if_running() {
    local tmux_conf="${CONFIG_HOME}/tmux/tmux.conf"

    if [ "$SCHEDULED" = "1" ]; then
        print_skip "Scheduled mode: skipping tmux reload"
        return 0
    fi
    if ! command_exists tmux; then
        print_skip "tmux not available"
        return 0
    fi
    if ! tmux ls >/dev/null 2>&1; then
        print_skip "No tmux server running"
        return 0
    fi
    if [ ! -f "$tmux_conf" ]; then
        print_skip "tmux config not found"
        return 0
    fi

    spinner_run "Reload tmux config" tmux source-file "$tmux_conf" || print_warn "Could not reload tmux config"
}

handle_alacritty_runtime_notice() {
    if [ "$ALACRITTY_UPDATED" != "1" ]; then
        return 0
    fi
    if [ "$SCHEDULED" = "1" ]; then
        print_skip "Scheduled mode: skipping Alacritty restart notice"
        return 0
    fi
    if pgrep -x "Alacritty" >/dev/null 2>&1; then
        print_info "Alacritty was updated. Quit and reopen it to use the new version."
    fi
}

#######################################
# Scheduling
#######################################

setup_schedule_macos() {
    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist_path="${plist_dir}/com.bdw.dotfiles.install.plist"
    local script_path="${DOTFILES_DIR}/install.sh"

    ensure_dir "$plist_dir"

    if [ -f "$plist_path" ] && grep -q "<string>com.bdw.dotfiles.install</string>" "$plist_path"; then
        print_skip "launchd schedule already present"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would create launchd schedule at $plist_path"
        return 0
    fi

    cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.bdw.dotfiles.install</string>
    <key>ProgramArguments</key>
    <array>
      <string>${script_path}</string>
      <string>--scheduled</string>
      <string>--quiet</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${DOTFILES_DIR}</string>
    <key>StartCalendarInterval</key>
    <dict>
      <key>Weekday</key>
      <integer>1</integer>
      <key>Hour</key>
      <integer>0</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
  </dict>
</plist>
EOF

    if launchctl list | grep -q "com.bdw.dotfiles.install"; then
        launchctl unload "$plist_path" >>"$LOG_FILE" 2>&1 || true
    fi

    launchctl load "$plist_path" >>"$LOG_FILE" 2>&1 && print_ok "launchd schedule installed" || print_warn "Could not load launchd plist"
}

setup_schedule_linux() {
    local script_path="${DOTFILES_DIR}/install.sh"
    local cron_line="0 0 * * 1 cd \"${DOTFILES_DIR}\" && \"${script_path}\" --scheduled --quiet >> \"${LOG_FILE}\" 2>&1"
    local current_cron=""

    if ! cron_available; then
        print_warn "crontab not available; cannot set weekly schedule"
        return 1
    fi

    current_cron="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$current_cron" | grep -Fq "$script_path --scheduled --quiet"; then
        print_skip "cron schedule already present"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would install cron schedule"
        return 0
    fi

    {
        printf '%s\n' "$current_cron" | sed '/^[[:space:]]*$/d'
        printf '%s\n' "$cron_line"
    } | crontab - >>"$LOG_FILE" 2>&1 && print_ok "cron schedule installed" || print_warn "Could not install cron schedule"
}

setup_schedule() {
    if [ "$SETUP_SCHEDULE" != "1" ]; then
        print_skip "Schedule setup disabled"
        return 0
    fi

    case "$PLATFORM" in
        mac) setup_schedule_macos ;;
        linux) setup_schedule_linux ;;
        *) print_skip "Schedule setup not implemented for platform: $PLATFORM" ;;
    esac
}

#######################################
# Misc
#######################################

run_fastfetch() {
    if ! command_exists fastfetch; then
        print_skip "fastfetch not available"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would run fastfetch"
        return 0
    fi

    print_info "Running fastfetch"
    if [ "$QUIET" != "1" ]; then
        print_rule '─'
    fi
    append_log "[RUN ] fastfetch"

    if fastfetch 2>>"$LOG_FILE"; then
        if [ "$QUIET" != "1" ]; then
            print_rule '─'
        fi
        print_ok "fastfetch complete"
    else
        if [ "$QUIET" != "1" ]; then
            print_rule '─'
        fi
        print_warn "fastfetch failed"
    fi
}

#######################################
# Config declarations
#######################################

PACKAGES=(
    "git|git"
    "vim|vim"
    "tmux|tmux"
    "fastfetch|fastfetch"
    "gh|gh"
)

GIT_REPOS=(
    "https://github.com/ohmyzsh/ohmyzsh.git|${HOME}/.oh-my-zsh|"
    "https://github.com/romkatv/powerlevel10k.git|${HOME}/.oh-my-zsh/custom/themes/powerlevel10k|--depth=1"
    "https://github.com/zsh-users/zsh-syntax-highlighting.git|${HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting|"
    "https://github.com/zsh-users/zsh-completions.git|${HOME}/.oh-my-zsh/custom/plugins/zsh-completions|"
    "https://github.com/tmux-plugins/tpm.git|${HOME}/.tmux/plugins/tpm|"
)

SYMLINKS=(
    "${DOTFILES_DIR}/alacritty/alacritty.toml|${CONFIG_HOME}/alacritty/alacritty.toml|0"
    "${DOTFILES_DIR}/zsh/.zshrc|${HOME}/.zshrc|0"
    "${DOTFILES_DIR}/zsh/.p10k.zsh|${HOME}/.p10k.zsh|0"
    "${DOTFILES_DIR}/dir_colors/.dir_colors|${HOME}/.dir_colors|0"
    "${DOTFILES_DIR}/vim/.vimrc|${HOME}/.vimrc|0"
    "${DOTFILES_DIR}/fastfetch/config.conf|${CONFIG_HOME}/fastfetch/config.conf|1"
    "${DOTFILES_DIR}/tmux/tmux.conf|${CONFIG_HOME}/tmux/tmux.conf|0"
)

#######################################
# Main
#######################################

init_logging
acquire_lock

start_section "Environment"
print_info "Platform: $PLATFORM"
print_info "Dotfiles: $DOTFILES_DIR"
print_info "Config home: $CONFIG_HOME"
print_info "Log file: $LOG_FILE"
print_info "FORCE_BREW=$FORCE_BREW DRY_RUN=$DRY_RUN QUIET=$QUIET SCHEDULED=$SCHEDULED PULL_DOTFILES=$PULL_DOTFILES"
end_section

start_section "Homebrew"
install_homebrew_if_needed
end_section

start_section "Directory setup"
ensure_dir "$CONFIG_HOME"
ensure_dir "${HOME}/.tmux/plugins"
ensure_dir "${HOME}/.oh-my-zsh"
ensure_dir "${HOME}/.oh-my-zsh/custom"
ensure_dir "${HOME}/.oh-my-zsh/custom/plugins"
ensure_dir "${HOME}/.oh-my-zsh/custom/themes"
end_section

start_section "Package upgrades"
upgrade_packages
end_section

start_section "Package checks"
for package_spec in "${PACKAGES[@]}"; do
    IFS='|' read -r command_name package_name <<< "$package_spec"
    ensure_command "$command_name" "$package_name"
done
end_section

start_section "Alacritty"
install_or_update_alacritty
end_section

start_section "Git"
GIT_BIN="$(get_preferred_git_path)"
if [ -n "$GIT_BIN" ]; then
    print_ok "Using CLI git binary: $GIT_BIN"
else
    print_warn "No git executable found"
fi

if [ "$PULL_DOTFILES" = "1" ]; then
    update_dotfiles_repo "$GIT_BIN"
fi
configure_git "$GIT_BIN"
end_section

start_section "Remove neofetch"
remove_neofetch_if_installed
end_section

start_section "Cloned tools"
if [ -z "$GIT_BIN" ]; then
    print_warn "No git binary available; skipping repo clone checks"
else
    for repo_spec in "${GIT_REPOS[@]}"; do
        IFS='|' read -r repo_url target_dir clone_args <<< "$repo_spec"
        clone_repo_if_missing "$GIT_BIN" "$repo_url" "$target_dir" "$clone_args"
    done
fi
end_section

start_section "Config symlinks"
for link_spec in "${SYMLINKS[@]}"; do
    IFS='|' read -r source target optional <<< "$link_spec"
    link_file "$source" "$target" "$optional"
done
end_section

start_section "Vim"
install_vim_plug
install_vim_plugins
end_section

start_section "Fonts"
install_fonts
end_section

start_section "tmux"
install_tmux_plugins
reload_tmux_config_if_running
end_section

start_section "Scheduling"
setup_schedule
end_section

start_section "Runtime notices"
handle_alacritty_runtime_notice
end_section

start_section "fastfetch"
run_fastfetch
end_section

start_section "Summary"
print_info "Directories created  : $CREATED_DIRS"
print_info "Backups made         : $BACKED_UP_PATHS"
print_info "Symlinks created     : $LINKED_FILES"
print_info "Symlinks skipped     : $SKIPPED_LINKS"
print_info "Packages installed   : $INSTALLED_PACKAGES"
print_info "Packages upgraded    : $UPGRADED_PACKAGES"
print_info "Packages removed     : $REMOVED_PACKAGES"
print_info "Packages skipped     : $SKIPPED_PACKAGES"
print_info "Repos cloned         : $CLONED_REPOS"
print_info "Repos skipped        : $SKIPPED_REPOS"
print_info "Fonts installed      : $INSTALLED_FONTS"
print_info "Fonts skipped        : $SKIPPED_FONTS"
print_info "Warnings             : $WARNINGS"
print_info "Errors               : $ERRORS"

end_section

if [ "$GH_INSTALLED_THIS_RUN" -eq 1 ]; then
    printf '\n'
    print_info "Next steps"
    print_info "Run: gh auth login"
    print_info "Then: gh auth setup-git"
fi

if [ "$GH_NEEDS_AUTH_HINT" -eq 1 ]; then
    printf '\n'
    print_warn "Dotfiles pull failed, likely due to GitHub authentication."
    print_info "Run: gh auth setup-git"
    print_info "Then retry: ./install.sh --pull-dotfiles"
fi

printf '\n'
print_info "Log file             : $LOG_FILE"

if [ "$ERRORS" -eq 0 ]; then
    print_ok "Bootstrap complete"
else
    print_warn "Bootstrap finished with errors; see $LOG_FILE"
fi