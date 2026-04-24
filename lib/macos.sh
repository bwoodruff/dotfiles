#!/usr/bin/env bash

#######################################
# Core defaults engine
#######################################

macos_read() {
    local scope="$1"
    local domain="$2"
    local key="$3"

    case "$scope" in
        currentHost)
            defaults -currentHost read "$domain" "$key" 2>/dev/null || true
            ;;
        *)
            defaults read "$domain" "$key" 2>/dev/null || true
            ;;
    esac
}

macos_normalize() {
    local type="$1"
    local value="$2"

    case "$type" in
        bool)
            case "$value" in
                1|true|TRUE|yes) printf 'true\n' ;;
                0|false|FALSE|no) printf 'false\n' ;;
                *) printf '%s\n' "$value" ;;
            esac
            ;;
        *)
            printf '%s\n' "$value"
            ;;
    esac
}

macos_write() {
    local scope="$1"
    local domain="$2"
    local key="$3"
    local type="$4"
    local value="$5"

    [ "$DRY_RUN" = "1" ] && return 0

    case "$scope" in
        currentHost)
            defaults -currentHost write "$domain" "$key" "-$type" "$value"
            ;;
        *)
            defaults write "$domain" "$key" "-$type" "$value"
            ;;
    esac
}

macos_apply() {
    local description="$1"
    local scope="$2"
    local domain="$3"
    local key="$4"
    local type="$5"
    local desired="$6"
    local restart_target="${7:-}"

    local current=""
    local verify=""

    current="$(macos_read "$scope" "$domain" "$key")"
    current="$(macos_normalize "$type" "$current")"

    if [ "$current" = "$desired" ]; then
        print_skip "$description already set"
        return 0
    fi

    if spinner_run "$description" macos_write "$scope" "$domain" "$key" "$type" "$desired"; then
        verify="$(macos_read "$scope" "$domain" "$key")"
        verify="$(macos_normalize "$type" "$verify")"

        if [ "$verify" = "$desired" ]; then
            [ "$restart_target" = "finder" ] && FINDER_PREFS_CHANGED=1
            return 0
        fi

        print_error "$description did not verify"
        mark_validated_fail
        return 1
    fi

    mark_validated_fail
    return 1
}

apply_records() {
    local record=""
    local description=""
    local scope=""
    local domain=""
    local key=""
    local type=""
    local desired=""
    local restart_target=""

    for record in "$@"; do
        IFS='|' read -r description scope domain key type desired restart_target <<< "$record"
        macos_apply "$description" "$scope" "$domain" "$key" "$type" "$desired" "$restart_target"
    done
}

restart_finder_if_needed() {
    if [ "${FINDER_PREFS_CHANGED:-0}" != "1" ]; then
        return 0
    fi

    if [ "$SCHEDULED" = "1" ]; then
        print_skip "Scheduled mode: skipping Finder restart"
        return 0
    fi

    if ! spinner_run "Restart Finder" killall Finder; then
        mark_validated_fail
    fi
}

#######################################
# Hostname (cookie-controlled)
#######################################

hostname_cookie() {
    printf '%s/hostname_set\n' "$(dirname "$LOG_FILE")"
}

configure_hostname_once() {
    local cookie=""
    local hostname=""
    local verify_computer=""
    local verify_host=""
    local verify_local=""
    local verify_netbios=""

    # Explicitly skip in non-interactive contexts
    if [ "$QUIET" = "1" ] || [ "$SCHEDULED" = "1" ]; then
        return 0
    fi

    cookie="$(hostname_cookie)"

    if [ -f "$cookie" ] && [ "${FORCE_HOSTNAME_PROMPT:-0}" != "1" ]; then
        return 0
    fi

    if ! prompt_yes_no_default_yes "Set system hostname?"; then
        return 0
    fi

    printf "Hostname: "
    read -r hostname

    [ -z "$hostname" ] && return 0

    if ! ensure_sudo_cached; then
        print_error "Unable to authenticate for hostname changes"
        mark_validated_fail
        return 1
    fi

    if spinner_run "Set hostname" sudo scutil --set ComputerName "$hostname"; then
        if [ "$DRY_RUN" != "1" ]; then
            sudo scutil --set HostName "$hostname" >/dev/null 2>&1 || true
            sudo scutil --set LocalHostName "$hostname" >/dev/null 2>&1 || true
            sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$hostname" >/dev/null 2>&1 || true
        fi

        verify_computer="$(scutil --get ComputerName 2>/dev/null || true)"
        verify_host="$(scutil --get HostName 2>/dev/null || true)"
        verify_local="$(scutil --get LocalHostName 2>/dev/null || true)"
        verify_netbios="$(defaults read /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName 2>/dev/null || true)"

        if [ "$verify_computer" = "$hostname" ] \
            && [ "$verify_host" = "$hostname" ] \
            && [ "$verify_local" = "$hostname" ] \
            && [ "$verify_netbios" = "$hostname" ]; then

            if [ "$DRY_RUN" != "1" ]; then
                ensure_dir "$(dirname "$cookie")"
                : > "$cookie"
            fi

            return 0
        fi

        print_error "Hostname did not verify"
        mark_validated_fail
        return 1
    fi

    mark_validated_fail
    return 1
}

