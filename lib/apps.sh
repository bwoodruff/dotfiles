#!/usr/bin/env bash

#######################################
# gpg
#######################################

app_bundle_short_version() {
    local app_path="$1"
    local plist="${app_path}/Contents/Info.plist"

    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null \
        || defaults read "${app_path}/Contents/Info" CFBundleShortVersionString 2>/dev/null \
        || true
    fi
}

gpg_has_secret_keys() {
    if ! command_exists gpg; then
        return 1
    fi

    gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'
}

#######################################
# GitHub Desktop
#######################################

GITHUB_DESKTOP_APP="/Applications/GitHub Desktop.app"

github_desktop_version() {
    app_bundle_short_version "$GITHUB_DESKTOP_APP"
}

github_desktop_download_url() {
    case "$(uname -m)" in
        arm64)
            echo "https://central.github.com/deployments/desktop/desktop/latest/darwin-arm64"
            ;;
        x86_64)
            echo "https://central.github.com/deployments/desktop/desktop/latest/darwin"
            ;;
        *)
            return 1
            ;;
    esac
}

install_github_desktop() {
    if ! is_macos; then
        print_skip "GitHub Desktop not supported on this platform"
        return 0
    fi

    if dir_exists "$GITHUB_DESKTOP_APP"; then
        print_skip "GitHub Desktop already installed ($(github_desktop_version))"
        return 0
    fi

    local url=""
    local tmp_dir=""
    local zip_path=""
    local app_path=""

    url="$(github_desktop_download_url)" || {
        print_error "Unsupported architecture for GitHub Desktop"
        mark_validated_fail
        return 1
    }

    tmp_dir="$(mktemp -d)"
    zip_path="${tmp_dir}/github-desktop.zip"

    if ! spinner_run "Download GitHub Desktop" dotfiles_curl -L -o "$zip_path" "$url"; then
        print_error "Failed to download GitHub Desktop"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    if ! spinner_run "Extract GitHub Desktop" ditto -x -k "$zip_path" "$tmp_dir"; then
        print_error "Failed to extract GitHub Desktop"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    app_path="$(find "$tmp_dir" -maxdepth 2 -type d -name "GitHub Desktop.app" -print -quit)"
    if [ -z "$app_path" ]; then
        print_error "GitHub Desktop.app not found after extraction"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    if ! spinner_run "Install GitHub Desktop" mv "$app_path" "/Applications/"; then
        print_error "Failed to move GitHub Desktop to /Applications"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    if ! clear_quarantine_if_present "$GITHUB_DESKTOP_APP"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    if dir_exists "$GITHUB_DESKTOP_APP"; then
        print_ok "GitHub Desktop installed ($(github_desktop_version))"
    else
        print_error "GitHub Desktop install did not verify"
        mark_validated_fail
    fi
}

#######################################
# Alfred (macOS)
#######################################

