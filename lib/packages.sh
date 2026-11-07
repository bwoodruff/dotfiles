#!/usr/bin/env bash

#######################################
# Package manager predicates
#######################################

brew_formula_installed() {
    brew list --formula "$1" >/dev/null 2>&1
}

apt_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Use the RPM DB directly — avoids `dnf list installed`, which can refresh metadata,
# contend for the DNF lock, and stall long enough to feel hung (see neofetch removal checks).
dnf_package_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

# True if DNF can resolve the package from configured repos (after makecache).
# Use before `dnf install` to skip cleanly when upstream does not publish an arch (e.g. 1Password on aarch64).
#
# Important: use the same DNF state as `sudo dnf makecache` (root cache). A user `dnf repoquery`
# can trigger another metadata refresh or block on the rpm DB lock right after makecache — that
# showed up as a hang after "1Password RPM repository refreshed".  `-C` is cache-only.
dnf_repo_package_available() {
    local pkg="$1"
    local out=""
    local -a sudocmd=(sudo)

    [ -n "$pkg" ] || return 1

    if [ "${SCHEDULED:-0}" = "1" ] || [ ! -t 0 ]; then
        sudocmd=(sudo -n)
    fi

    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 120 "${sudocmd[@]}" dnf -C repoquery --quiet --available "$pkg" 2>/dev/null || true)"
    else
        out="$("${sudocmd[@]}" dnf -C repoquery --quiet --available "$pkg" 2>/dev/null || true)"
    fi

    printf '%s\n' "$out" | head -n1 | grep -q .
}

pacman_package_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

#######################################
# Version helpers
#######################################

command_version() {
    local cmd="$1"

    case "$cmd" in
        git) git --version 2>/dev/null | awk '{print $3}' ;;
        vim) vim --version 2>/dev/null | head -n1 | awk '{print $5}' ;;
        tmux) tmux -V 2>/dev/null | awk '{print $2}' ;;
        fastfetch) fastfetch --version 2>/dev/null | head -n1 | awk '{print $2}' ;;
        gh) gh --version 2>/dev/null | head -n1 | awk '{print $3}' ;;
        gpg) gpg --version 2>/dev/null | head -n1 | awk '{print $3}' ;;
        op) op --version 2>/dev/null | head -n1 | awk '{print $1}' ;;
        *) "$cmd" --version 2>/dev/null | head -n1 ;;
    esac
}

#######################################
# Homebrew setup / upgrades
#######################################

homebrew_bin_path() {
    if [ -x /opt/homebrew/bin/brew ]; then
        printf '/opt/homebrew/bin/brew\n'
    elif [ -x /usr/local/bin/brew ]; then
        printf '/usr/local/bin/brew\n'
    else
        printf '\n'
    fi
}

# Install.sh is often run from a non-login shell (e.g. Terminal) where PATH may not
# include /opt/homebrew/bin yet. Sourcing Homebrew from known locations before any
# `command -v brew` check prevents re-running the official installer.
homebrew_ensure_path() {
    local brew_bin=""
    brew_bin="$(homebrew_bin_path)"
    if [ -n "$brew_bin" ] && [ -x "$brew_bin" ]; then
        # shellcheck disable=SC1090
        eval "$("$brew_bin" shellenv)"
    fi
}

# Overrides lib/core.sh: PATH may omit brew until shellenv runs (see homebrew_ensure_path).
homebrew_available() {
    homebrew_ensure_path
    command_exists brew
}

homebrew_shellenv_rcfile() {
    case "${SHELL:-}" in
        */zsh) printf '%s/.zprofile\n' "$HOME" ;;
        */bash) printf '%s/.bash_profile\n' "$HOME" ;;
        *) printf '%s/.profile\n' "$HOME" ;;
    esac
}

