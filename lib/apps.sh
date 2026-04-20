#!/usr/bin/env bash

#######################################
# gpg
#######################################

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

github_desktop_installed() {
    [ -d "$GITHUB_DESKTOP_APP" ]
}

github_desktop_version() {
    local plist="${GITHUB_DESKTOP_APP}/Contents/Info.plist"

    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null \
        || defaults read "${GITHUB_DESKTOP_APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null \
        || true
    fi
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
        mark_validated_ok
        return 0
    fi

    if github_desktop_installed; then
        print_skip "GitHub Desktop already installed ($(github_desktop_version))"
        mark_validated_ok
        return 0
    fi

    local url
    url="$(github_desktop_download_url)" || {
        print_error "Unsupported architecture for GitHub Desktop"
        mark_validated_fail
        return 1
    }

    local tmp_dir zip_path app_path
    tmp_dir="$(mktemp -d)"
    zip_path="${tmp_dir}/github-desktop.zip"

    # Download
    if ! spinner_run "Download GitHub Desktop" curl -L -o "$zip_path" "$url"; then
        print_error "Failed to download GitHub Desktop"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    # Unzip
    if ! spinner_run "Extract GitHub Desktop" unzip -q "$zip_path" -d "$tmp_dir"; then
        print_error "Failed to extract GitHub Desktop"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    # Locate .app
    app_path="$(find "$tmp_dir" -maxdepth 2 -type d -name "GitHub Desktop.app" -print -quit)"

    if [ -z "$app_path" ]; then
        print_error "GitHub Desktop.app not found after extraction"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    # Move to /Applications
    if spinner_run "Install GitHub Desktop" mv "$app_path" "/Applications/"; then
        :
    else
        print_error "Failed to move GitHub Desktop to /Applications"
        rm -rf "$tmp_dir"
        mark_validated_fail
        return 1
    fi

    # Remove quarantine (important)
    xattr -dr com.apple.quarantine "$GITHUB_DESKTOP_APP" 2>/dev/null || true

    # Cleanup
    rm -rf "$tmp_dir"

    # Verify
    if github_desktop_installed; then
        print_ok "GitHub Desktop installed ($(github_desktop_version))"
        mark_validated_ok
    else
        print_error "GitHub Desktop install did not verify"
        mark_validated_fail
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
    local quarantine_attr="com.apple.quarantine"

    installed_version="$(get_installed_alacritty_version_macos || true)"
    if [ -n "$installed_version" ]; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "Alacritty already installed (${installed_version})"
        mark_validated_ok
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would check latest Alacritty GitHub release and install if missing"
        mark_validated_ok
        return 0
    fi

    print_info "Checking latest Alacritty release from GitHub"
    latest_tag="$(curl -fsSL "$api_url" 2>>"$LOG_FILE" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -z "$latest_tag" ]; then
        print_warn "Could not determine latest Alacritty release tag"
        mark_validated_fail
        return 1
    fi
    latest_version="${latest_tag#v}"

    dmg_url="$(curl -fsSL "$api_url" 2>>"$LOG_FILE" | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -n1)"
    if [ -z "$dmg_url" ]; then
        print_warn "Could not find Alacritty DMG asset"
        mark_validated_fail
        return 1
    fi

    tmp_dir="$(mktemp -d)"
    dmg_path="${tmp_dir}/alacritty.dmg"
    mount_point="${tmp_dir}/mnt"
    mkdir -p "$mount_point"

    if spinner_run "Download Alacritty DMG" curl -fL "$dmg_url" -o "$dmg_path"; then
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

    if spinner_run "Mount Alacritty DMG" hdiutil attach -nobrowse -quiet -mountpoint "$mount_point" "$dmg_path"; then
        :
    else
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
    if spinner_run "Install Alacritty.app" ditto "$app_source" "/Applications/Alacritty.app"; then
        :
    else
        hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
        rm -rf "$tmp_dir"
        print_error "Could not copy Alacritty.app"
        mark_validated_fail
        return 1
    fi

    xattr -dr "$quarantine_attr" "/Applications/Alacritty.app" >>"$LOG_FILE" 2>&1 || true
    hdiutil detach -quiet "$mount_point" >>"$LOG_FILE" 2>&1 || true
    rm -rf "$tmp_dir"

    local final_version=""
    final_version="$(get_installed_alacritty_version_macos || true)"
    if [ -n "$final_version" ]; then
        if verify_xattr_absent "/Applications/Alacritty.app" "$quarantine_attr"; then
            :
        else
            print_warn "Alacritty installed but quarantine attribute may still be present"
        fi
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
        mark_validated_ok
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
ONEPASSWORD_MAC_DOWNLOAD_URL="https://downloads.1password.com/mac/1Password.zip"

onepassword_mac_installed() {
    [ -d "$ONEPASSWORD_MAC_APP" ]
}

onepassword_safari_app_present() {
    [ -d "$ONEPASSWORD_SAFARI_APP" ]
}

onepassword_mac_version() {
    local plist="${ONEPASSWORD_MAC_APP}/Contents/Info.plist"

    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null \
        || defaults read "${ONEPASSWORD_MAC_APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null \
        || true
    fi
}

install_1password_mac_app() {
    local tmp_dir=""
    local zip_path=""
    local extracted_app=""
    local final_version=""
    local quarantine_attr="com.apple.quarantine"

    if onepassword_mac_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password already installed ($(onepassword_mac_version || true))"
        mark_validated_ok
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would download and install 1Password for Mac"
        mark_validated_ok
        return 0
    fi

    tmp_dir="$(mktemp -d)"
    zip_path="${tmp_dir}/1Password.zip"

    if spinner_run "Download 1Password for Mac" curl -fL "$ONEPASSWORD_MAC_DOWNLOAD_URL" -o "$zip_path"; then
        if ! verify_path_exists "$zip_path"; then
            rm -rf "$tmp_dir"
            print_error "Downloaded 1Password archive not found"
            return 1
        fi
    else
        rm -rf "$tmp_dir"
        print_error "Could not download 1Password for Mac"
        mark_validated_fail
        return 1
    fi

    if spinner_run "Extract 1Password for Mac" ditto -x -k "$zip_path" "$tmp_dir"; then
        :
    else
        rm -rf "$tmp_dir"
        print_error "Could not extract 1Password for Mac"
        mark_validated_fail
        return 1
    fi

    extracted_app="$(find "$tmp_dir" -maxdepth 3 -name '1Password.app' -type d | head -n1)"
    if [ -z "$extracted_app" ]; then
        rm -rf "$tmp_dir"
        print_error "Could not find 1Password.app after extraction"
        mark_validated_fail
        return 1
    fi

    rm -rf "$ONEPASSWORD_MAC_APP"
    if spinner_run "Install 1Password for Mac" ditto "$extracted_app" "$ONEPASSWORD_MAC_APP"; then
        :
    else
        rm -rf "$tmp_dir"
        print_error "Could not install 1Password for Mac"
        mark_validated_fail
        return 1
    fi

    xattr -dr "$quarantine_attr" "$ONEPASSWORD_MAC_APP" >>"$LOG_FILE" 2>&1 || true
    rm -rf "$tmp_dir"

    if onepassword_mac_installed; then
        final_version="$(onepassword_mac_version || true)"
        if verify_xattr_absent "$ONEPASSWORD_MAC_APP" "$quarantine_attr"; then
            :
        else
            print_warn "1Password installed but quarantine attribute may still be present"
        fi
        INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        ONEPASSWORD_INSTALLED_THIS_RUN=1
        if [ -n "$final_version" ]; then
            print_ok "Installed 1Password for Mac (${final_version})"
        else
            print_ok "Installed 1Password for Mac"
        fi
        return 0
    fi

    print_error "1Password install reported success but app is still missing"
    mark_validated_fail
    return 1
}

#######################################
# 1Password Linux app
#######################################

onepassword_linux_installed() {
    command_exists 1password
}

onepassword_linux_version() {
    if command_exists 1password; then
        1password --version 2>/dev/null | awk '{print $2}'
    fi
}

ensure_1password_linux_repo_apt() {
    local keyring="/usr/share/keyrings/1password-archive-keyring.gpg"
    local repo_file="/etc/apt/sources.list.d/1password.list"

    if [ ! -f "$keyring" ]; then
        if spinner_run "Install 1Password APT signing key" bash -lc \
            "curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o $keyring"; then
            :
        else
            print_error "Could not install 1Password APT signing key"
            mark_validated_fail
            return 1
        fi
    else
        print_skip "1Password APT signing key already present"
        mark_validated_ok
    fi

    if [ ! -f "$repo_file" ]; then
        if spinner_run "Configure 1Password APT repository" sudo tee "$repo_file" >/dev/null <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main
EOF
        then
            :
        else
            print_error "Could not configure 1Password APT repository"
            mark_validated_fail
            return 1
        fi
    else
        print_skip "1Password APT repository already configured"
        mark_validated_ok
    fi

    if spinner_run "apt-get update (1Password repo)" sudo apt-get update; then
        print_ok "1Password APT repository refreshed"
        mark_validated_ok
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
        mark_validated_ok
    fi

    if spinner_run "dnf makecache (1Password repo)" sudo dnf makecache; then
        print_ok "1Password RPM repository refreshed"
        mark_validated_ok
    else
        print_warn "Could not refresh DNF metadata after adding 1Password repo"
        mark_validated_fail
        return 1
    fi

    return 0
}

install_1password_linux_app() {
    if onepassword_linux_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password already installed ($(onepassword_linux_version || true))"
        mark_validated_ok
        return 0
    fi

    if apt_available; then
        ensure_1password_linux_repo_apt || return 1
        if spinner_run "Install 1Password for Linux" sudo apt-get install -y 1password; then
            if onepassword_linux_installed; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                ONEPASSWORD_INSTALLED_THIS_RUN=1
                print_ok "Installed 1Password for Linux ($(onepassword_linux_version || true))"
                mark_validated_ok
            else
                print_error "1Password install reported success but command is still missing"
                mark_validated_fail
            fi
        else
            print_error "Could not install 1Password for Linux"
            mark_validated_fail
        fi
    elif dnf_available; then
        ensure_1password_linux_repo_dnf || return 1
        if spinner_run "Install 1Password for Linux" sudo dnf install -y 1password; then
            if onepassword_linux_installed; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                ONEPASSWORD_INSTALLED_THIS_RUN=1
                print_ok "Installed 1Password for Linux ($(onepassword_linux_version || true))"
                mark_validated_ok
            else
                print_error "1Password install reported success but command is still missing"
                mark_validated_fail
            fi
        else
            print_error "Could not install 1Password for Linux"
            mark_validated_fail
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
    local quarantine_attr="com.apple.quarantine"

    if onepassword_cli_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password CLI already installed ($(onepassword_cli_version || true))"
        mark_validated_ok
        return 0
    fi

    if ! homebrew_available; then
        print_warn "Homebrew unavailable; cannot install 1Password CLI"
        mark_validated_fail
        return 1
    fi

    if spinner_run "Install 1Password CLI via Homebrew" brew install --cask 1password-cli; then
        if verify_command_present "op"; then
            op_bin="$(command -v op)"
            xattr -d "$quarantine_attr" "$op_bin" >/dev/null 2>&1 || true

            if verify_xattr_absent "$op_bin" "$quarantine_attr"; then
                :
            else
                print_warn "1Password CLI installed but quarantine attribute may still be present"
            fi

            INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
            ONEPASSWORD_CLI_INSTALLED_THIS_RUN=1
            print_ok "Installed 1Password CLI ($(onepassword_cli_version || true))"
        else
            print_error "1Password CLI install reported success but op is still missing"
        fi
    else
        print_error "Could not install 1Password CLI"
        mark_validated_fail
    fi
}

install_1password_cli_linux() {
    if onepassword_cli_installed; then
        SKIPPED_PACKAGES=$((SKIPPED_PACKAGES + 1))
        print_skip "1Password CLI already installed ($(onepassword_cli_version || true))"
        mark_validated_ok
        return 0
    fi

    if apt_available; then
        local keyring="/usr/share/keyrings/1password-archive-keyring.gpg"
        local repo_file="/etc/apt/sources.list.d/1password.list"

        if [ ! -f "$keyring" ]; then
            if spinner_run "Install 1Password APT signing key" bash -lc \
                "curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o $keyring"; then
                :
            else
                print_error "Could not install 1Password APT signing key"
                mark_validated_fail
                return 1
            fi
        fi

        if [ ! -f "$repo_file" ]; then
            if spinner_run "Configure 1Password APT repository" sudo tee "$repo_file" >/dev/null <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main
EOF
            then
                :
            else
                print_error "Could not configure 1Password APT repository"
                mark_validated_fail
                return 1
            fi
        fi

        if spinner_run "apt-get update (1Password repo)" sudo apt-get update; then
            :
        else
            print_warn "Could not refresh APT after adding 1Password repo"
            mark_validated_fail
            return 1
        fi

        if spinner_run "Install 1Password CLI" sudo apt-get install -y 1password-cli; then
            if verify_command_present "op"; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                ONEPASSWORD_CLI_INSTALLED_THIS_RUN=1
                print_ok "Installed 1Password CLI ($(onepassword_cli_version || true))"
            else
                print_error "1Password CLI install reported success but op is still missing"
            fi
        else
            print_error "Could not install 1Password CLI"
            mark_validated_fail
        fi
    elif dnf_available; then
        ensure_1password_linux_repo_dnf || return 1
        if spinner_run "Install 1Password CLI" sudo dnf install -y 1password-cli; then
            if verify_command_present "op"; then
                INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
                ONEPASSWORD_CLI_INSTALLED_THIS_RUN=1
                print_ok "Installed 1Password CLI ($(onepassword_cli_version || true))"
            else
                print_error "1Password CLI install reported success but op is still missing"
            fi
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
# 1Password preferences / browser guidance
#######################################

check_1password_safari_status() {
    if ! is_macos; then
        return 0
    fi

    if onepassword_safari_app_present; then
        print_skip "1Password for Safari app is present"
        mark_validated_ok
    else
        print_warn "1Password for Safari app not detected"
        ONEPASSWORD_SAFARI_NEXT_STEP=1
        mark_validated_fail
    fi
}

install_1password_stack() {
    case "$PLATFORM" in
        mac)
            install_1password_mac_app
            check_1password_safari_status
            install_1password_cli_macos
            ;;
        linux)
            install_1password_linux_app
            install_1password_cli_linux
            ;;
        *)
            print_skip "1Password automation not implemented for platform: $PLATFORM"
            mark_validated_ok
            ;;
    esac
}

