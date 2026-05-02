#!/usr/bin/env bash

#######################################
# Git helpers
#######################################

get_preferred_git_path() {
    local github_desktop_git=""

    if command_exists git; then
        command -v git
        return
    fi

    if is_macos; then
        github_desktop_git="/Applications/GitHub Desktop.app/Contents/Resources/app/git/bin/git"
        if [ -x "$github_desktop_git" ]; then
            printf '%s\n' "$github_desktop_git"
            return
        fi
    fi

    printf '\n'
}

git_version() {
    local git_bin="$1"
    if [ -n "$git_bin" ] && [ -x "$git_bin" ]; then
        "$git_bin" --version 2>/dev/null | awk '{print $3}'
    fi
}

update_dotfiles_repo() {
    local git_bin="$1"

    if [ -n "${DOTFILES_SELF_UPDATE_PULLED:-}" ]; then
        print_skip "Dotfiles already updated before this run"
        return 0
    fi

    if [ -z "$git_bin" ]; then
        print_warn "No git executable available; cannot pull dotfiles"
        mark_validated_fail
        return 1
    fi

    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        print_skip "Dotfiles repo not found at $DOTFILES_DIR"
        return 0
    fi

    if spinner_run "Pull dotfiles repo" dotfiles_git_http "$git_bin" -C "$DOTFILES_DIR" pull --ff-only; then
        print_ok "Dotfiles repo pulled"
    else
        local pull_status=$?
        print_warn "Dotfiles pull failed"
        # Do not assume HTTPS auth when the failure was "command not found" (127), timeout (124), etc.
        case "$pull_status" in
            124|126|127) ;;
            *) command_exists gh && GH_NEEDS_AUTH_HINT=1 ;;
        esac
        mark_validated_fail
    fi
}

#######################################
# Self-update: compare to origin, pull, re-exec
#######################################

dotfiles_normalize_github_path() {
    local u="${1?}"
    u="${u#git@github.com:}"
    u="${u#https://github.com/}"
    u="${u#http://github.com/}"
    u="${u%.git}"
    printf '%s\n' "$u"
}

# Returns 0 if we should trust origin (URL matches, or any-origin is allowed).
dotfiles_self_update_trusts_origin() {
    local git_bin="${1?}" repo_root="${2?}"
    local url norm

    if [ "$DOTFILES_SELF_UPDATE_ANY_ORIGIN" = "1" ]; then
        return 0
    fi

    if ! url="$("$git_bin" -C "$repo_root" remote get-url origin 2>/dev/null)"; then
        return 1
    fi
    if [ -z "$url" ]; then
        return 1
    fi

    norm="$(dotfiles_normalize_github_path "$url")"
    [ "$norm" = "$DOTFILES_UPSTREAM_GITHUB" ]
}