alfred_app_bundle_path() {
    local p=""
    for p in /Applications/Alfred\ 5.app /Applications/Alfred\ 4.app /Applications/Alfred.app; do
        if dir_exists "$p"; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

alfred_managed_by_homebrew() {
    homebrew_available && brew list --cask alfred >/dev/null 2>&1
}

install_alfred_macos() {
    if ! is_macos; then
        print_skip "Alfred is only installed on macOS"
        return 0
    fi

    if ! homebrew_available; then
        print_warn "Homebrew unavailable; cannot install Alfred"
        mark_validated_fail
        return 1
    fi

    local existing=""
    existing="$(alfred_app_bundle_path || true)"

    if [ -n "$existing" ] && alfred_managed_by_homebrew; then
        print_skip "Alfred already installed via Homebrew ($(app_bundle_short_version "$existing" || true))"
        return 0
    fi

    if [ -n "$existing" ] && [ "$FORCE_BREW" != "1" ]; then
        print_skip "Alfred found at $existing (not managed by Homebrew); skipping brew install (use --force-brew to install the Homebrew cask)"
        return 0
    fi

    local brew_args=(install --cask)
    if [ "$FORCE_BREW" = "1" ] && [ -n "$existing" ]; then
        brew_args+=(--force)
    fi
    brew_args+=(alfred)

    if spinner_run "Install Alfred via Homebrew cask" brew "${brew_args[@]}"; then
        existing="$(alfred_app_bundle_path || true)"
        if [ -z "$existing" ]; then
            print_error "Alfred cask install reported success but no Alfred.app was found in /Applications"
            mark_validated_fail
            return 1
        fi

        if ! clear_quarantine_if_present "$existing"; then
            return 1
        fi

        ALFRED_INSTALLED_THIS_RUN=1
        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        print_ok "Installed Alfred ($(app_bundle_short_version "$existing" || true))"
        return 0
    fi

    print_error "Could not install Alfred via Homebrew"
    mark_validated_fail
    return 1
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

get_installed_alacritty_version_linux() {
    if command_exists alacritty; then
        alacritty --version 2>/dev/null | awk '{print $2}'
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
    local final_version=""

    installed_version="$(get_installed_alacritty_version_macos || true)"
    if [ -n "$installed_version" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "Alacritty already installed (${installed_version})"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would check latest Alacritty GitHub release and install if missing"
        return 0
    fi

    print_info "Checking latest Alacritty release from GitHub"
    latest_tag="$(dotfiles_curl -fsSL "$api_url" 2>>"$LOG_FILE" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -z "$latest_tag" ]; then
        print_warn "Could not determine latest Alacritty release tag"
        mark_validated_fail
        return 1
    fi
    latest_version="${latest_tag#v}"

    dmg_url="$(dotfiles_curl -fsSL "$api_url" 2>>"$LOG_FILE" | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -n1)"
    if [ -z "$dmg_url" ]; then
        print_warn "Could not find Alacritty DMG asset"
        mark_validated_fail
        return 1
    fi

    tmp_dir="$(mktemp -d)"
    dmg_path="${tmp_dir}/alacritty.dmg"
    mount_point="${tmp_dir}/mnt"
    mkdir -p "$mount_point"

    if spinner_run "Download Alacritty DMG" dotfiles_curl -fL "$dmg_url" -o "$dmg_path"; then
        if ! verify_path_exists "$dmg_path"; then
            rm -rf "$tmp_dir"
            print_error "Downloaded Alacritty DMG not found"
            return 1
        fi
    else
        rm -rf "$tmp_dir"
        print_error "Could not download Alacritty DMG"
        mark_validated_fail
        return 1
    fi

    if ! spinner_run "Mount Alacritty DMG" hdiutil attach -nobrowse -quiet -mountpoint "$mount_point" "$dmg_path"; then
        rm -rf "$tmp_dir"
        print_error "Could not mount Alacritty DMG"
        mark_validated_fail
        return 1
    fi

    app_source="$(find "$mount_point" -maxdepth 2 -name 'Alacritty.app' -type d | head -n1)"
    if [ -z "$app_source" ]; then
        hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
        rm -rf "$tmp_dir"
        print_error "Could not find Alacritty.app in mounted DMG"
        mark_validated_fail
        return 1
    fi

    rm -rf "/Applications/Alacritty.app"
    if ! spinner_run "Install Alacritty.app" ditto "$app_source" "/Applications/Alacritty.app"; then
        hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
        rm -rf "$tmp_dir"
        print_error "Could not copy Alacritty.app"
        mark_validated_fail
        return 1
    fi

    hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
    rm -rf "$tmp_dir"

    if ! clear_quarantine_if_present "/Applications/Alacritty.app"; then
        return 1
    fi

    final_version="$(get_installed_alacritty_version_macos || true)"
    if [ -n "$final_version" ]; then
        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        ALACRITTY_UPDATED=1
        print_ok "Installed Alacritty (${final_version})"
        return 0
    fi

    print_error "Alacritty install reported success but app is still missing"
    mark_validated_fail
    return 1
}

install_alacritty_linux() {
    local installed_version=""
    installed_version="$(get_installed_alacritty_version_linux || true)"
    if [ -n "$installed_version" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "Alacritty already installed (${installed_version})"
        return 0
    fi

    if apt_available; then
        if spinner_run "Install Alacritty via apt" sudo apt-get install -y alacritty; then
            if verify_command_present "alacritty"; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                print_ok "Installed Alacritty ($(get_installed_alacritty_version_linux || true))"
            else
                print_error "Alacritty install reported success but command is still missing"
            fi
        else
            print_error "Could not install Alacritty"
            mark_validated_fail
        fi
    elif dnf_available; then
        if spinner_run "Install Alacritty via dnf" sudo dnf install -y alacritty; then
            if verify_command_present "alacritty"; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                print_ok "Installed Alacritty ($(get_installed_alacritty_version_linux || true))"
            else
                print_error "Alacritty install reported success but command is still missing"
            fi
        else
            print_error "Could not install Alacritty"
            mark_validated_fail
        fi
    elif pacman_available; then
        if spinner_run "Install Alacritty via pacman" sudo pacman -S --noconfirm alacritty; then
            if verify_command_present "alacritty"; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                print_ok "Installed Alacritty ($(get_installed_alacritty_version_linux || true))"
            else
                print_error "Alacritty install reported success but command is still missing"
            fi
        else
            print_error "Could not install Alacritty"
            mark_validated_fail
        fi
    else
        print_warn "No supported package manager available to install Alacritty"
        mark_validated_fail
    fi
}

install_or_update_alacritty() {
    case "$PLATFORM" in
        mac) install_alacritty_macos ;;
        linux) install_alacritty_linux ;;
        windows|cygwin)
            print_warn "Automatic Alacritty install not implemented for platform: $PLATFORM"
            mark_validated_fail
            ;;
        *)
            print_warn "Alacritty install not implemented for platform: $PLATFORM"
            mark_validated_fail
            ;;
    esac
}

