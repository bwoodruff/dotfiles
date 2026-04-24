#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#######################################
# Import libraries
#######################################

# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"

# Detect platform early so OS-specific libraries can be sourced conditionally.
detect_platform

# shellcheck source=lib/packages.sh
source "${SCRIPT_DIR}/lib/packages.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/apps.sh
source "${SCRIPT_DIR}/lib/apps.sh"
# shellcheck source=lib/macos.sh
if is_macos; then
    source "${SCRIPT_DIR}/lib/macos.sh"
fi
# shellcheck source=lib/scheduling.sh
source "${SCRIPT_DIR}/lib/scheduling.sh"

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
  --no-auto-update           Do not fetch origin / pull / re-exec when behind (see DOTFILES_AUTO_UPDATE)
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
        --no-auto-update) DOTFILES_AUTO_UPDATE=0 ;;
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

prepare_interactive_screen() {
    if [ "$QUIET" = "1" ] || [ "$SCHEDULED" = "1" ] || [ ! -t 1 ]; then
        return 0
    fi

    clear
}

#######################################
# Task wrappers
#######################################

task_environment() {
    print_info "Platform: $PLATFORM"
    print_info "Dotfiles: $DOTFILES_DIR"
    print_info "Config home: $CONFIG_HOME"
    print_info "Log file: $LOG_FILE"
    if [ "${DOTFILES_INSTALL_REEXEC:-0}" = "1" ]; then
        print_info "Install script: continued after a self-update (fetched the latest from origin)"
    fi
    print_info "FORCE_BREW=$FORCE_BREW DRY_RUN=$DRY_RUN QUIET=$QUIET SCHEDULED=$SCHEDULED PULL_DOTFILES=$PULL_DOTFILES DOTFILES_AUTO_UPDATE=$DOTFILES_AUTO_UPDATE"
}

task_directory_setup() {
    ensure_dir "$CONFIG_HOME"
    ensure_dir "${HOME}/.tmux/plugins"
}

task_package_checks() {
    local package_spec command_name package_name

    for package_spec in "${PACKAGES[@]}"; do
        IFS='|' read -r command_name package_name <<< "$package_spec"
        ensure_command "$command_name" "$package_name"
    done
}

task_git() {
    GIT_BIN="$(get_preferred_git_path)"

    if [ -n "$GIT_BIN" ]; then
        local git_ver=""
        git_ver="$(git_version "$GIT_BIN" || true)"
        if [ -n "$git_ver" ]; then
            print_ok "Using CLI git binary: $GIT_BIN ($git_ver)"
        else
            print_ok "Using CLI git binary: $GIT_BIN"
        fi
    else
        print_warn "No git executable found"
        mark_validated_fail
    fi

    if [ "$PULL_DOTFILES" = "1" ]; then
        update_dotfiles_repo "$GIT_BIN"
    fi

    configure_git "$GIT_BIN"
}

task_cloned_tools() {
    local repo_spec repo_url target_dir clone_args

    if [ -z "${GIT_BIN:-}" ]; then
        print_warn "No git binary available; skipping repo clone checks"
        mark_validated_fail
        return 0
    fi

    for repo_spec in "${GIT_REPOS[@]}"; do
        IFS='|' read -r repo_url target_dir clone_args <<< "$repo_spec"
        clone_repo_if_missing "$GIT_BIN" "$repo_url" "$target_dir" "$clone_args"
    done
}

task_config_symlinks() {
    local link_spec source target optional

    for link_spec in "${SYMLINKS[@]}"; do
        IFS='|' read -r source target optional <<< "$link_spec"
        link_file "$source" "$target" "$optional"
    done
}

task_gpg() {
    if command_exists gpg; then
        local gpg_ver=""
        gpg_ver="$(command_version gpg || true)"
        if [ -n "$gpg_ver" ]; then
            print_skip "gpg already installed ($gpg_ver)"
        else
            print_skip "gpg already installed"
        fi
    else
        ensure_command "gpg" "gnupg"
    fi
}

task_summary() {
    local changes_applied=0
    changes_applied=$((CREATED_DIRS + BACKED_UP_PATHS + LINKED_FILES + INSTALLED_PACKAGES + UPGRADED_PACKAGES + REMOVED_PACKAGES + CLONED_REPOS + INSTALLED_FONTS))

    print_info "Changes applied      : $changes_applied"
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
    print_info "Checks failed        : $VALIDATED_FAIL"
    print_info "Warnings             : $WARNINGS"
    print_info "Errors               : $ERRORS"
    print_post_install_next_steps
}

#######################################
# Task registry
#######################################

TASKS=(
    "Environment|task_environment|all|0"
    "Homebrew|install_homebrew_if_needed|mac|0"
    "Directory setup|task_directory_setup|all|0"
    "Package upgrades|upgrade_packages|all|0"
    "Package checks|task_package_checks|all|0"
    "Alacritty|install_or_update_alacritty|mac|0"
    "Git|task_git|all|0"
    "GitHub Desktop|install_github_desktop|mac|0"
    "Alfred|install_alfred_macos|mac|0"
    "Remove neofetch|remove_neofetch_if_installed|all|0"
    "Cloned tools|task_cloned_tools|all|0"
    "Config symlinks|task_config_symlinks|all|0"
    "Vim|install_vim_plug,install_vim_plugins|all|0"
    "Fonts|install_fonts|all|0"
    "tmux|install_tmux_plugins,reload_tmux_config_if_running|all|0"
    "1Password|install_1password_stack|all|0"
    "GPG|task_gpg|all|0"
    "macOS preferences|configure_global_macos_preferences,configure_dock_preferences,configure_finder_preferences|mac|1"
    "Scheduling|setup_schedule|all|0"
    "fastfetch|run_fastfetch|all|0"
    "Summary|task_summary|all|0"
)

#######################################
# Main
#######################################

main() {
    detect_platform
    init_colors
    init_sections
    init_logging
    prepare_interactive_screen
    # Compare to origin, pull with --ff-only, and re-exec once so the rest of the run uses fresh sources.
    maybe_reexec_fresh_install_script "$SCRIPT_DIR" "$@"
    progress_setup
    acquire_lock

    run_tasks "${TASKS[@]}"

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