# If install.sh is behind origin/HEAD, fast-forward, then re-exec with the same args.
# Safe to run before git + lock: re-exec replaces the process, so no second lock; child
# sets DOTFILES_INSTALL_REEXEC=1 to avoid an update loop. Updates only the in-repo script; a
# git pull in task_git is redundant if DOTFILES_SELF_UPDATE_PULLED is set.
maybe_reexec_fresh_install_script() {
    local script_dir="${1?}"
    shift

    if [ "$DOTFILES_AUTO_UPDATE" != "1" ] || [ "$DRY_RUN" = "1" ]; then
        return 0
    fi
    if [ "${DOTFILES_INSTALL_REEXEC:-0}" = "1" ]; then
        return 0
    fi

    local git_bin repo_root
    git_bin="$(get_preferred_git_path)"
    if [ -z "$git_bin" ] || [ ! -x "$git_bin" ]; then
        return 0
    fi

    repo_root="$("$git_bin" -C "$script_dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
    if [ ! -d "$repo_root/.git" ]; then
        return 0
    fi

    local df_resolved
    df_resolved="$(cd "$DOTFILES_DIR" 2>/dev/null && pwd 2>/dev/null)" || df_resolved=""
    if [ -n "$df_resolved" ] && [ "$df_resolved" != "$repo_root" ]; then
        print_info "This script's repo is $repo_root, but DOTFILES_DIR is $DOTFILES_DIR; skipping self-update to avoid the wrong tree"
        return 0
    fi

    if ! dotfiles_self_update_trusts_origin "$git_bin" "$repo_root"; then
        if [ "$QUIET" = "1" ]; then
            return 0
        fi
        print_info "origin does not look like ${DOTFILES_UPSTREAM_GITHUB}; skipping self-update (set DOTFILES_SELF_UPDATE_ANY_ORIGIN=1 to allow any origin)"
        return 0
    fi

    if [ -n "$("$git_bin" -C "$repo_root" status --porcelain 2>/dev/null)" ]; then
        print_warn "Dotfiles repo has uncommitted changes; skipping self-update. Commit or stash, or run with DOTFILES_AUTO_UPDATE=0"
        return 0
    fi

    if ! dotfiles_git_http "$git_bin" -C "$repo_root" fetch -q --prune origin 2>/dev/null; then
        if [ "$QUIET" = "1" ]; then
            return 0
        fi
        print_info "Could not contact git origin; continuing with the current install script on disk"
        return 0
    fi

    local branch behind ahead
    branch="$("$git_bin" -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
    if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
        return 0
    fi
    if ! "$git_bin" -C "$repo_root" rev-parse -q "origin/${branch}" >/dev/null 2>&1; then
        if [ "$QUIET" = "1" ]; then
            return 0
        fi
        print_info "No origin/${branch} yet; skipping self-update"
        return 0
    fi

    behind="$("$git_bin" -C "$repo_root" rev-list --count HEAD.."origin/${branch}" 2>/dev/null || echo 0)"
    ahead="$("$git_bin" -C "$repo_root" rev-list --count "origin/${branch}"..HEAD 2>/dev/null || echo 0)"
    if [ "$behind" = "0" ] || [ -z "$behind" ]; then
        return 0
    fi
    if [ "${ahead:-0}" != "0" ]; then
        print_warn "Remote has newer commits, but you have local commits; not auto-updating. Rebase, merge, or push, then re-run (or set DOTFILES_AUTO_UPDATE=0)"
        return 0
    fi

    if ! spinner_run "Pull latest dotfiles (self-update)" dotfiles_git_http "$git_bin" -C "$repo_root" pull --ff-only; then
        print_warn "Could not fast-forward the dotfiles repo; continuing with the current install script on disk"
        return 0
    fi

    print_info "Restarting the installer so it runs the code you just pulled (one re-exec only)"
    export DOTFILES_INSTALL_REEXEC=1
    export DOTFILES_SELF_UPDATE_PULLED=1
    exec /usr/bin/env bash "${script_dir}/install.sh" "$@"
}

configure_git() {
    local git_bin="$1"
    local current_editor=""

    if [ -z "$git_bin" ] || ! command_exists vim; then
        print_skip "Skipping git editor config"
        return 0
    fi

    current_editor="$("$git_bin" config --global core.editor 2>/dev/null || true)"

    if [ "$current_editor" = "vim" ]; then
        print_skip "Git editor already set to vim"
        return 0
    fi

    if spinner_run "Set git editor to vim" "$git_bin" config --global core.editor "vim"; then
        current_editor="$("$git_bin" config --global core.editor 2>/dev/null || true)"
        if [ "$current_editor" = "vim" ]; then
            print_ok "Git editor set to vim"
        else
            print_error "Git editor change did not verify"
            mark_validated_fail
        fi
    else
        print_error "Could not set git editor"
        mark_validated_fail
    fi
}

#######################################
# Repo clones
#######################################

clone_repo_if_missing() {
    local git_bin="$1"
    local repo_url="$2"
    local target_dir="$3"
    local clone_args="${4:-}"

    if [ -d "$target_dir" ]; then
        SKIPPED_REPOS=$((SKIPPED_REPOS + 1))
        print_skip "Repo present: $target_dir"
        return 0
    fi

    ensure_dir "$(dirname "$target_dir")"

    # shellcheck disable=SC2086
    if spinner_run "Clone $(basename "$repo_url")" dotfiles_git_http "$git_bin" clone $clone_args "$repo_url" "$target_dir"; then
        if [ -d "$target_dir/.git" ] || [ -d "$target_dir" ]; then
            CLONED_REPOS=$((CLONED_REPOS + 1))
            print_ok "Cloned repo: $target_dir"
        else
            print_error "Clone reported success but repo missing: $target_dir"
            mark_validated_fail
        fi
    else
        print_error "Could not clone $repo_url"
        mark_validated_fail
    fi
}