#######################################
# 1Password desktop app
#######################################

ONEPASSWORD_MAC_APP="/Applications/1Password.app"
ONEPASSWORD_SAFARI_APP="/Applications/1Password for Safari.app"
# Mac App Store ADAM ID (https://apps.apple.com/app/id1569813296)
ONEPASSWORD_SAFARI_MAS_ID=1569813296

onepassword_mac_version() {
    app_bundle_short_version "$ONEPASSWORD_MAC_APP"
}

install_1password_mac_app() {
    local final_version=""

    if dir_exists "$ONEPASSWORD_MAC_APP"; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password already installed ($(onepassword_mac_version || true))"
        return 0
    fi

    if ! homebrew_available; then
        print_warn "Homebrew unavailable; cannot install 1Password for Mac"
        mark_validated_fail
        return 1
    fi

    if spinner_run "Install 1Password for Mac via Homebrew cask" brew install --cask 1password; then
        if ! verify_path_exists "$ONEPASSWORD_MAC_APP"; then
            print_error "1Password cask install reported success but app not found: $ONEPASSWORD_MAC_APP"
            return 1
        fi

        if ! clear_quarantine_if_present "$ONEPASSWORD_MAC_APP"; then
            return 1
        fi

        final_version="$(onepassword_mac_version || true)"
        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        ONEPASSWORD_INSTALLED_THIS_RUN=1

        if [ -n "$final_version" ]; then
            print_ok "Installed 1Password for Mac (${final_version})"
        else
            print_ok "Installed 1Password for Mac"
        fi
        return 0
    fi

    print_error "Could not install 1Password for Mac"
    mark_validated_fail
    return 1
}

#######################################
# 1Password Linux app
#######################################

onepassword_linux_installed() {
    command_exists 1password && return 0
    if command_exists flatpak && flatpak info com.onepassword.OnePassword &>/dev/null; then
        return 0
    fi
    return 1
}

onepassword_linux_version() {
    if command_exists 1password; then
        1password --version 2>/dev/null | awk '{print $2}'
        return 0
    fi
    if command_exists flatpak && flatpak info com.onepassword.OnePassword &>/dev/null; then
        flatpak info com.onepassword.OnePassword 2>/dev/null | awk -F': ' '$1 ~ /Version/ {print $2; exit}'
    fi
}