#######################################
# Appearance (not in MACOS_DEFAULTS_COMMON)
#######################################

# Matches System Settings (unlike `defaults read` for AppleInterfaceStyle on recent macOS).
macos_appearance_is_dark() {
    local out=""
    out="$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')"
    [ "$out" = "true" ]
}

# Recent macOS builds often disagree between `defaults read` and what System Settings shows for
# Light/Dark/Auto, so `macos_apply` skip logic is unsafe here. The General pane applies Dark via
# the same System Events path we use; then we best-effort sync plist keys to match.
macos_apply_dark_appearance() {
    if macos_appearance_is_dark; then
        print_skip "Dark appearance already set"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would set Dark appearance (System Events + defaults sync)"
        return 0
    fi

    if ! spinner_run "Set Dark appearance" osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'; then
        print_error "Set Dark appearance failed (System Events). Grant Terminal (or your terminal app) access if macOS asks."
        mark_validated_fail
        return 1
    fi

    if ! macos_appearance_is_dark; then
        print_error "Dark appearance change did not verify"
        mark_validated_fail
        return 1
    fi

    if ! macos_write standard NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically bool false; then
        print_warn "Could not sync AppleInterfaceStyleSwitchesAutomatically to defaults (non-fatal)"
    fi
    if ! macos_write standard NSGlobalDomain AppleInterfaceStyle string Dark; then
        print_warn "Could not sync AppleInterfaceStyle to defaults (non-fatal)"
    fi
}

#######################################
# Declarative defaults
#######################################

MACOS_DEFAULTS_COMMON=(
    "Set purple accent color|standard|NSGlobalDomain|AppleAccentColor|int|5|"
    "Always show scrollbars|standard|NSGlobalDomain|AppleShowScrollBars|string|Always|"
    "Expand save panel|standard|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode|bool|true|"
    "Expand save panel (v2)|standard|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode2|bool|true|"
    "Expand print panel|standard|NSGlobalDomain|PMPrintingExpandedStateForPrint|bool|true|"
    "Expand print panel (v2)|standard|NSGlobalDomain|PMPrintingExpandedStateForPrint2|bool|true|"
    "Save to disk by default|standard|NSGlobalDomain|NSDocumentSaveNewDocumentsToCloud|bool|false|"
    "Quit printer app when finished|standard|com.apple.print.PrintingPrefs|Quit When Finished|bool|true|"
    "Enable tap to click|standard|com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|true|"
    "Enable tap behavior host|currentHost|NSGlobalDomain|com.apple.mouse.tapBehavior|int|1|"
    "Enable tap behavior global|standard|NSGlobalDomain|com.apple.mouse.tapBehavior|int|1|"
    "Enable two-finger secondary click|standard|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadRightClick|bool|true|"
    "Two-finger gesture|standard|com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadCornerSecondaryClick|int|0|"
    "Disable natural scrolling|standard|NSGlobalDomain|com.apple.swipescrolldirection|bool|false|"
    "Disable .DS_Store network|standard|com.apple.desktopservices|DSDontWriteNetworkStores|bool|true|finder"
    "Disable .DS_Store USB|standard|com.apple.desktopservices|DSDontWriteUSBStores|bool|true|finder"
    "Safari show full URL|standard|com.apple.Safari|ShowFullURLInSmartSearchField|bool|true|"
    "Safari homepage blank|standard|com.apple.Safari|HomePage|string|about:blank|"
    "Safari disable auto-open downloads|standard|com.apple.Safari|AutoOpenSafeDownloads|bool|false|"
    "Safari Develop menu|standard|com.apple.Safari|IncludeDevelopMenu|bool|true|"
    "Safari Web Inspector|standard|com.apple.Safari|WebKitDeveloperExtrasEnabledPreferenceKey|bool|true|"
    "Safari WebKit2 extras|standard|com.apple.Safari|com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled|bool|true|"
    "Global WebKit extras|standard|NSGlobalDomain|WebKitDeveloperExtras|bool|true|"
    "Disable Safari autofill contacts|standard|com.apple.Safari|AutoFillFromAddressBook|bool|false|"
    "Disable Safari autofill passwords|standard|com.apple.Safari|AutoFillPasswords|bool|false|"
    "Disable Safari autofill credit cards|standard|com.apple.Safari|AutoFillCreditCardData|bool|false|"
    "Disable Safari autofill misc|standard|com.apple.Safari|AutoFillMiscellaneousForms|bool|false|"
)

