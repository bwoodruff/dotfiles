#!/usr/bin/env bash

set -euo pipefail

#######################################
# User-tunable behavior
#######################################

# Default behavior:
# - install missing commands
# - do NOT replace existing commands just because Homebrew has them
# Optional override:
# - FORCE_BREW=1 will install listed formulas via Homebrew even if a command already exists
FORCE_BREW="${FORCE_BREW:-0}"

# Print commands without executing them
DRY_RUN="${DRY_RUN:-0}"

# If 1, missing optional config files are warnings instead of normal skips
STRICT_OPTIONAL_CONFIGS="${STRICT_OPTIONAL_CONFIGS:-0}"

#######################################
# Basic paths
#######################################

DOTFILES_DIR="${HOME}/dotfiles"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_SUFFIX=".old"

#######################################
# Counters / summary
#######################################

CREATED_DIRS=0
BACKED_UP_PATHS=0
LINKED_FILES=0
SKIPPED_LINKS=0
INSTALLED_PACKAGES=0
SKIPPED_PACKAGES=0
CLONED_REPOS=0
SKIPPED_REPOS=0
INSTALLED_FONTS=0
SKIPPED_FONTS=0
WARNINGS=0

#######################################
# Logging helpers
#######################################

log() {
    printf '\n==> %s\n' "$1"
}

info() {
    printf '%s\n' "$1"
}

warn() {
    WARNINGS=$((WARNINGS + 1))
    printf 'WARNING: %s\n' "$1" >&2
}

#######################################
# Command runner
#######################################

run_cmd() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '[dry-run] '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

#######################################
# OS detection
#######################################

uname_out="$(uname -s)"
case "${uname_out}" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="mac" ;;
    CYGWIN*)  PLATFORM="cygwin" ;;
    MINGW*|MSYS*) PLATFORM="windows" ;;
    *)        PLATFORM="unknown" ;;
esac

#######################################
# Utility helpers
#######################################

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
    local dir="$1"

    if [ -d "$dir" ]; then
        info "Directory exists; skipping: $dir"
    else
        info "Creating directory: $dir"
        run_cmd mkdir -p "$dir"
        CREATED_DIRS=$((CREATED_DIRS + 1))
    fi
}

backup_if_exists() {
    local target="$1"

    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ ! -e "${target}${BACKUP_SUFFIX}" ] && [ ! -L "${target}${BACKUP_SUFFIX}" ]; then
            info "Backing up existing path: $target -> ${target}${BACKUP_SUFFIX}"
            run_cmd mv -f "$target" "${target}${BACKUP_SUFFIX}"
            BACKED_UP_PATHS=$((BACKED_UP_PATHS + 1))
        else
            info "Backup already exists; removing current path: $target"
            run_cmd rm -rf "$target"
        fi
    else
        info "No existing path found; no backup needed: $target"
    fi
}

link_file() {
    local source="$1"
    local target="$2"
    local optional="${3:-0}"

    if [ ! -e "$source" ]; then
        if [ "$optional" = "1" ] && [ "$STRICT_OPTIONAL_CONFIGS" != "1" ]; then
            info "Optional source missing; skipping link: $source"
            SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
            return
        fi

        warn "Source file missing; skipping link: $source"
        SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
        return
    fi

    ensure_dir "$(dirname "$target")"

    if [ -L "$target" ]; then
        local current_link
        current_link="$(readlink "$target" || true)"
        if [ "$current_link" = "$source" ]; then
            info "Symlink already correct; skipping: $target -> $source"
            SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
            return
        fi
    fi

    backup_if_exists "$target"
    info "Linking: $target -> $source"
    run_cmd ln -s "$source" "$target"
    LINKED_FILES=$((LINKED_FILES + 1))
}

#######################################
# Homebrew helpers
#######################################

homebrew_available() {
    command_exists brew
}

install_homebrew_if_needed() {
    if [ "$PLATFORM" != "mac" ]; then
        info "Not on macOS; skipping Homebrew setup"
        return
    fi

    if homebrew_available; then
        info "Homebrew already installed; skipping"
    else
        info "Homebrew not installed; installing"
        run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    if homebrew_available; then
        local brew_share
        brew_share="$(brew --prefix)/share"
        if [ -d "$brew_share" ]; then
            info "Fixing Homebrew share permissions: $brew_share"
            run_cmd chmod go-w "$brew_share" || true
        fi
    fi
}

brew_formula_installed() {
    brew list --formula "$1" >/dev/null 2>&1
}