# apt_arch is dpkg architecture: amd64 (desktop + CLI .debs) or arm64 (CLI .deb only; desktop uses Flatpak).
ensure_1password_linux_repo_apt() {
    local apt_arch="${1:?}"
    local keyring="/usr/share/keyrings/1password-archive-keyring.gpg"
    local repo_file="/etc/apt/sources.list.d/1password.list"

    case "$apt_arch" in
        amd64|arm64) ;;
        *)
            print_error "ensure_1password_linux_repo_apt: unsupported architecture: $apt_arch"
            return 1
            ;;
    esac

    if [ ! -f "$keyring" ]; then
        if spinner_run "Install 1Password APT signing key" bash -lc \
            "curl --connect-timeout \"${DOTFILES_CURL_CONNECT_TIMEOUT_SEC:-25}\" --max-time \"${DOTFILES_CURL_MAX_TIME_SEC:-3600}\" -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o \"$keyring\""; then
            :
        else
            print_error "Could not install 1Password APT signing key"
            mark_validated_fail
            return 1
        fi
    else
        print_skip "1Password APT signing key already present"
    fi

    if [ ! -f "$repo_file" ] || ! grep -qF "linux/debian/${apt_arch}" "$repo_file" 2>/dev/null; then
        if [ -f "$repo_file" ]; then
            print_info "Rewriting 1Password APT source for ${apt_arch}"
        fi
        if spinner_run "Configure 1Password APT repository (${apt_arch})" sudo tee "$repo_file" >/dev/null <<EOF
deb [arch=${apt_arch} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${apt_arch} stable main
EOF
        then
            :
        else
            print_error "Could not configure 1Password APT repository"
            mark_validated_fail
            return 1
        fi
    else
        print_skip "1Password APT repository already configured (${apt_arch})"
    fi

    if spinner_run "apt-get update (1Password repo)" sudo apt-get update; then
        print_ok "1Password APT repository refreshed"
    else
        print_warn "Could not refresh APT after adding 1Password repo"
        mark_validated_fail
        return 1
    fi

    return 0
}

ensure_1password_linux_repo_dnf() {
    local repo_file="/etc/yum.repos.d/1password.repo"

    if [ ! -f "$repo_file" ]; then
        if spinner_run "Import 1Password RPM signing key" sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc; then
            :
        else
            print_error "Could not import 1Password RPM signing key"
            mark_validated_fail
            return 1
        fi

        if spinner_run "Configure 1Password RPM repository" sudo tee "$repo_file" >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
        then
            :
        else
            print_error "Could not configure 1Password RPM repository"
            mark_validated_fail
            return 1
        fi
    else
        print_skip "1Password RPM repository already configured"
    fi

    if spinner_run "dnf makecache (1Password repo)" sudo dnf -y makecache; then
        print_ok "1Password RPM repository refreshed"
    else
        print_warn "Could not refresh DNF metadata after adding 1Password repo"
        mark_validated_fail
        return 1
    fi

    return 0
}

# Official apt repos publish a desktop .deb for amd64 only; arm64 apt has CLI only. RPM aarch64 is CLI-only too.
# Use Flathub for the GUI when native 1password package is unavailable (per https://support.1password.com/install-linux/).
install_1password_linux_app_flatpak() {
    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would enable Flathub (user) and install com.onepassword.OnePassword"
        return 0
    fi

    if ! command_exists flatpak; then
        print_skip "1Password desktop: install Flatpak for GUI on this architecture (no native repo package); https://flathub.org/apps/com.onepassword.OnePassword"
        return 0
    fi

    if ! spinner_run "Add Flathub remote (flatpak)" flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
        print_error "Could not add Flathub remote for Flatpak"
        mark_validated_fail
        return 1
    fi

    if ! spinner_run "Install 1Password (Flatpak)" flatpak install --user -y flathub com.onepassword.OnePassword; then
        print_error "Could not install 1Password via Flatpak"
        mark_validated_fail
        return 1
    fi

    mark_1password_linux_installed
}

