#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"
# shellcheck source=lib/packages.sh
source "${SCRIPT_DIR}/lib/packages.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/apps.sh
source "${SCRIPT_DIR}/lib/apps.sh"
# shellcheck source=lib/macos.sh
source "${SCRIPT_DIR}/lib/macos.sh"

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
# Helpers
#######################################

run_package_checks() {
    local package_spec command_name package_name
    for package_spec in "${PACKAGES[@]}"; do
        IFS='|' read -r command_name package_name <<< "$package_spec"
        ensure_command "$command_name" "$package_name"
    done
}

run_repo_clones() {
    local repo_spec repo_url target_dir clone_args

    if [ -z "$GIT_BIN" ]; then
        print_warn "No git binary available; skipping repo clone checks"
        mark_validated_fail
        return 0
    fi

    for repo_spec in "${GIT_REPOS[@]}"; do
        IFS='|' read -r repo_url target_dir clone_args <<< "$repo_spec"
        clone_repo_if_missing "$GIT_BIN" "$repo_url" "$target_dir" "$clone_args"
    done
}

run_symlink_setup() {
    local link_spec source target optional
    for link_spec in "${SYMLINKS[@]}"; do
        IFS='|' read -r source target optional <<< "$link_spec"
        link_file "$source" "$target" "$optional"
    done
}

print_summary() {
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
    print_info "Validated OK         : $VALIDATED_OK"
    print_info "Validation failures  : $VALIDATED_FAIL"
    print_info "Warnings             : $WARNINGS"
    print_info "Errors               : $ERRORS"
}

#######################################
# Main
#######################################

main() {
    detect_platform
    init_colors
    init_sections
    init_logging
    progress_setup
    acquire_lock

    start_section "Environment"
    print_info "Platform: $PLATFORM"
    print_info "Dotfiles: $DOTFILES_DIR"
    print_info "Config home: $CONFIG_HOME"
    print_info "Log file: $LOG_FILE"
    print_info "FORCE_BREW=$FORCE_BREW DRY_RUN=$DRY_RUN QUIET=$QUIET SCHEDULED=$SCHEDULED PULL_DOTFILES=$PULL_DOTFILES"

    start_section "Homebrew"
    install_homebrew_if_needed

    start_section "Directory setup"
    ensure_dir "$CONFIG_HOME"
    ensure_dir "${HOME}/.tmux/plugins"
    ensure_dir "${HOME}/.oh-my-zsh"
    ensure_dir "${HOME}/.oh-my-zsh/custom"
    ensure_dir "${HOME}/.oh-my-zsh/custom/plugins"
    ensure_dir "${HOME}/.oh-my-zsh/custom/themes"

    start_section "Package upgrades"
    upgrade_packages

    start_section "Package checks"
    run_package_checks

    start_section "Alacritty"
    install_or_update_alacritty

    start_section "Git"
    GIT_BIN="$(get_preferred_git_path)"
    if [ -n "$GIT_BIN" ]; then
        local git_ver=""
        git_ver="$(git_version "$GIT_BIN" || true)"
        if [ -n "$git_ver" ]; then
            print_ok "Using CLI git binary: $GIT_BIN ($git_ver)"
        else
            print_ok "Using CLI git binary: $GIT_BIN"
        fi
        mark_validated_ok
    else
        print_warn "No git executable found"
        mark_validated_fail
    fi

    if [ "$PULL_DOTFILES" = "1" ]; then
        update_dotfiles_repo "$GIT_BIN"
    fi
    configure_git "$GIT_BIN"
    
    start_section "GitHub Desktop"
	install_github_desktop

    start_section "Remove neofetch"
    remove_neofetch_if_installed

    start_section "Cloned tools"
    run_repo_clones

    start_section "Config symlinks"
    run_symlink_setup

    start_section "Vim"
    install_vim_plug
    install_vim_plugins

    start_section "Fonts"
    install_fonts

    start_section "tmux"
    install_tmux_plugins
    reload_tmux_config_if_running

    start_section "1Password"
    install_1password_stack

    start_section "GPG"
    if command_exists gpg; then
        local gpg_ver=""
        gpg_ver="$(command_version gpg || true)"
        if [ -n "$gpg_ver" ]; then
            print_skip "gpg already installed ($gpg_ver)"
        else
            print_skip "gpg already installed"
        fi
        mark_validated_ok
    else
        ensure_command "gpg" "gnupg"
    fi

    start_section "macOS preferences"
    configure_global_macos_preferences
    configure_finder_preferences

    start_section "Scheduling"
    setup_schedule

    start_section "fastfetch"
    run_fastfetch

    start_section "Summary"
    print_summary
    print_post_install_next_steps

    printf '\n'
    progress_destroy
    print_info "Log file             : $LOG_FILE"

    if [ "$ERRORS" -eq 0 ] && [ "$VALIDATED_FAIL" -eq 0 ]; then
        print_ok "Bootstrap complete"
    else
        print_warn "Bootstrap finished with issues; see $LOG_FILE"
    fi
}

main "$@"