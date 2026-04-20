#!/usr/bin/env bash

#######################################
# macOS defaults helpers
#######################################

macos_defaults_read() {
    local domain="$1"
    local key="$2"
    defaults read "$domain" "$key" 2>/dev/null || true
}

macos_bool_is_true() {
    case "$1" in
        1|true|TRUE|yes) return 0 ;;
        *) return 1 ;;
    esac
}

macos_bool_is_false() {
    case "$1" in
        0|false|FALSE|no) return 0 ;;
        *) return 1 ;;
    esac
}

macos_defaults_write_bool() {
    local domain="$1"
    local key="$2"
    local value="$3"
    local description="$4"
    local verify_domain="${5:-$domain}"
    local verify_key="${6:-$key}"
    local actual=""

    if spinner_run "$description" defaults write "$domain" "$key" -bool "$value"; then
        actual="$(macos_defaults_read "$verify_domain" "$verify_key")"

        if [ "$value" = "true" ]; then
            if macos_bool_is_true "$actual"; then
                mark_validated_ok
                return 0
            fi
        else
            if macos_bool_is_false "$actual"; then
                mark_validated_ok
                return 0
            fi
        fi

        print_error "$description did not verify"
        mark_validated_fail
        return 1
    fi

    print_error "$description failed"
    mark_validated_fail
    return 1
}

macos_defaults_write_string() {
    local domain="$1"
    local key="$2"
    local value="$3"
    local description="$4"
    local verify_domain="${5:-$domain}"
    local verify_key="${6:-$key}"
    local actual=""

    if spinner_run "$description" defaults write "$domain" "$key" -string "$value"; then
        actual="$(macos_defaults_read "$verify_domain" "$verify_key")"

        if [ "$actual" = "$value" ]; then
            mark_validated_ok
            return 0
        fi

        print_error "$description did not verify"
        mark_validated_fail
        return 1
    fi

    print_error "$description failed"
    mark_validated_fail
    return 1
}

macos_defaults_write_int() {
    local domain="$1"
    local key="$2"
    local value="$3"
    local description="$4"
    local verify_domain="${5:-$domain}"
    local verify_key="${6:-$key}"
    local actual=""

    if spinner_run "$description" defaults write "$domain" "$key" -int "$value"; then
        actual="$(macos_defaults_read "$verify_domain" "$verify_key")"

        if [ "$actual" = "$value" ]; then
            mark_validated_ok
            return 0
        fi

        print_error "$description did not verify"
        mark_validated_fail
        return 1
    fi

    print_error "$description failed"
    mark_validated_fail
    return 1
}

restart_finder_if_needed() {
    if [ "$FINDER_PREFS_CHANGED" != "1" ]; then
        return 0
    fi

    if [ "$SCHEDULED" = "1" ]; then
        print_skip "Scheduled mode: skipping Finder restart"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Restart Finder" killall Finder; then
        mark_validated_ok
    else
        print_warn "Could not restart Finder automatically"
        mark_validated_fail
    fi
}

#######################################
# Global macOS preferences
#######################################

current_macos_appearance_is_dark() {
    local result=""
    result="$(macos_defaults_read -g AppleInterfaceStyle)"
    [ "$result" = "Dark" ]
}

set_macos_appearance_dark() {
    if current_macos_appearance_is_dark; then
        print_skip "macOS appearance already Dark"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Set macOS appearance to Dark" osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'; then
        if current_macos_appearance_is_dark; then
            mark_validated_ok
        else
            print_error "macOS appearance change did not verify"
            mark_validated_fail
        fi
    else
        print_error "Failed to set macOS appearance to Dark"
        mark_validated_fail
    fi
}

current_macos_accent_is_purple() {
    local actual=""
    actual="$(macos_defaults_read -g AppleAccentColor)"
    [ "$actual" = "5" ]
}

