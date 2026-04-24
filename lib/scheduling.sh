#!/usr/bin/env bash

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
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would install cron schedule"
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
    else
        print_warn "Could not install cron schedule"
        mark_validated_fail
    fi
}

setup_schedule() {
    if [ "$SETUP_SCHEDULE" != "1" ]; then
        print_skip "Schedule setup disabled"
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
            ;;
    esac
}