install_1password_linux_app() {
    if onepassword_linux_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password already installed ($(onepassword_linux_version || true))"
        return 0
    fi

    if apt_available; then
        local apt_arch=""
        apt_arch="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
        if [ "$apt_arch" = "amd64" ]; then
            ensure_1password_linux_repo_apt amd64 || return 1
            if spinner_run "Install 1Password for Linux" sudo apt-get install -y 1password; then
                mark_1password_linux_installed
            else
                print_error "Could not install 1Password for Linux"
                mark_validated_fail
            fi
        elif [ "$apt_arch" = "arm64" ]; then
            install_1password_linux_app_flatpak || return 1
        else
            print_skip "1Password desktop: unsupported APT architecture (${apt_arch}); install manually if needed"
            return 0
        fi
    elif dnf_available; then
        ensure_1password_linux_repo_dnf || return 1
        if dnf_repo_package_available "1password"; then
            if spinner_run "Install 1Password for Linux" sudo dnf install -y 1password; then
                mark_1password_linux_installed
            else
                print_error "Could not install 1Password for Linux"
                mark_validated_fail
            fi
        else
            install_1password_linux_app_flatpak || return 1
        fi
    else
        print_warn "Automatic 1Password Linux install not implemented for this distro"
        mark_validated_fail
        return 1
    fi
}

#######################################
# 1Password CLI (op)
#######################################

mark_1password_linux_installed() {
    if onepassword_linux_installed; then
        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        ONEPASSWORD_INSTALLED_THIS_RUN=1
        print_ok "Installed 1Password for Linux ($(onepassword_linux_version || true))"
    else
        print_error "1Password install reported success but command is still missing"
        mark_validated_fail
    fi
}

mark_1password_cli_installed() {
    if verify_command_present "op"; then
        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        ONEPASSWORD_CLI_INSTALLED_THIS_RUN=1
        print_ok "Installed 1Password CLI ($(onepassword_cli_version || true))"
    else
        print_error "1Password CLI install reported success but op is still missing"
    fi
}

onepassword_cli_installed() {
    command_exists op
}

onepassword_cli_version() {
    if command_exists op; then
        op --version 2>/dev/null | head -n1
    fi
}

install_1password_cli_macos() {
    local op_bin=""

    if onepassword_cli_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password CLI already installed ($(onepassword_cli_version || true))"
        return 0
    fi

    if ! homebrew_available; then
        print_warn "Homebrew unavailable; cannot install 1Password CLI"
        mark_validated_fail
        return 1
    fi

    if spinner_run "Install 1Password CLI via Homebrew" brew install --cask 1password-cli; then
        op_bin="$(command -v op 2>/dev/null || true)"
        if [ -z "$op_bin" ]; then
            print_error "1Password CLI install reported success but op is still missing"
            mark_validated_fail
            return 1
        fi

        if ! clear_quarantine_if_present "$op_bin"; then
            return 1
        fi

        mark_1password_cli_installed
    else
        print_error "Could not install 1Password CLI"
        mark_validated_fail
    fi
}

install_1password_cli_linux() {
    if onepassword_cli_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password CLI already installed ($(onepassword_cli_version || true))"
        return 0
    fi

    if apt_available; then
        local apt_arch=""
        apt_arch="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
        if [ "$apt_arch" != "amd64" ] && [ "$apt_arch" != "arm64" ]; then
            print_skip "1Password CLI: no official APT builds wired for ${apt_arch}; install op manually if needed"
            return 0
        fi
        ensure_1password_linux_repo_apt "$apt_arch" || return 1

        if spinner_run "Install 1Password CLI" sudo apt-get install -y 1password-cli; then
            mark_1password_cli_installed
        else
            print_error "Could not install 1Password CLI"
            mark_validated_fail
        fi
    elif dnf_available; then
        ensure_1password_linux_repo_dnf || return 1
        if ! dnf_repo_package_available "1password-cli"; then
            print_skip "1Password CLI RPM not in stable repo for this CPU ($(uname -m)); install op from https://developer.1password.com/docs/cli or GitHub releases"
            return 0
        fi
        if spinner_run "Install 1Password CLI" sudo dnf install -y 1password-cli; then
            mark_1password_cli_installed
        else
            print_error "Could not install 1Password CLI"
            mark_validated_fail
        fi
    else
        print_warn "Automatic 1Password CLI install not implemented for this distro"
        mark_validated_fail
        return 1
    fi
}

#######################################
# 1Password for Safari (Mac App Store via mas)
#######################################