set_macos_accent_purple() {
    if current_macos_accent_is_purple; then
        print_skip "macOS accent color already Purple"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Set macOS accent color to Purple" defaults write -g AppleAccentColor -int 5; then
        local actual=""
        actual="$(macos_defaults_read -g AppleAccentColor)"
        if [ "$actual" = "5" ]; then
            mark_validated_ok
        else
            print_error "Accent color change did not verify"
            mark_validated_fail
        fi
    else
        print_error "Failed to set macOS accent color"
        mark_validated_fail
    fi
}

current_scroll_direction_is_natural() {
    local actual=""
    actual="$(macos_defaults_read -g com.apple.swipescrolldirection)"
    macos_bool_is_true "$actual"
}

set_scroll_direction_natural() {
    if current_scroll_direction_is_natural; then
        print_skip "Natural scroll direction already enabled"
        mark_validated_ok
        return 0
    fi

    macos_defaults_write_bool -g com.apple.swipescrolldirection true "Enable natural scroll direction"
}

configure_global_macos_preferences() {
    if ! is_macos; then
        print_skip "macOS preferences not relevant on non-macOS"
        mark_validated_ok
        return 0
    fi

    if ! is_interactive; then
        print_skip "Skipping macOS preferences in non-interactive mode"
        mark_validated_ok
        return 0
    fi

    if current_macos_appearance_is_dark; then
        print_skip "macOS appearance already Dark"
        mark_validated_ok
    else
        if prompt_yes_no_default_yes "Set macOS appearance to Dark?"; then
            set_macos_appearance_dark
        else
            print_skip "macOS appearance unchanged"
            mark_validated_ok
        fi
    fi

    if current_macos_accent_is_purple; then
        print_skip "macOS accent color already Purple"
        mark_validated_ok
    else
        if prompt_yes_no_default_yes "Set macOS accent color to Purple?"; then
            set_macos_accent_purple
        else
            print_skip "macOS accent color unchanged"
            mark_validated_ok
        fi
    fi

    if current_scroll_direction_is_natural; then
        print_skip "Natural scroll direction already enabled"
        mark_validated_ok
    else
        if prompt_yes_no_default_yes "Enable natural scroll direction?"; then
            set_scroll_direction_natural
        else
            print_skip "Scroll direction unchanged"
            mark_validated_ok
        fi
    fi
}

#######################################
# Finder preferences
#######################################

finder_default_view_is_list() {
    [ "$(macos_defaults_read com.apple.finder FXPreferredViewStyle)" = "Nlsv" ]
}

finder_show_path_bar_enabled() {
    macos_bool_is_true "$(macos_defaults_read com.apple.finder ShowPathbar)"
}

finder_show_status_bar_enabled() {
    macos_bool_is_true "$(macos_defaults_read com.apple.finder ShowStatusBar)"
}

finder_show_tab_bar_enabled() {
    macos_bool_is_true "$(macos_defaults_read com.apple.finder ShowTabView)"
}

finder_show_extensions_enabled() {
    macos_bool_is_true "$(macos_defaults_read -g AppleShowAllExtensions)"
}

finder_new_windows_show_home() {
    local target=""
    local path=""
    target="$(macos_defaults_read com.apple.finder NewWindowTarget)"
    path="$(macos_defaults_read com.apple.finder NewWindowTargetPath)"
    [ "$target" = "PfHm" ] && [ "$path" = "file://${HOME}" ]
}

finder_tabs_instead_of_windows_enabled() {
    macos_bool_is_true "$(macos_defaults_read com.apple.finder FinderSpawnTab)"
}

finder_keep_folders_on_top_windows_enabled() {
    macos_bool_is_true "$(macos_defaults_read com.apple.finder _FXSortFoldersFirst)"
}

finder_keep_folders_on_top_desktop_enabled() {
    macos_bool_is_true "$(macos_defaults_read com.apple.finder _FXSortFoldersFirstOnDesktop)"
}

finder_search_current_folder_enabled() {
    [ "$(macos_defaults_read com.apple.finder FXDefaultSearchScope)" = "SCcf" ]
}