ensure_homebrew_shellenv_configured() {
    local brew_bin=""
    local rcfile=""
    local shellenv_line=""

    brew_bin="$(homebrew_bin_path)"
    if [ -z "$brew_bin" ]; then
        print_error "Homebrew appears installed but brew binary was not found in a standard location"
        mark_validated_fail
        return 1
    fi

    # Make brew available immediately in this running script.
    eval "$("$brew_bin" shellenv)"

    if command_exists brew; then
        :
    else
        print_error "Failed to activate Homebrew in current shell"
        mark_validated_fail
        return 1
    fi

    rcfile="$(homebrew_shellenv_rcfile)"
    shellenv_line="eval \"\$($brew_bin shellenv)\""

    ensure_dir "$(dirname "$rcfile")" || return 1

    if [ -f "$rcfile" ] && grep -Fqx "$shellenv_line" "$rcfile"; then
        print_skip "Homebrew shellenv already configured in $rcfile"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would append Homebrew shellenv to $rcfile"
        return 0
    fi

    {
        [ -f "$rcfile" ] || : > "$rcfile"
        printf '\n%s\n' "$shellenv_line"
    } >>"$rcfile"

    if grep -Fqx "$shellenv_line" "$rcfile"; then
        print_ok "Configured Homebrew shellenv in $rcfile"
    else
        print_error "Failed to persist Homebrew shellenv in $rcfile"
        mark_validated_fail
        return 1
    fi
}

install_homebrew_if_needed() {
    if ! is_macos; then
        print_skip "Not macOS; skipping Homebrew setup"
        return 0
    fi

    if homebrew_available; then
        print_skip "Homebrew already installed ($(command -v brew))"
    else
        if ! ensure_sudo_cached; then
            print_error "Unable to authenticate for Homebrew installation"
            mark_validated_fail
            return 1
        fi

        if spinner_run "Install Homebrew" env NONINTERACTIVE=1 /bin/bash -c "$(dotfiles_curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            if ensure_homebrew_shellenv_configured && homebrew_available; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                print_ok "Homebrew installed ($(command -v brew))"
            else
                print_error "Homebrew installer returned success but brew is still unavailable"
                mark_validated_fail
            fi
        else
            print_error "Homebrew install failed"
            mark_validated_fail
        fi
    fi

    if homebrew_available; then
        local brew_share
        brew_share="$(brew --prefix)/share"

        if [ -d "$brew_share" ]; then
            if verify_permission_not_group_other_writable "$brew_share"; then
                print_skip "Homebrew permissions already correct: $brew_share"
            else
                if spinner_run "Fix Homebrew permissions" chmod go-w "$brew_share"; then
                    if verify_permission_not_group_other_writable "$brew_share"; then
                        print_ok "Homebrew permissions verified: $brew_share"
                    else
                        print_error "Homebrew permissions still not correct: $brew_share"
                    fi
                else
                    print_error "Failed to adjust Homebrew permissions"
                    mark_validated_fail
                fi
            fi
        fi
    fi
}

# Keep the tested client/firmware pair until the manual Proxmark updater is run.
ensure_proxmark_pinned() {
    PROXMARK_PIN_FAILED=0
    if ! homebrew_available || ! brew_formula_installed proxmark3; then
        print_skip "Proxmark is not installed; no pin needed"
        return 0
    fi

    local pinned=""
    if ! pinned="$(brew list --pinned 2>>"$LOG_FILE")"; then
        print_error "Unable to check Homebrew pins; package upgrades will be skipped"
        mark_validated_fail
        PROXMARK_PIN_FAILED=1
        return 1
    fi
    if printf '%s\n' "$pinned" | grep -Eq '(^|/)proxmark3$'; then
        print_skip "Proxmark is pinned for manual client/firmware updates"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would pin Proxmark for manual client/firmware updates"
        return 0
    fi
    if spinner_run "Pin Proxmark for manual updates" brew pin proxmark3; then
        if pinned="$(brew list --pinned 2>>"$LOG_FILE")" && printf '%s\n' "$pinned" | grep -Eq '(^|/)proxmark3$'; then
            print_ok "Proxmark pinned for manual client/firmware updates"
            return 0
        fi
    fi
    print_error "Unable to pin Proxmark; package upgrades will be skipped"
    mark_validated_fail
    PROXMARK_PIN_FAILED=1
    return 1
}