mas_output_suggests_app_store_signin() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        return 1
    fi

    if grep -qiE \
        'sign[[:space:]]*in|not signed|apple[[:space:]]*id|authenticate|authentication|account|media[[:space:]]*&|purchases|re-?download|not available|store|password|touch[[:space:]]*id|verification failed|unable to complete|no.*logged|logged in' \
        "$log_file"
    then
        return 0
    fi

    return 1
}

install_1password_safari_via_mas() {
    if ! is_macos; then
        return 0
    fi

    if dir_exists "$ONEPASSWORD_SAFARI_APP"; then
        print_skip "1Password for Safari app is present"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would install 1Password for Safari via mas (ID $ONEPASSWORD_SAFARI_MAS_ID)"
        return 0
    fi

    if ! homebrew_available; then
        print_warn "Homebrew unavailable; cannot install 1Password for Safari via mas"
        return 0
    fi

    if ! command_exists mas; then
        print_warn "mas is not installed (it is listed in package checks on macOS as brew install mas); skipping 1Password for Safari"
        return 0
    fi

    if ! ensure_sudo_cached; then
        print_warn "Cannot cache sudo credentials; skipping mas install for 1Password for Safari"
        return 0
    fi

    sudo -v

    local mas_log=""
    mas_log="$(mktemp)"
    if spinner_run "Install 1Password for Safari (Mac App Store via mas)" \
        bash -c "set -o pipefail; sudo mas get '${ONEPASSWORD_SAFARI_MAS_ID}' >'${mas_log}' 2>&1"
    then
        if dir_exists "$ONEPASSWORD_SAFARI_APP"; then
            if ! clear_quarantine_if_present "$ONEPASSWORD_SAFARI_APP"; then
                rm -f "$mas_log"
                return 1
            fi
            ONEPASSWORD_SAFARI_INSTALLED_THIS_RUN=1
            print_ok "Installed 1Password for Safari ($(app_bundle_short_version "$ONEPASSWORD_SAFARI_APP" || true))"
            rm -f "$mas_log"
            return 0
        fi

        print_warn "mas finished but 1Password for Safari is not in /Applications yet (try again after Spotlight indexes, or install from the Mac App Store)"
        if mas_output_suggests_app_store_signin "$mas_log"; then
            MAS_APP_STORE_SIGNIN_NEXT_STEP=1
        fi
        rm -f "$mas_log"
        return 0
    fi

    print_warn "Could not install 1Password for Safari via mas"
    if mas_output_suggests_app_store_signin "$mas_log"; then
        MAS_APP_STORE_SIGNIN_NEXT_STEP=1
    fi
    rm -f "$mas_log"
    return 0
}

install_1password_stack() {
    case "$PLATFORM" in
        mac)
            install_1password_mac_app
            install_1password_safari_via_mas
            install_1password_cli_macos
            ;;
        linux)
            install_1password_linux_app
            install_1password_cli_linux
            ;;
        *)
            print_skip "1Password automation not implemented for platform: $PLATFORM"
            ;;
    esac
}

#######################################
# fastfetch
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

    if [ "$QUIET" = "1" ]; then
        if fastfetch >>"$LOG_FILE" 2>&1; then
            print_ok "fastfetch complete"
        else
            print_warn "fastfetch failed"
            mark_validated_fail
        fi
        return 0
    fi

    local ff_tmp=""
    ff_tmp="$(mktemp)"

    if fastfetch --pipe false 2>&1 | tee "$ff_tmp"; then
        rm -f "$ff_tmp"
        print_rule '─'
        print_ok "fastfetch complete"
    else
        rm -f "$ff_tmp"
        print_rule '─'
        print_warn "fastfetch failed"
        mark_validated_fail
    fi
}

#######################################
# Next-step summary helpers
#######################################

has_next_steps() {
    [ "$GH_INSTALLED_THIS_RUN" -eq 1 ] \
    || [ "$GH_NEEDS_AUTH_HINT" -eq 1 ] \
    || [ "$GPG_INSTALLED_THIS_RUN" -eq 1 ] \
    || { command_exists gpg && ! gpg_has_secret_keys; } \
    || [ "$ONEPASSWORD_INSTALLED_THIS_RUN" -eq 1 ] \
    || [ "$ONEPASSWORD_SAFARI_INSTALLED_THIS_RUN" -eq 1 ] \
    || [ "$ONEPASSWORD_CLI_INSTALLED_THIS_RUN" -eq 1 ] \
    || [ "$MAS_APP_STORE_SIGNIN_NEXT_STEP" -eq 1 ] \
    || [ "$ALFRED_INSTALLED_THIS_RUN" -eq 1 ] \
    || [ "$ALACRITTY_UPDATED" -eq 1 ] \
    || [ -n "${ZSH_VERSION:-}" ]
}