finder_hide_hard_disks_on_desktop_correct() {
    macos_bool_is_false "$(macos_defaults_read com.apple.finder ShowHardDrivesOnDesktop)"
}

finder_hide_external_disks_on_desktop_correct() {
    macos_bool_is_false "$(macos_defaults_read com.apple.finder ShowExternalHardDrivesOnDesktop)"
}

finder_hide_servers_on_desktop_correct() {
    macos_bool_is_false "$(macos_defaults_read com.apple.finder ShowMountedServersOnDesktop)"
}

finder_hide_removable_media_on_desktop_correct() {
    macos_bool_is_false "$(macos_defaults_read com.apple.finder ShowRemovableMediaOnDesktop)"
}

finder_disable_icloud_sidebar_shortcut_correct() {
    macos_bool_is_false "$(macos_defaults_read com.apple.finder SidebarShowingiCloudDesktop)"
}

finder_preferences_need_changes() {
    ! finder_default_view_is_list \
    || ! finder_show_path_bar_enabled \
    || ! finder_show_status_bar_enabled \
    || ! finder_show_tab_bar_enabled \
    || ! finder_show_extensions_enabled \
    || ! finder_new_windows_show_home \
    || ! finder_tabs_instead_of_windows_enabled \
    || ! finder_keep_folders_on_top_windows_enabled \
    || ! finder_keep_folders_on_top_desktop_enabled \
    || ! finder_search_current_folder_enabled \
    || ! finder_hide_hard_disks_on_desktop_correct \
    || ! finder_hide_external_disks_on_desktop_correct \
    || ! finder_hide_servers_on_desktop_correct \
    || ! finder_hide_removable_media_on_desktop_correct \
    || ! finder_disable_icloud_sidebar_shortcut_correct
}

apply_finder_preferences() {
    print_info "Applying Finder preferences"

    if finder_default_view_is_list; then
        print_skip "Finder default view already List"
        mark_validated_ok
    else
        macos_defaults_write_string com.apple.finder FXPreferredViewStyle Nlsv "Set Finder default view to List"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_show_path_bar_enabled; then
        print_skip "Finder path bar already enabled"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowPathbar true "Enable Finder path bar"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_show_status_bar_enabled; then
        print_skip "Finder status bar already enabled"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowStatusBar true "Enable Finder status bar"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_show_tab_bar_enabled; then
        print_skip "Finder tab bar already enabled"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowTabView true "Enable Finder tab bar"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_show_extensions_enabled; then
        print_skip "Show all filename extensions already enabled"
        mark_validated_ok
    else
        macos_defaults_write_bool -g AppleShowAllExtensions true "Enable show all filename extensions"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_new_windows_show_home; then
        print_skip "Finder new windows already open to Home"
        mark_validated_ok
    else
        macos_defaults_write_string com.apple.finder NewWindowTarget PfHm "Set Finder new windows to Home"
        macos_defaults_write_string com.apple.finder NewWindowTargetPath "file://${HOME}" "Set Finder home target path"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_tabs_instead_of_windows_enabled; then
        print_skip "Finder already opens folders in tabs instead of new windows"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder FinderSpawnTab true "Open folders in tabs instead of new windows"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_keep_folders_on_top_windows_enabled; then
        print_skip "Finder already keeps folders on top in windows"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder _FXSortFoldersFirst true "Keep folders on top in Finder windows"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_keep_folders_on_top_desktop_enabled; then
        print_skip "Finder already keeps folders on top on Desktop"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder _FXSortFoldersFirstOnDesktop true "Keep folders on top on Desktop"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_search_current_folder_enabled; then
        print_skip "Finder search scope already set to current folder"
        mark_validated_ok
    else
        macos_defaults_write_string com.apple.finder FXDefaultSearchScope SCcf "Set Finder search scope to current folder"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_hide_hard_disks_on_desktop_correct; then
        print_skip "Hard disks already hidden on Desktop"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowHardDrivesOnDesktop false "Hide hard disks on Desktop"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_hide_external_disks_on_desktop_correct; then
        print_skip "External disks already hidden on Desktop"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowExternalHardDrivesOnDesktop false "Hide external disks on Desktop"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_hide_servers_on_desktop_correct; then
        print_skip "Connected servers already hidden on Desktop"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowMountedServersOnDesktop false "Hide connected servers on Desktop"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_hide_removable_media_on_desktop_correct; then
        print_skip "CDs/DVDs/iOS devices already hidden on Desktop"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder ShowRemovableMediaOnDesktop false "Hide CDs/DVDs/iOS devices on Desktop"
        FINDER_PREFS_CHANGED=1
    fi

    if finder_disable_icloud_sidebar_shortcut_correct; then
        print_skip "iCloud Desktop/Documents sync shortcut already disabled in Finder sidebar"
        mark_validated_ok
    else
        macos_defaults_write_bool com.apple.finder SidebarShowingiCloudDesktop false "Disable iCloud Desktop/Documents sync shortcut in Finder sidebar"
        FINDER_PREFS_CHANGED=1
    fi

    restart_finder_if_needed
}