#######################################
# Symlinks
#######################################

link_file() {
    local source="$1"
    local target="$2"
    local optional="${3:-0}"

    if [ ! -e "$source" ]; then
        if [ "$optional" = "1" ] && [ "$STRICT_OPTIONAL_CONFIGS" != "1" ]; then
            SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
            print_skip "Optional source missing: $source"
            return 0
        fi
        SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
        print_warn "Source file missing: $source"
        mark_validated_fail
        return 1
    fi

    ensure_dir "$(dirname "$target")"

    if [ -L "$target" ]; then
        local current_link
        current_link="$(readlink "$target" || true)"
        if [ "$current_link" = "$source" ]; then
            SKIPPED_LINKS=$((SKIPPED_LINKS + 1))
            print_skip "Symlink already correct: $target"
            return 0
        fi
    fi

    backup_if_exists "$target" || return 1

    if spinner_run "Link $target" ln -s "$source" "$target"; then
        if verify_symlink_target "$target" "$source"; then
            LINKED_FILES=$((LINKED_FILES + 1))
            print_ok "Linked $target -> $source"
            if [ "$target" = "${CONFIG_HOME}/tmux/tmux.conf" ]; then
                TMUX_CONFIG_CHANGED=1
            fi
        else
            print_error "Symlink did not verify: $target"
            mark_validated_fail
        fi
    else
        print_error "Could not link $target -> $source"
        mark_validated_fail
    fi
}

#######################################
# Vim
#######################################

install_vim_plug() {
    local plug_path="${HOME}/.vim/autoload/plug.vim"

    if [ -f "$plug_path" ]; then
        print_skip "vim-plug already installed"
        return 0
    fi

    ensure_dir "$(dirname "$plug_path")"

    if spinner_run "Install vim-plug" dotfiles_curl -fLo "$plug_path" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
        if verify_path_exists "$plug_path"; then
            print_ok "vim-plug installed"
        else
            print_error "vim-plug install reported success but file missing"
            mark_validated_fail
        fi
    else
        print_warn "Could not install vim-plug"
        mark_validated_fail
    fi
}

install_vim_plugins() {
    local vim_log="${HOME}/.vim/plug-install.log"

    if ! command_exists vim; then
        print_skip "vim not available"
        return 0
    fi

    if [ ! -f "${HOME}/.vimrc" ]; then
        print_skip ".vimrc not found"
        return 0
    fi

    if [ ! -f "${HOME}/.vim/autoload/plug.vim" ]; then
        print_skip "vim-plug not found"
        return 0
    fi

    if [ -d "${HOME}/.vim/plugged" ]; then
        print_skip "Vim plugins already installed"
        return 0
    fi

    ensure_dir "${HOME}/.vim"
    append_log "Vim plugin log: $vim_log"

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would run vim -N -V1${vim_log} -E -s -u ${HOME}/.vimrc '+PlugInstall --sync' '+qa!'"
        return 0
    fi

    if vim -N -V1"${vim_log}" -E -s -u "${HOME}/.vimrc" "+PlugInstall --sync" "+qa!" >>"$LOG_FILE" 2>&1; then
        if [ -d "${HOME}/.vim/plugged" ]; then
            print_ok "Vim plugins installed"
        else
            print_error "Vim exited successfully but ~/.vim/plugged was not found"
            mark_validated_fail
        fi
    else
        print_warn "Vim plugin installation failed; see $vim_log"
        mark_validated_fail
    fi
}

#######################################
# Fonts
#######################################

