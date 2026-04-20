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

    if [ -z "$git_bin" ]; then
        print_warn "No git executable available; cannot pull dotfiles"
        mark_validated_fail
        return 1
    fi

    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        print_skip "Dotfiles repo not found at $DOTFILES_DIR"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Pull dotfiles repo" "$git_bin" -C "$DOTFILES_DIR" pull --ff-only; then
        print_ok "Dotfiles repo pulled"
        mark_validated_ok
    else
        print_warn "Dotfiles pull failed"
        command_exists gh && GH_NEEDS_AUTH_HINT=1
        mark_validated_fail
    fi
}

configure_git() {
    local git_bin="$1"
    local current_editor=""

    if [ -z "$git_bin" ] || ! command_exists vim; then
        print_skip "Skipping git editor config"
        mark_validated_ok
        return 0
    fi

    current_editor="$("$git_bin" config --global core.editor 2>/dev/null || true)"

    if [ "$current_editor" = "vim" ]; then
        print_skip "Git editor already set to vim"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Set git editor to vim" "$git_bin" config --global core.editor "vim"; then
        current_editor="$("$git_bin" config --global core.editor 2>/dev/null || true)"
        if [ "$current_editor" = "vim" ]; then
            print_ok "Git editor set to vim"
            mark_validated_ok
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
        mark_validated_ok
        return 0
    fi

    ensure_dir "$(dirname "$target_dir")"

    if [ -n "$clone_args" ]; then
        if spinner_run "Clone $(basename "$repo_url")" bash -lc "\"$git_bin\" clone $clone_args \"$repo_url\" \"$target_dir\""; then
            if [ -d "$target_dir/.git" ] || [ -d "$target_dir" ]; then
                CLONED_REPOS=$((CLONED_REPOS + 1))
                print_ok "Cloned repo: $target_dir"
                mark_validated_ok
            else
                print_error "Clone reported success but repo missing: $target_dir"
                mark_validated_fail
            fi
        else
            print_error "Could not clone $repo_url"
            mark_validated_fail
        fi
    else
        if spinner_run "Clone $(basename "$repo_url")" "$git_bin" clone "$repo_url" "$target_dir"; then
            if [ -d "$target_dir/.git" ] || [ -d "$target_dir" ]; then
                CLONED_REPOS=$((CLONED_REPOS + 1))
                print_ok "Cloned repo: $target_dir"
                mark_validated_ok
            else
                print_error "Clone reported success but repo missing: $target_dir"
                mark_validated_fail
            fi
        else
            print_error "Could not clone $repo_url"
            mark_validated_fail
        fi
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
            mark_validated_ok
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
            mark_validated_ok
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
            mark_validated_ok
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
        mark_validated_ok
        return 0
    fi

    ensure_dir "$(dirname "$plug_path")"

    if spinner_run "Install vim-plug" curl -fLo "$plug_path" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
        if verify_path_exists "$plug_path"; then
            print_ok "vim-plug installed"
            mark_validated_ok
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
        mark_validated_ok
        return 0
    fi

    if [ ! -f "${HOME}/.vimrc" ]; then
        print_skip ".vimrc not found"
        mark_validated_ok
        return 0
    fi

    if [ ! -f "${HOME}/.vim/autoload/plug.vim" ]; then
        print_skip "vim-plug not found"
        mark_validated_ok
        return 0
    fi

    if [ -d "${HOME}/.vim/plugged" ]; then
        print_skip "Vim plugins already installed"
        mark_validated_ok
        return 0
    fi

    ensure_dir "${HOME}/.vim"
    append_log "Vim plugin log: $vim_log"

    if [ "$DRY_RUN" = "1" ]; then
        print_info "[dry-run] Would run vim -N -V1${vim_log} -E -s -u ${HOME}/.vimrc '+PlugInstall --sync' '+qa!'"
        mark_validated_ok
        return 0
    fi

    if vim -N -V1"${vim_log}" -E -s -u "${HOME}/.vimrc" "+PlugInstall --sync" "+qa!" >>"$LOG_FILE" 2>&1; then
        if [ -d "${HOME}/.vim/plugged" ]; then
            print_ok "Vim plugins installed"
            mark_validated_ok
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
        mark_validated_ok
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
            mark_validated_ok
        else
            if spinner_run "Install font ${filename}" cp "$font_file" "${fonts_dest_dir}/${filename}"; then
                if verify_path_exists "${fonts_dest_dir}/${filename}"; then
                    INSTALLED_FONTS=$((INSTALLED_FONTS + 1))
                    print_ok "Installed font: ${filename}"
                    mark_validated_ok
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
        mark_validated_ok
    fi

    if is_linux && [ "$INSTALLED_FONTS" -gt 0 ] && command_exists fc-cache; then
        if spinner_run "Refresh font cache" fc-cache -f "$fonts_dest_dir"; then
            print_ok "Font cache refreshed"
            mark_validated_ok
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
        mark_validated_ok
        return 0
    fi

    if [ "${TMUX_CONFIG_CHANGED:-0}" != "1" ]; then
        print_skip "tmux plugins unchanged; install not needed"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Install tmux plugins" "$installer"; then
        print_ok "tmux plugins installed"
        mark_validated_ok
    else
        print_warn "tmux plugin install failed"
        mark_validated_fail
    fi
}

reload_tmux_config_if_running() {
    local tmux_conf="${CONFIG_HOME}/tmux/tmux.conf"

    if [ "$SCHEDULED" = "1" ]; then
        print_skip "Scheduled mode: skipping tmux reload"
        mark_validated_ok
        return 0
    fi

    if [ "${TMUX_CONFIG_CHANGED:-0}" != "1" ]; then
        print_skip "tmux config unchanged; reload not needed"
        mark_validated_ok
        return 0
    fi

    if ! command_exists tmux; then
        print_skip "tmux not available"
        mark_validated_ok
        return 0
    fi

    if ! tmux ls >/dev/null 2>&1; then
        print_skip "No tmux server running"
        mark_validated_ok
        return 0
    fi

    if [ ! -f "$tmux_conf" ]; then
        print_skip "tmux config not found"
        mark_validated_ok
        return 0
    fi

    if spinner_run "Reload tmux config" tmux source-file "$tmux_conf"; then
        print_ok "tmux config reloaded"
        mark_validated_ok
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