configure_finder_preferences() {
    if ! is_macos; then
        print_skip "Finder preferences not relevant on non-macOS"
        mark_validated_ok
        return 0
    fi

    if ! is_interactive; then
        print_skip "Skipping Finder preferences in non-interactive mode"
        mark_validated_ok
        return 0
    fi

    if ! finder_preferences_need_changes; then
        print_skip "Finder preferences already configured"
        mark_validated_ok
        return 0
    fi

    if prompt_yes_no_default_yes "Configure Finder preferences?"; then
        apply_finder_preferences
    else
        print_skip "Finder preferences unchanged"
        mark_validated_ok
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
        mark_validated_ok
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would create launchd schedule at $plist_path"
        mark_validated_ok
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

    if [ ! -f "$plist_path" ]; then
        print_error "launchd plist was not written"
        mark_validated_fail
        return 1
    fi

    if launchctl list | grep -q "com.bdw.dotfiles.install"; then
        launchctl unload "$plist_path" >>"$LOG_FILE" 2>&1 || true
    fi

    if launchctl load "$plist_path" >>"$LOG_FILE" 2>&1; then
        print_ok "launchd schedule installed"
        mark_validated_ok
    else
        print_warn "Could not load launchd plist"
        mark_validated_fail
    fi
}

setup_schedule_linux() {
    local script_path="${DOTFILES_DIR}/install.sh"
    local cron_line="0 0 * * 1 cd \"${DOTFILES_DIR}\" && \"${script_path}\" --scheduled --quiet >> \"${LOG_FILE}\" 2>&1"
    local current_cron=""

    if ! cron_available; then
        print_warn "crontab not available; cannot set weekly schedule"
        mark_validated_fail
        return 1
    fi

    current_cron="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$current_cron" | grep -Fq "$script_path --scheduled --quiet"; then
        print_skip "cron schedule already present"
        mark_validated_ok
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would install cron schedule"
        mark_validated_ok
        return 0
    fi

    {
        printf '%s\n' "$current_cron" | sed '/^[[:space:]]*$/d'
        printf '%s\n' "$cron_line"
    } | crontab -

    local updated_cron=""
    updated_cron="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$updated_cron" | grep -Fq "$script_path --scheduled --quiet"; then
        print_ok "cron schedule installed"
        mark_validated_ok
    else
        print_warn "Could not install cron schedule"
        mark_validated_fail
    fi
}

setup_schedule() {
    if [ "$SETUP_SCHEDULE" != "1" ]; then
        print_skip "Schedule setup disabled"
        mark_validated_ok
        return 0
    fi

    case "$PLATFORM" in
        mac)
            setup_schedule_macos
            ;;
        linux)
            setup_schedule_linux
            ;;
        *)
            print_skip "Schedule setup not implemented for platform: $PLATFORM"
            mark_validated_ok
            ;;
    esac
}