# Use Homebrew's existing Ruby directly; `brew ruby` enables developer mode.
# A failed or malformed query must not look like an empty upgrade list.
homebrew_upgradable_count() {
    local outdated_json="" brew_repo="" ruby_bin=""
    if ! outdated_json="$(brew outdated --json=v2 2>>"$LOG_FILE")"; then
        return 1
    fi
    if ! brew_repo="$(brew --repository 2>>"$LOG_FILE")"; then
        return 1
    fi
    ruby_bin="$brew_repo/Library/Homebrew/vendor/portable-ruby/current/bin/ruby"
    if [ ! -x "$ruby_bin" ]; then
        printf 'Homebrew portable Ruby not found: %s\n' "$ruby_bin" >>"$LOG_FILE"
        return 1
    fi
    printf '%s\n' "$outdated_json" | "$ruby_bin" -rjson -e '
        data = JSON.parse(STDIN.read)
        unless data.is_a?(Hash) && %w[formulae casks].all? { |key| data[key].is_a?(Array) }
          abort "Unexpected brew outdated JSON structure"
        end
        entries = data["formulae"] + data["casks"]
        unless entries.all? { |entry| entry.is_a?(Hash) && [true, false].include?(entry["pinned"]) }
          abort "Missing or invalid pin status in brew outdated JSON"
        end
        puts entries.count { |entry| !entry["pinned"] }
    ' 2>>"$LOG_FILE"
}

# This only loads the client; it never opens a device or reads a card.
check_proxmark_client() {
    if ! homebrew_available || ! brew_formula_installed proxmark3; then
        print_skip "Proxmark is not installed; skipping client startup check"
        return 0
    fi
    # Package checks may have installed the client after the earlier pin task.
    ensure_proxmark_pinned || return 1
    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would check Proxmark client startup without a device"
        return 0
    fi

    local brew_prefix="" client="" marker="$LOG_DIR/proxmark-client-startup.failed"
    local healthy=0 updater="${DOTFILES_DIR:-$HOME/dotfiles}/proxmark-update"
    if brew_prefix="$(brew --prefix 2>>"$LOG_FILE")"; then
        client="$brew_prefix/opt/proxmark3/bin/proxmark3"
        if [ -x "$client" ]; then
            if command -v timeout >/dev/null 2>&1; then
                if timeout 20 "$client" --incognito --version >>"$LOG_FILE" 2>&1; then
                    healthy=1
                fi
            elif "$client" --incognito --version >>"$LOG_FILE" 2>&1; then
                healthy=1
            fi
        fi
    fi
    if [ "$healthy" = "1" ]; then
        rm -f "$marker"
        print_skip "Proxmark client startup check passed"
        return 0
    fi

    print_error "Proxmark client cannot start; run $updater. See $LOG_FILE"
    mark_validated_fail
    if [ ! -f "$marker" ] && command -v osascript >/dev/null 2>&1; then
        if osascript - "$LOG_FILE" "$updater" >>"$LOG_FILE" 2>&1 <<'APPLESCRIPT'
on run argv
    display notification ("Proxmark client cannot start. Run " & item 2 of argv & "; see " & item 1 of argv) with title "Dotfiles maintenance"
end run
APPLESCRIPT
        then
            (umask 077; : > "$marker") || print_warn "Could not record the Proxmark startup notification"
        else
            print_warn "Could not send the Proxmark startup notification"
        fi
    fi
    return 1
}