MACOS_DEFAULTS_FINDER=(
    "Finder list view|standard|com.apple.finder|FXPreferredViewStyle|string|Nlsv|finder"
    "Finder path bar|standard|com.apple.finder|ShowPathbar|bool|true|finder"
    "Finder status bar|standard|com.apple.finder|ShowStatusBar|bool|true|finder"
    "Finder tab bar|standard|com.apple.finder|ShowTabView|bool|true|finder"
    "Show file extensions|standard|NSGlobalDomain|AppleShowAllExtensions|bool|true|finder"
    "Finder open home|standard|com.apple.finder|NewWindowTarget|string|PfHm|finder"
    "Finder home path|standard|com.apple.finder|NewWindowTargetPath|string|file://${HOME}|finder"
    "Finder tabs instead windows|standard|com.apple.finder|FinderSpawnTab|bool|true|finder"
    "Finder folders on top|standard|com.apple.finder|_FXSortFoldersFirst|bool|true|finder"
    "Finder folders top desktop|standard|com.apple.finder|_FXSortFoldersFirstOnDesktop|bool|true|finder"
    "Finder search current folder|standard|com.apple.finder|FXDefaultSearchScope|string|SCcf|finder"
    "Hide hard disks on Desktop|standard|com.apple.finder|ShowHardDrivesOnDesktop|bool|false|finder"
    "Hide external disks on Desktop|standard|com.apple.finder|ShowExternalHardDrivesOnDesktop|bool|false|finder"
    "Hide connected servers on Desktop|standard|com.apple.finder|ShowMountedServersOnDesktop|bool|false|finder"
    "Hide removable media on Desktop|standard|com.apple.finder|ShowRemovableMediaOnDesktop|bool|false|finder"
    "Disable iCloud Desktop/Documents shortcut in Finder sidebar|standard|com.apple.finder|SidebarShowingiCloudDesktop|bool|false|finder"
)

safari_developer_features_enabled() {
    local legacy=""
    local sandbox=""

    legacy="$(defaults read com.apple.Safari IncludeDevelopMenu 2>/dev/null || true)"
    sandbox="$(defaults read com.apple.Safari.SandboxBroker ShowDevelopMenu 2>/dev/null || true)"

    [ "$legacy" = "1" ] || [ "$sandbox" = "1" ]
}

# Sets SAFARI_DEVTOOLS_NEXT_STEP for post-install hints; run from configure_global_macos_preferences
# (not at file scope — that would print before Environment and before logging initializes).
macos_safari_developer_status_message() {
    if safari_developer_features_enabled; then
        print_skip "Safari developer features already enabled"
        SAFARI_DEVTOOLS_NEXT_STEP=0
    else
        SAFARI_DEVTOOLS_NEXT_STEP=1
        print_info "Safari developer features are not enabled"
    fi
}

#######################################
# Entry points
#######################################

configure_global_macos_preferences() {
    if ! is_macos; then
        print_skip "macOS preferences not relevant"
        return 0
    fi

    if ! is_interactive; then
        print_skip "Skipping macOS preferences in non-interactive mode"
        return 0
    fi

    osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true
    osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true

    macos_safari_developer_status_message
    macos_apply_dark_appearance
    configure_hostname_once
    apply_records "${MACOS_DEFAULTS_COMMON[@]}"
}

configure_finder_preferences() {
    if ! is_macos; then
        print_skip "Finder preferences not relevant on non-macOS"
        return 0
    fi

    if ! is_interactive; then
        print_skip "Skipping Finder preferences in non-interactive mode"
        return 0
    fi

    apply_records "${MACOS_DEFAULTS_FINDER[@]}"
    restart_finder_if_needed
}