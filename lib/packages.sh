#!/usr/bin/env bash

#######################################
# Package manager predicates
#######################################

brew_formula_installed() {
    brew list --formula "$1" >/dev/null 2>&1
}

brew_cask_installed() {
    brew list --cask "$1" >/dev/null 2>&1
}

apt_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

dnf_package_installed() {
    dnf list installed "$1" >/dev/null 2>&1
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

print_command_status_with_version() {
    local cmd="$1"
    local status_prefix="$2"
    local version=""

    if command_exists "$cmd"; then
        version="$(command_version "$cmd" || true)"
        if [ -n "$version" ]; then
            printf '%s (%s)\n' "$status_prefix" "$version"
        else
            printf '%s\n' "$status_prefix"
        fi
    else
        printf '%s\n' "$status_prefix"
    fi
}

#######################################
# Homebrew setup / upgrades
#######################################

install_homebrew_if_needed() {
    if ! is_macos; then
        print_skip "Not macOS; skipping Homebrew setup"
        mark_validated_ok
        return 0
    fi

    if homebrew_available; then
        print_skip "Homebrew already installed ($(command -v brew))"
        mark_validated_ok
        else
        if ! ensure_sudo_cached; then
            print_error "Unable to authenticate for Homebrew installation"
            mark_validated_fail
            return 1
        fi

        if spinner_run "Install Homebrew" env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            if homebrew_available; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                print_ok "Homebrew installed ($(command -v brew))"
                mark_validated_ok
            else
                print_error "Homebrew installer returned success but brew is still missing"
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

upgrade_packages() {
    if [ "$UPGRADE_PACKAGES" != "1" ]; then
        print_skip "Package upgrades disabled"
        mark_validated_ok
        return 0
    fi

    case "$PLATFORM" in
        mac)
            if homebrew_available; then
				if spinner_run "brew update" brew update; then
					mark_validated_ok
				else
					print_warn "brew update failed"
					mark_validated_fail
				fi

                local outdated_count=0
                outdated_count="$(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')"

                if [ "${outdated_count:-0}" -gt 0 ]; then
                    if spinner_run "brew upgrade" brew upgrade; then
                        local remaining
                        remaining="$(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')"
                        if [ "${remaining:-0}" -lt "$outdated_count" ]; then
                            UPGRADED_PACKAGES=$((UPGRADED_PACKAGES + outdated_count - remaining))
                            print_ok "Homebrew upgrade complete (${outdated_count} candidates, ${remaining} remaining)"
                            mark_validated_ok
                        else
                            print_error "brew upgrade ran but outdated package count did not decrease"
                            mark_validated_fail
                        fi
                    else
                        print_warn "brew upgrade failed"
                        mark_validated_fail
                    fi
                else
                    print_skip "No Homebrew packages need upgrading"
                    mark_validated_ok
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
                    mark_validated_ok
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
                            mark_validated_ok
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
                    mark_validated_ok
                fi
            elif dnf_available; then
                if spinner_run "dnf upgrade" sudo dnf upgrade -y; then
                    print_ok "dnf upgrade complete"
                    mark_validated_ok
                else
                    print_warn "dnf upgrade failed"
                    mark_validated_fail
                fi
            elif pacman_available; then
                if spinner_run "pacman -Syu" sudo pacman -Syu --noconfirm; then
                    print_ok "pacman -Syu complete"
                    mark_validated_ok
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
            mark_validated_ok
            ;;
    esac
}

#######################################
# Generic package install helpers
#######################################

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
        mark_validated_ok
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
                mark_validated_ok
                return 0
            fi

            if spinner_run "Install $package_name via Homebrew" brew install "$package_name"; then
                if verify_command_present "$command_name"; then
                    INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                    local version
                    version="$(command_version "$command_name" || true)"
                    if [ -n "$version" ]; then
                        print_ok "Installed $command_name ($version)"
                    else
                        print_ok "Installed $command_name"
                    fi

                    case "$command_name" in
                        gh) GH_INSTALLED_THIS_RUN=1 ;;
                        gpg) GPG_INSTALLED_THIS_RUN=1 ;;
                    esac
                else
                    print_error "Install reported success but command still missing: $command_name"
                fi
            else
                print_error "Failed to install $package_name"
                mark_validated_fail
            fi
            ;;
        linux)
            if apt_available; then
                if spinner_run "Install $package_name via apt" sudo apt-get install -y "$package_name"; then
                    if verify_command_present "$command_name"; then
                        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                        local version
                        version="$(command_version "$command_name" || true)"
                        if [ -n "$version" ]; then
                            print_ok "Installed $command_name ($version)"
                        else
                            print_ok "Installed $command_name"
                        fi
                        [ "$command_name" = "gpg" ] && GPG_INSTALLED_THIS_RUN=1
                    else
                        print_error "Install reported success but command still missing: $command_name"
                    fi
                else
                    print_error "Failed to install $package_name"
                    mark_validated_fail
                fi
            elif dnf_available; then
                if spinner_run "Install $package_name via dnf" sudo dnf install -y "$package_name"; then
                    if verify_command_present "$command_name"; then
                        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                        local version
                        version="$(command_version "$command_name" || true)"
                        if [ -n "$version" ]; then
                            print_ok "Installed $command_name ($version)"
                        else
                            print_ok "Installed $command_name"
                        fi
                        [ "$command_name" = "gpg" ] && GPG_INSTALLED_THIS_RUN=1
                    else
                        print_error "Install reported success but command still missing: $command_name"
                    fi
                else
                    print_error "Failed to install $package_name"
                    mark_validated_fail
                fi
            elif pacman_available; then
                if spinner_run "Install $package_name via pacman" sudo pacman -S --noconfirm "$package_name"; then
                    if verify_command_present "$command_name"; then
                        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                        local version
                        version="$(command_version "$command_name" || true)"
                        if [ -n "$version" ]; then
                            print_ok "Installed $command_name ($version)"
                        else
                            print_ok "Installed $command_name"
                        fi
                        [ "$command_name" = "gpg" ] && GPG_INSTALLED_THIS_RUN=1
                    else
                        print_error "Install reported success but command still missing: $command_name"
                    fi
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