upgrade_packages() {
    if [ "$UPGRADE_PACKAGES" != "1" ]; then
        print_skip "Package upgrades disabled"
        return 0
    fi

    case "$PLATFORM" in
        mac)
            if homebrew_available; then
                if [ "${PROXMARK_PIN_FAILED:-0}" = "1" ]; then
                    print_error "Skipping Homebrew upgrades because Proxmark could not be pinned"
                    return 1
                fi
                if spinner_run "brew update" brew update; then
                    :
                else
                    print_warn "brew update failed"
                    mark_validated_fail
                fi

                local outdated_count=0 remaining=0 upgrade_ok=1
                if ! outdated_count="$(homebrew_upgradable_count)"; then
                    print_error "Unable to read Homebrew upgrade candidates; skipping upgrades"
                    mark_validated_fail
                    return 1
                fi

                if [ "$outdated_count" -gt 0 ]; then
                    if spinner_run "brew upgrade" brew upgrade; then
                        :
                    else
                        upgrade_ok=0
                        print_warn "brew upgrade failed"
                        mark_validated_fail
                    fi
                    if [ "$DRY_RUN" = "1" ]; then
                        print_info "[dry-run] Would upgrade $outdated_count unpinned Homebrew packages"
                        return 0
                    fi
                    if ! remaining="$(homebrew_upgradable_count)"; then
                        print_error "Unable to verify remaining Homebrew upgrade candidates"
                        mark_validated_fail
                        return 1
                    fi
                    if [ "$remaining" -lt "$outdated_count" ]; then
                        UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + outdated_count - remaining))
                    fi
                    if [ "$upgrade_ok" = "1" ] && [ "$remaining" -eq 0 ]; then
                        print_ok "Homebrew upgrade complete ($outdated_count packages)"
                    else
                        print_error "Homebrew upgrades incomplete ($outdated_count candidates, $remaining remaining)"
                        if [ "$upgrade_ok" = "1" ]; then
                            mark_validated_fail
                        fi
                        return 1
                    fi
                else
                    print_skip "No unpinned Homebrew packages need upgrading"
                fi
            else
                print_warn "Homebrew unavailable; skipping upgrades"
                mark_validated_fail
            fi
            ;;
        linux)
            if apt_available; then
                if spinner_run "apt-get update" sudo apt-get update; then
                    print_ok "apt-get update complete"
                else
                    print_warn "apt-get update failed"
                    mark_validated_fail
                fi

                local upgrade_count=0
                upgrade_count="$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"

                if [ "${upgrade_count:-0}" -gt 0 ]; then
                    if spinner_run "apt-get upgrade" sudo apt-get upgrade -y; then
                        local remaining
                        remaining="$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
                        if [ "${remaining:-0}" -lt "$upgrade_count" ]; then
                            UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + upgrade_count - remaining))
                            print_ok "apt-get upgrade complete (${upgrade_count} candidates, ${remaining} remaining)"
                        else
                            print_error "apt-get upgrade ran but upgradable package count did not decrease"
                            mark_validated_fail
                        fi
                    else
                        print_warn "apt-get upgrade failed"
                        mark_validated_fail
                    fi
                else
                    print_skip "No apt packages need upgrading"
                fi
            elif dnf_available; then
                if spinner_run "dnf upgrade" sudo dnf upgrade -y; then
                    print_ok "dnf upgrade complete"
                else
                    print_warn "dnf upgrade failed"
                    mark_validated_fail
                fi
            elif pacman_available; then
                if spinner_run "pacman -Syu" sudo pacman -Syu --noconfirm; then
                    print_ok "pacman -Syu complete"
                else
                    print_warn "pacman upgrade failed"
                    mark_validated_fail
                fi
            else
                print_warn "No supported Linux package manager found for upgrade"
                mark_validated_fail
            fi
            ;;
        *)
            print_skip "Package upgrade not implemented for platform: $PLATFORM"
            ;;
    esac
}

#######################################
# Generic package install helpers
#######################################

mark_command_installed() {
    local command_name="$1"
    local track_gh="${2:-0}"
    local version=""

    if ! verify_command_present "$command_name"; then
        print_error "Install reported success but command still missing: $command_name"
        return 1
    fi

    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
    version="$(command_version "$command_name" || true)"
    if [ -n "$version" ]; then
        print_ok "Installed $command_name ($version)"
    else
        print_ok "Installed $command_name"
    fi

    [ "$command_name" = "gpg" ] && GPG_INSTALLED_THIS_RUN=1
    if [ "$track_gh" = "1" ] && [ "$command_name" = "gh" ]; then
        GH_INSTALLED_THIS_RUN=1
    fi

    return 0
}