#######################################
# fastfetch
#######################################

run_fastfetch() {
    if ! command_exists fastfetch; then
        print_skip "fastfetch not available"
        mark_validated_ok
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would run fastfetch"
        mark_validated_ok
        return 0
    fi

    print_info "Running fastfetch"

    if [ "$QUIET" != "1" ]; then
        print_rule '─'
    fi

    append_log "[INFO] Running fastfetch"

    if [ "$QUIET" = "1" ]; then
        if fastfetch >>"$LOG_FILE" 2>&1; then
            print_ok "fastfetch complete"
            mark_validated_ok
        else
            print_warn "fastfetch failed"
            mark_validated_fail
        fi
        return 0
    fi

    local ff_tmp
    ff_tmp="$(mktemp)"

    if fastfetch --pipe false 2>&1 | tee "$ff_tmp"; then
        cat "$ff_tmp" >>"$LOG_FILE"
        rm -f "$ff_tmp"
        print_rule '─'
        print_ok "fastfetch complete"
        mark_validated_ok
    else
        cat "$ff_tmp" >>"$LOG_FILE"
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
    || [ "$ONEPASSWORD_SAFARI_NEXT_STEP" -eq 1 ] \
    || [ "$ONEPASSWORD_CLI_INSTALLED_THIS_RUN" -eq 1 ] \
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

    if [ "$ONEPASSWORD_INSTALLED_THIS_RUN" -eq 1 ] \
        || [ "$ONEPASSWORD_SAFARI_NEXT_STEP" -eq 1 ] \
        || [ "$ONEPASSWORD_CLI_INSTALLED_THIS_RUN" -eq 1 ]; then
        print_info "1Password"
        if [ "$ONEPASSWORD_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "Open and sign in to the 1Password desktop app"
        fi
        if [ "$ONEPASSWORD_SAFARI_NEXT_STEP" -eq 1 ]; then
            print_info "Install 1Password for Safari from the Mac App Store"
            print_info "Then enable it in Safari Settings > Extensions"
        fi
        if [ "$ONEPASSWORD_CLI_INSTALLED_THIS_RUN" -eq 1 ]; then
            print_info "Run: op signin"
        fi
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
}