install_fonts() {
    local fonts_source_dir="${DOTFILES_DIR}/fonts"
    local fonts_dest_dir=""

    if [ ! -d "$fonts_source_dir" ]; then
        print_skip "No fonts directory at $fonts_source_dir"
        return 0
    fi

    case "$PLATFORM" in
        mac) fonts_dest_dir="${HOME}/Library/Fonts" ;;
        linux) fonts_dest_dir="${HOME}/.local/share/fonts" ;;
        *)
            print_warn "Font installation not implemented for platform: $PLATFORM"
            mark_validated_fail
            return 1
            ;;
    esac

    ensure_dir "$fonts_dest_dir"

    local found_any=0
    while IFS= read -r -d '' font_file; do
        found_any=1
        local filename
        filename="$(basename "$font_file")"

        if [ -e "${fonts_dest_dir}/${filename}" ]; then
            SKIPPED_FONTS=$((SKIPPED_FONTS + 1))
            print_skip "Font present: ${filename}"
        else
            if spinner_run "Install font ${filename}" cp "$font_file" "${fonts_dest_dir}/${filename}"; then
                if verify_path_exists "${fonts_dest_dir}/${filename}"; then
                    INSTALLED_FONTS=$((INSTALLED_FONTS + 1))
                    print_ok "Installed font: ${filename}"
                else
                    print_error "Font install reported success but file missing: ${filename}"
                    mark_validated_fail
                fi
            else
                print_error "Could not install font: ${filename}"
                mark_validated_fail
            fi
        fi
    done < <(find "$fonts_source_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)

    if [ "$found_any" = "0" ]; then
        print_skip "No font files found under $fonts_source_dir"
    fi

    if is_linux && [ "$INSTALLED_FONTS" -gt 0 ] && command_exists fc-cache; then
        if spinner_run "Refresh font cache" fc-cache -f "$fonts_dest_dir"; then
            print_ok "Font cache refreshed"
        else
            print_warn "Could not refresh font cache"
            mark_validated_fail
        fi
    fi
}

#######################################
# tmux
#######################################

install_tmux_plugins() {
    local installer="${HOME}/.tmux/plugins/tpm/bin/install_plugins"

    if [ ! -x "$installer" ]; then
        print_skip "TPM installer not found"
        return 0
    fi

    if [ "${TMUX_CONFIG_CHANGED:-0}" != "1" ]; then
        print_skip "tmux plugins unchanged; install not needed"
        return 0
    fi

    if spinner_run "Install tmux plugins" "$installer"; then
        print_ok "tmux plugins installed"
    else
        print_warn "tmux plugin install failed"
        mark_validated_fail
    fi
}

reload_tmux_config_if_running() {
    local tmux_conf="${CONFIG_HOME}/tmux/tmux.conf"

    if [ "$SCHEDULED" = "1" ]; then
        print_skip "Scheduled mode: skipping tmux reload"
        return 0
    fi

    if [ "${TMUX_CONFIG_CHANGED:-0}" != "1" ]; then
        print_skip "tmux config unchanged; reload not needed"
        return 0
    fi

    if ! command_exists tmux; then
        print_skip "tmux not available"
        return 0
    fi

    if ! tmux ls >/dev/null 2>&1; then
        print_skip "No tmux server running"
        return 0
    fi

    if [ ! -f "$tmux_conf" ]; then
        print_skip "tmux config not found"
        return 0
    fi

    if spinner_run "Reload tmux config" tmux source-file "$tmux_conf"; then
        print_ok "tmux config reloaded"
    else
        print_warn "Could not reload tmux config"
        mark_validated_fail
    fi
}

#######################################
# Config declarations
#######################################

GIT_REPOS=(
    "https://github.com/ohmyzsh/ohmyzsh.git|${HOME}/.oh-my-zsh|"
    "https://github.com/romkatv/powerlevel10k.git|${HOME}/.oh-my-zsh/custom/themes/powerlevel10k|--depth=1"
    "https://github.com/zsh-users/zsh-syntax-highlighting.git|${HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting|"
    "https://github.com/zsh-users/zsh-completions.git|${HOME}/.oh-my-zsh/custom/plugins/zsh-completions|"
    "https://github.com/tmux-plugins/tpm.git|${HOME}/.tmux/plugins/tpm|"
)

SYMLINKS=(
    "${DOTFILES_DIR}/alacritty/alacritty.toml|${CONFIG_HOME}/alacritty/alacritty.toml|0"
    "${DOTFILES_DIR}/zsh/.zshrc|${HOME}/.zshrc|0"
    "${DOTFILES_DIR}/zsh/.p10k.zsh|${HOME}/.p10k.zsh|0"
    "${DOTFILES_DIR}/dir_colors/.dir_colors|${HOME}/.dir_colors|0"
    "${DOTFILES_DIR}/vim/.vimrc|${HOME}/.vimrc|0"
    "${DOTFILES_DIR}/fastfetch/config.conf|${CONFIG_HOME}/fastfetch/config.conf|1"
    "${DOTFILES_DIR}/tmux/tmux.conf|${CONFIG_HOME}/tmux/tmux.conf|0"
)