print_post_install_next_steps() {
    has_next_steps || return 0

    start_section "Next steps"

    if [ "$GH_INSTALLED_THIS_RUN" -eq 1 ] || [ "$GH_NEEDS_AUTH_HINT" -eq 1 ]; then
        print_info "GitHub CLI"
        if [ "$GH_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "Run: gh auth login"
            print_info "Then: gh auth setup-git"
        fi
        if [ "$GH_NEEDS_AUTH_HINT" -eq 1 ]; then
            print_info "Dotfiles pull failed, likely due to GitHub authentication"
            print_info "Run: gh auth setup-git"
            print_info "Then retry: ./install.sh --pull-dotfiles"
        fi
        printf '\n'
    fi

    if [ "$MAS_APP_STORE_SIGNIN_NEXT_STEP" -eq 1 ]; then
        print_info "Mac App Store"
        print_info "Open the App Store app and sign in with your Apple ID (Store menu or Account)"
        print_info "Free downloads may still require Apple ID authentication (Touch ID or password) once per app"
        print_info "Then re-run this installer if 1Password for Safari did not install"
        printf '\n'
    fi

    if [ "$ONEPASSWORD_INSTALLED_THIS_RUN" -eq 1 ] \
        || [ "$ONEPASSWORD_SAFARI_INSTALLED_THIS_RUN" -eq 1 ] \
        || [ "$ONEPASSWORD_CLI_INSTALLED_THIS_RUN" -eq 1 ]; then
        print_info "1Password"
        if [ "$ONEPASSWORD_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "Open and sign in to the 1Password desktop app"
        fi
        if [ "$ONEPASSWORD_SAFARI_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "In Safari: Settings > Extensions — enable 1Password for Safari"
        fi
        if [ "$ONEPASSWORD_CLI_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "Run: op signin"
        fi
        printf '\n'
    fi

    if [ "$ALFRED_INSTALLED_THIS_RUN" -eq 1 ]; then
        print_info "Alfred"
        print_info "Alfred Preferences > Advanced > Set preferences folder to your AlfredSync folder in iCloud Drive"
        print_info "Typical path: ~/Library/Mobile Documents/com~apple~CloudDocs/AlfredSync"
        print_info "See https://www.alfredapp.com/help/advanced/sync/ — keep Alfred.alfredpreferences downloaded (e.g. Keep Downloaded) if you use iCloud"
        print_info "System Settings > Keyboard > Keyboard Shortcuts > Spotlight: change Show Spotlight search away from Command Space (e.g. Option Space)"
        print_info "Then set Alfred’s hotkey to Command Space in Alfred Preferences > General"
        printf '\n'
    fi

    if [ "$GPG_INSTALLED_THIS_RUN" -eq 1 ] || { command_exists gpg && ! gpg_has_secret_keys; }; then
        print_info "GPG"

        if [ "$GPG_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "GPG was installed during this run"
        fi

        if command_exists gpg && ! gpg_has_secret_keys; then
            print_info "No GPG secret keys were found"
            print_info "Retrieve your GPG key material from 1Password and import it"
            print_info "Then set trust as needed"
        else
            print_info "Import or create keys, then set trust as needed"
        fi

        printf '\n'
    fi

    if [ "$ALACRITTY_UPDATED" -eq 1 ]; then
        print_info "Alacritty"
        print_info "Quit and reopen Alacritty to use the updated version"
        printf '\n'
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        print_info "Shell"
        print_info "Start a new shell session to fully apply zsh-related changes"
        printf '\n'
    fi

    if [ "$SAFARI_DEVTOOLS_NEXT_STEP" -eq 1 ]; then
        print_info "Safari"
        print_info "Enable Safari Settings > Advanced > Show features for web developers"
        printf '\n'
    fi
}