ensure_command() {
    local command_name="$1"
    local package_name="$2"

    if command_exists "$command_name" && [ "$FORCE_BREW" != "1" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        local version
        version="$(command_version "$command_name" || true)"
        if [ -n "$version" ]; then
            print_skip "Command available: $command_name ($(command -v "$command_name"), $version)"
        else
            print_skip "Command available: $command_name ($(command -v "$command_name"))"
        fi
        return 0
    fi

    if [ "$package_name" = "mas" ] && [ "$PLATFORM" != "mac" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "mas (Mac App Store CLI) is only installed on macOS"
        return 0
    fi

    case "$PLATFORM" in
        mac)
            if ! homebrew_available; then
                print_warn "Homebrew unavailable; cannot install $package_name"
                mark_validated_fail
                return 1
            fi

            if [ "$FORCE_BREW" = "1" ] && brew_formula_installed "$package_name"; then
                SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
                print_skip "Homebrew formula already installed: $package_name"
                return 0
            fi

            if spinner_run "Install $package_name via Homebrew" brew install "$package_name"; then
                mark_command_installed "$command_name" "1"
            else
                print_error "Failed to install $package_name"
                mark_validated_fail
            fi
            ;;
        linux)
            if apt_available; then
                if spinner_run "Install $package_name via apt" sudo apt-get install -y "$package_name"; then
                    mark_command_installed "$command_name"
                else
                    print_error "Failed to install $package_name"
                    mark_validated_fail
                fi
            elif dnf_available; then
                if spinner_run "Install $package_name via dnf" sudo dnf install -y "$package_name"; then
                    mark_command_installed "$command_name"
                else
                    print_error "Failed to install $package_name"
                    mark_validated_fail
                fi
            elif pacman_available; then
                if spinner_run "Install $package_name via pacman" sudo pacman -S --noconfirm "$package_name"; then
                    mark_command_installed "$command_name"
                else
                    print_error "Failed to install $package_name"
                    mark_validated_fail
                fi
            else
                print_warn "No supported package manager available for $package_name"
                mark_validated_fail
            fi
            ;;
        *)
            print_warn "Package install not implemented for platform: $PLATFORM"
            mark_validated_fail
            ;;
    esac
}

#######################################
# Package removal helpers
#######################################

confirm_neofetch_removed() {
    local still_installed_fn="$1"
    local failure_message="$2"

    if ! "$still_installed_fn" "neofetch" && ! command_exists neofetch; then
        REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1))
        print_ok "Removed neofetch"
        return 0
    fi

    print_error "$failure_message"
    mark_validated_fail
    return 1
}

remove_neofetch_via() {
    local description="$1"
    local still_installed_fn="$2"
    local failure_message="$3"
    shift 3

    if spinner_run "$description" "$@"; then
        confirm_neofetch_removed "$still_installed_fn" "$failure_message"
    else
        print_warn "Could not remove neofetch"
        mark_validated_fail
        return 1
    fi
}

remove_neofetch_if_installed() {
    case "$PLATFORM" in
        mac)
            if ! command_exists neofetch && ! { homebrew_available && brew_formula_installed "neofetch"; }; then
                print_skip "neofetch not installed"
                return 0
            fi
            if homebrew_available && brew_formula_installed "neofetch"; then
                remove_neofetch_via \
                    "Remove neofetch" \
                    "brew_formula_installed" \
                    "neofetch uninstall reported success but neofetch is still present" \
                    brew uninstall neofetch
            else
                print_skip "neofetch not installed via Homebrew"
            fi
            ;;
        linux)
            if ! command_exists neofetch; then
                print_skip "neofetch not installed (not on PATH)"
                return 0
            fi
            if apt_available && apt_package_installed "neofetch"; then
                remove_neofetch_via \
                    "Remove neofetch via apt" \
                    "apt_package_installed" \
                    "neofetch still present after apt removal" \
                    sudo apt-get remove -y neofetch
            elif dnf_available && dnf_package_installed "neofetch"; then
                remove_neofetch_via \
                    "Remove neofetch via dnf" \
                    "dnf_package_installed" \
                    "neofetch still present after dnf removal" \
                    sudo dnf remove -y neofetch
            elif pacman_available && pacman_package_installed "neofetch"; then
                remove_neofetch_via \
                    "Remove neofetch via pacman" \
                    "pacman_package_installed" \
                    "neofetch still present after pacman removal" \
                    sudo pacman -Rns --noconfirm neofetch
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
# Declared packages
#######################################

PACKAGES=(
    "git|git"
    "vim|vim"
    "tmux|tmux"
    "fastfetch|fastfetch"
    "gh|gh"
    "gpg|gnupg"
    "mas|mas"
)