ensure_brew_cask() {
    local cask_name="$1"
    local validation_path="$2"
    local friendly_name="$3"

    if ! is_macos; then
        print_skip "Cask install not relevant on non-macOS: $friendly_name"
        mark_validated_ok
        return 0
    fi

    if [ -e "$validation_path" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "$friendly_name already present"
        mark_validated_ok
        return 0
    fi

    if ! homebrew_available; then
        print_warn "Homebrew unavailable; cannot install cask $cask_name"
        mark_validated_fail
        return 1
    fi

    if spinner_run "Install $friendly_name via Homebrew cask" brew install --cask "$cask_name"; then
        if verify_path_exists "$validation_path"; then
            INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
            print_ok "Installed $friendly_name"
        else
            print_error "Cask install reported success but app not found: $validation_path"
        fi
    else
        print_error "Failed to install cask: $friendly_name"
        mark_validated_fail
    fi
}

#######################################
# Package removal helpers
#######################################

remove_neofetch_if_installed() {
    case "$PLATFORM" in
        mac)
            if homebrew_available && brew_formula_installed "neofetch"; then
                if spinner_run "Remove neofetch" brew uninstall neofetch; then
                    if ! brew_formula_installed "neofetch" && ! command_exists neofetch; then
                        REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1))
                        print_ok "Removed neofetch"
                        mark_validated_ok
                    else
                        print_error "neofetch uninstall reported success but neofetch is still present"
                        mark_validated_fail
                    fi
                else
                    print_warn "Could not remove neofetch"
                    mark_validated_fail
                fi
            else
                print_skip "neofetch not installed via Homebrew"
                mark_validated_ok
            fi
            ;;
        linux)
            if apt_available && apt_package_installed "neofetch"; then
                if spinner_run "Remove neofetch via apt" sudo apt-get remove -y neofetch; then
                    if ! apt_package_installed "neofetch" && ! command_exists neofetch; then
                        REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1))
                        print_ok "Removed neofetch"
                        mark_validated_ok
                    else
                        print_error "neofetch still present after apt removal"
                        mark_validated_fail
                    fi
                else
                    print_warn "Could not remove neofetch"
                    mark_validated_fail
                fi
            elif dnf_available && dnf_package_installed "neofetch"; then
                if spinner_run "Remove neofetch via dnf" sudo dnf remove -y neofetch; then
                    if ! dnf_package_installed "neofetch" && ! command_exists neofetch; then
                        REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1))
                        print_ok "Removed neofetch"
                        mark_validated_ok
                    else
                        print_error "neofetch still present after dnf removal"
                        mark_validated_fail
                    fi
                else
                    print_warn "Could not remove neofetch"
                    mark_validated_fail
                fi
            elif pacman_available && pacman_package_installed "neofetch"; then
                if spinner_run "Remove neofetch via pacman" sudo pacman -Rns --noconfirm neofetch; then
                    if ! pacman_package_installed "neofetch" && ! command_exists neofetch; then
                        REMOVED_PACKAGES=$((REMOVED_PACKAGES + 1))
                        print_ok "Removed neofetch"
                        mark_validated_ok
                    else
                        print_error "neofetch still present after pacman removal"
                        mark_validated_fail
                    fi
                else
                    print_warn "Could not remove neofetch"
                    mark_validated_fail
                fi
            else
                print_skip "neofetch not installed through supported package manager"
                mark_validated_ok
            fi
            ;;
        *)
            print_skip "neofetch removal not implemented for platform: $PLATFORM"
            mark_validated_ok
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
)