ensure_command() {
    local command_name="$1"
    local formula_name="$2"

    if [ "$PLATFORM" = "mac" ]; then
        if [ "$FORCE_BREW" = "1" ]; then
            if ! homebrew_available; then
                warn "Homebrew unavailable; cannot force-install $formula_name"
                return
            fi

            if brew_formula_installed "$formula_name"; then
                info "Homebrew formula already installed; skipping: $formula_name"
                SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
            else
                info "FORCE_BREW=1, installing via Homebrew: $formula_name"
                run_cmd brew install "$formula_name"
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
            fi
            return
        fi

        if command_exists "$command_name"; then
            info "Command already available; skipping install: $command_name ($(command -v "$command_name"))"
            SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        else
            if ! homebrew_available; then
                warn "Homebrew unavailable; cannot install missing command: $command_name"
                return
            fi

            info "Command missing; installing via Homebrew: $formula_name"
            run_cmd brew install "$formula_name"
            INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        fi
        return
    fi

    if [ "$PLATFORM" = "linux" ]; then
        if command_exists "$command_name"; then
            info "Command already available; skipping install: $command_name ($(command -v "$command_name"))"
            SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
            return
        fi

        if command_exists apt-get; then
            info "Command missing; installing via apt: $formula_name"
            run_cmd sudo apt-get install -y "$formula_name"
            INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        else
            warn "No supported package manager configured for missing command: $command_name"
        fi
        return
    fi

    warn "Package installation not implemented for platform: $PLATFORM"
}

#######################################
# Git detection / preference
#######################################

get_preferred_git_path() {
    local github_desktop_git=""

    if [ "$PLATFORM" = "mac" ]; then
        github_desktop_git="/Applications/GitHub Desktop.app/Contents/Resources/app/git/bin/git"
        if [ -x "$github_desktop_git" ]; then
            printf '%s\n' "$github_desktop_git"
            return
        fi
    fi

    if command_exists git; then
        command -v git
        return
    fi

    printf '\n'
}

#######################################
# Git clone helpers
#######################################

clone_repo_if_missing() {
    local git_bin="$1"
    local repo_url="$2"
    local target_dir="$3"
    local clone_args="${4:-}"

    if [ -d "$target_dir" ]; then
        info "Repo already present; skipping: $target_dir"
        SKIPPED_REPOS=$((SKIPPED_REPOS + 1))
        return
    fi

    ensure_dir "$(dirname "$target_dir")"
    info "Cloning repo: $repo_url -> $target_dir"

    if [ -n "$clone_args" ]; then
        # shellcheck disable=SC2086
        run_cmd "$git_bin" clone $clone_args "$repo_url" "$target_dir"
    else
        run_cmd "$git_bin" clone "$repo_url" "$target_dir"
    fi

    CLONED_REPOS=$((CLONED_REPOS + 1))
}

#######################################
# Fonts
#######################################

install_fonts() {
    local fonts_source_dir="${DOTFILES_DIR}/fonts"
    local fonts_dest_dir=""

    if [ ! -d "$fonts_source_dir" ]; then
        info "No fonts directory found; skipping: $fonts_source_dir"
        return
    fi

    case "$PLATFORM" in
        mac)
            fonts_dest_dir="${HOME}/Library/Fonts"
            ;;
        linux)
            fonts_dest_dir="${HOME}/.local/share/fonts"
            ;;
        windows|cygwin)
            warn "Automatic font installation is not implemented for this Windows-like environment"
            return
            ;;
        *)
            warn "Unknown platform; skipping font installation"
            return
            ;;
    esac

    ensure_dir "$fonts_dest_dir"

    local found_any=0

    while IFS= read -r -d '' font_file; do
        found_any=1
        local filename
        filename="$(basename "$font_file")"

        if [ -e "${fonts_dest_dir}/${filename}" ]; then
            info "Font already present; skipping: ${filename}"
            SKIPPED_FONTS=$((SKIPPED_FONTS + 1))
        else
            info "Installing font: ${filename}"
            run_cmd cp "$font_file" "${fonts_dest_dir}/${filename}"
            INSTALLED_FONTS=$((INSTALLED_FONTS + 1))
        fi
    done < <(find "$fonts_source_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)

    if [ "$found_any" = "0" ]; then
        info "No font files found under: $fonts_source_dir"
    fi

    if [ "$PLATFORM" = "linux" ] && [ "$INSTALLED_FONTS" -gt 0 ]; then
        if command_exists fc-cache; then
            info "Refreshing font cache"
            run_cmd fc-cache -f "$fonts_dest_dir"
        else
            warn "fc-cache not found; fonts may not appear immediately"
        fi
    fi
}

#######################################
# Configuration declarations
#######################################

# Each package entry is: "command_name|package_name"
PACKAGES=(
    "git|git"
    "vim|vim"
    "tmux|tmux"
    "fastfetch|fastfetch"
)

# Each repo entry is: "url|target_dir|extra_clone_args"
GIT_REPOS=(
    "https://github.com/ohmyzsh/ohmyzsh.git|${HOME}/.oh-my-zsh|"
    "https://github.com/romkatv/powerlevel10k.git|${HOME}/.oh-my-zsh/custom/themes/powerlevel10k|--depth=1"
    "https://github.com/zsh-users/zsh-syntax-highlighting.git|${HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting|"
    "https://github.com/zsh-users/zsh-completions.git|${HOME}/.oh-my-zsh/custom/plugins/zsh-completions|"
    "https://github.com/tmux-plugins/tpm.git|${HOME}/.tmux/plugins/tpm|"
)

# Each symlink entry is: "source|target|optional"
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

log "Platform"
info "Detected platform: ${PLATFORM}"
info "Dotfiles directory: ${DOTFILES_DIR}"
info "Config home: ${CONFIG_HOME}"
info "FORCE_BREW: ${FORCE_BREW}"
info "DRY_RUN: ${DRY_RUN}"

log "Homebrew"
install_homebrew_if_needed

log "Directory setup"
ensure_dir "$CONFIG_HOME"
ensure_dir "${HOME}/.tmux/plugins"
ensure_dir "${HOME}/.oh-my-zsh"
ensure_dir "${HOME}/.oh-my-zsh/custom"
ensure_dir "${HOME}/.oh-my-zsh/custom/plugins"
ensure_dir "${HOME}/.oh-my-zsh/custom/themes"

log "Package checks"
for package_spec in "${PACKAGES[@]}"; do
    IFS='|' read -r command_name package_name <<< "$package_spec"
    ensure_command "$command_name" "$package_name"
done

log "Preferred git"
GIT_BIN="$(get_preferred_git_path)"
if [ -n "$GIT_BIN" ]; then
    info "Using git binary: $GIT_BIN"
else
    info "No git executable found"
fi

log "Git-cloned tools/plugins"
if [ -z "$GIT_BIN" ]; then
    warn "No git executable available; cannot clone repos"
else
    for repo_spec in "${GIT_REPOS[@]}"; do
        IFS='|' read -r repo_url target_dir clone_args <<< "$repo_spec"
        clone_repo_if_missing "$GIT_BIN" "$repo_url" "$target_dir" "$clone_args"
    done
fi

log "Config symlinks"
for link_spec in "${SYMLINKS[@]}"; do
    IFS='|' read -r source target optional <<< "$link_spec"
    link_file "$source" "$target" "$optional"
done

log "Fonts"
install_fonts

log "Git configuration"
if [ -n "$GIT_BIN" ] && command_exists vim; then
    info "Setting global git editor to vim using: $GIT_BIN"
    run_cmd "$GIT_BIN" config --global core.editor "vim"
else
    info "Skipping git editor configuration; git and/or vim unavailable"
fi

log "tmux plugins"
if [ -x "${HOME}/.tmux/plugins/tpm/bin/install_plugins" ]; then
    info "Installing tmux plugins from config"
    run_cmd "${HOME}/.tmux/plugins/tpm/bin/install_plugins"
else
    info "TPM installer not found; skipping tmux plugin installation"
fi

log "fastfetch"
if command_exists fastfetch; then
    info "Running fastfetch"
    run_cmd fastfetch
else
    info "fastfetch not available; skipping"
fi

log "Summary"
info "Directories created:   ${CREATED_DIRS}"
info "Backups made:          ${BACKED_UP_PATHS}"
info "Symlinks created:      ${LINKED_FILES}"
info "Symlinks skipped:      ${SKIPPED_LINKS}"
info "Packages installed:    ${INSTALLED_PACKAGES}"
info "Packages skipped:      ${SKIPPED_PACKAGES}"
info "Repos cloned:          ${CLONED_REPOS}"
info "Repos skipped:         ${SKIPPED_REPOS}"
info "Fonts installed:       ${INSTALLED_FONTS}"
info "Fonts skipped:         ${SKIPPED_FONTS}"
info "Warnings:              ${WARNINGS}"

log "Done"
info "Bootstrap complete"