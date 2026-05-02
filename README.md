```

▗▄▄▖  ▗▄▖  ▗▄▖▗▄▄▄▖▗▄▄▖▗▄▄▄▖▗▄▄▖  ▗▄▖ ▗▄▄▖ 
▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌ █ ▐▌     █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
▐▛▀▚▖▐▌ ▐▌▐▌ ▐▌ █  ▝▀▚▖  █  ▐▛▀▚▖▐▛▀▜▌▐▛▀▘ 
▐▙▄▞▘▝▚▄▞▘▝▚▄▞▘ █ ▗▄▄▞▘  █  ▐▌ ▐▌▐▌ ▐▌▐▌   


```

_Disclaimer: This repo is public primarily for convenience. It allows the bootstrap process to run without requiring prior authentication (for example, installing 1Password or configuring `gh` first)._

A cross-platform bootstrap script for bringing up a fresh machine with:

- shell + terminal setup
- developer tooling
- dotfiles symlinks
- macOS preferences
- applications (Alacritty, GitHub Desktop, 1Password, etc.)

Goals:

- **idempotent** (safe to re-run)
- **resilient** (keeps going when individual steps fail)
- **verifiable** (checks results after each action)
- **readable** (clear tagged output with a persistent progress bar)

---

## ━━ Quick Start

On macOS, grant your terminal app **Full Disk Access** before running the script:

_System Settings → Privacy & Security → Full Disk Access_

This is required for some settings writes, including Safari preferences.

```bash
git clone https://github.com/bwoodruff/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

On the first run, if your `git` `origin` is behind the remote (same branch) and a fast-forward is possible, the script fetches, pulls, and **restarts itself once** so the rest of the run uses the current repo contents (including any updated `lib/*.sh` files). Use `--no-auto-update` to skip that.

---

## ━━ What It Does

The bootstrap script runs in phases for setup, tooling, configuration, and validation.

### Core Features

- Installs and updates packages via Homebrew (macOS) or the system package manager (Linux); on macOS, **package checks** also ensure the **`mas`** CLI is present (for Mac App Store installs). **`mas`** is skipped on Linux
- Installs apps like:
  - Alacritty
  - GitHub CLI (`gh`)
  - GitHub Desktop
  - Alfred (Homebrew cask when no existing install, or when `--force-brew` overrides a non-Homebrew copy)
  - 1Password (desktop, **1Password for Safari** via `mas` + Mac App Store, CLI)
  - GPG
- Sets up:
  - `.zshrc`, `.vimrc`, tmux config, etc.
  - Oh My Zsh + Powerlevel10k
- Applies macOS preferences through a declarative defaults engine (including menu bar clock and Dock)
- Applies Dock and Finder preferences through the same validation model
- Installs fonts
- Ensures `$HOME/.hushlogin` exists (suppresses shell login banners like "Last login")
- Verifies outcomes after each step
- Automatically clears macOS quarantine attributes for downloaded binaries when appropriate
- Supports scheduled maintenance runs

---

## ━━ Script Behavior

### Idempotent

You can safely run the script repeatedly:

```bash
./install.sh
./install.sh --pull-dotfiles
./install.sh --scheduled
```

Nothing should be duplicated or broken on re-run. The script checks current state first and only changes what needs changing.

### Self-update

By default, the bootstrap compares your checked-out branch to `origin` (no version tags or releases: it uses `git` commits on the current branch). If you are **behind** the remote, the working tree is **clean**, and a **fast-forward** is possible, it runs `git pull --ff-only` and **re-executes** `install.sh` with the same arguments so loaded shell code matches the tree on disk. The second run will not pull again in a loop.

Self-update is skipped when it would be unsafe or ambiguous, including: dry-run mode, **uncommitted or unstaged changes** in the dotfiles repo, local commits not on the remote, pull or fetch errors, a detached `HEAD`, and when `origin` is not a clone of this repo (unless you allow it; see the table below). The install script and `DOTFILES_DIR` are expected to point at the same repository.

`--pull-dotfiles` (for example in scheduled mode) still runs a pull during the **Git** task, but the **default self-update** runs earlier. If a self-update already pulled, the later pull is skipped as redundant.

| Variable | Default | Meaning |
|----------|---------|---------|
| `DOTFILES_AUTO_UPDATE` | `1` | Set to `0` to never fetch/restart for updates (same as `--no-auto-update`) |
| `DOTFILES_UPSTREAM_GITHUB` | `bwoodruff/dotfiles` | Expected `org/repo` for `origin` (after normalizing `https` / `git@` URLs) |
| `DOTFILES_SELF_UPDATE_ANY_ORIGIN` | `0` | Set to `1` to run self-update even when `origin` is not that GitHub path (for example a fork) |

---

### Trust But Verify

Actions are validated where practical:

- install → check binary or app exists
- symlink → verify correct target
- defaults write → read back and verify expected value
- permissions/xattrs → re-check resulting state

Failures are logged, and execution continues when safe.

---

### Logging

Logs are written to:

```text
~/.local/state/dotfiles/install.log
```

Logging behavior:

- timestamped entries
- structured output
- command output grouped under the relevant action
- log retention
- clear end-of-run summary counters

---

### Visual Output

- sectioned output
- clean `[INFO] [RUN] [OK] [WARN] [FAIL] [SKIP]` tags
- persistent progress bar
- optional `fastfetch` block near the end
- readable spacing and grouping

---

### Next Steps

The script may print a **Next steps** section at the end of the run.

- Only shown when manual follow-up is required
- Organized by tool (for example GitHub CLI, 1Password, or GPG)
- Each subsection appears only when relevant

This keeps output concise while still surfacing manual follow-up.

---

## ━━ Flags

```bash
./install.sh [options]
```

| Flag | Description |
|------|-------------|
| `--force-brew` | Install configured Homebrew formulas even if the command already exists |
| `--dry-run` | Show what would happen without making changes |
| `--quiet` | Reduce terminal output |
| `--scheduled` | Non-interactive maintenance mode; implies `--pull-dotfiles` and skips prompts/runtime reloads |
| `--pull-dotfiles` | Run `git pull --ff-only` in `~/dotfiles` before applying changes |
| `--no-auto-update` | Do not fetch / fast-forward / re-exec at startup (see [Self-update](#self-update)) |
| `--strict-optional-configs` | Treat missing optional config sources as warnings |
| `--no-schedule` | Do not create/check the weekly scheduled run |
| `--no-upgrade` | Skip package-manager update/upgrade step |
| `-h`, `--help` | Show help |

---

## ━━ Platform Behavior Matrix

Quick reference for what runs where:

- **Runs on both macOS and Linux**
  - package checks and upgrades
  - Alacritty (Linux: `apt` / `dnf` / `pacman`; macOS: GitHub release DMG)
  - symlink/config setup
  - git / dotfiles update flow (default [self-update](#self-update) at startup, optional `--pull-dotfiles` in the Git task)
  - fonts, vim, tmux, GPG, 1Password, scheduling, fastfetch
- **macOS-only**
  - Homebrew bootstrap task
  - **`mas`** Homebrew formula during package checks (Mac App Store CLI; not used on Linux)
  - GitHub Desktop install
  - Alfred (Homebrew cask), **1Password for Safari** (`mas` + `sudo mas get`, requires Mac App Store Apple ID)
  - declarative macOS / Dock / Finder preferences
  - launchd scheduler path
- **Linux-only**
  - Linux package-manager install paths (`apt` / `dnf` / `pacman`)
  - cron scheduler path
- **Interactive-only behaviors**
  - prompt-driven hostname setup
  - macOS preference task execution
  - live progress UI

---

## ━━ Safety And Side Effects

Operational notes to know before running:

- **Privilege use**
  - some install and system-level operations use `sudo`
  - the script caches sudo credentials when required
  - in interactive terminals, `sudo` commands run in the foreground (with output mirrored to the install log) so password prompts are not mixed with the spinner line
  - when stdin is not a TTY or `--scheduled` is used, `sudo` is invoked as `sudo -n` so unattended runs fail fast instead of hanging on a password prompt (configure **passwordless sudo** or equivalent for fully unattended upgrades/installs)
- **Restarts and reloads**
  - Finder may be restarted if Finder preferences changed
  - Dock may be restarted if Dock preferences changed
  - tmux config reload is skipped in scheduled mode
- **Mac App Store (`mas`)**
  - installing App Store apps uses **`sudo`** (cached like Homebrew when possible) and an **Apple ID signed into the App Store**; there is no `mas sign-in` for current macOS. If install fails, next steps tell you to open the App Store and sign in, then re-run
- **Scheduled mode behavior**
  - `--scheduled` implies `--pull-dotfiles` and quiet/non-interactive behavior
  - prompt-driven actions are skipped
  - package-manager steps that need elevation rely on non-interactive sudo (`sudo -n`); ensure your environment allows that (for example NOPASSWD rules for `dnf`/`apt` where appropriate)
- **Network and git**
  - unless `--no-auto-update` or `DOTFILES_AUTO_UPDATE=0`, the script may contact `git` `origin` once at the start; it does not send telemetry beyond normal `git` operations
- **Write locations**
  - updates files under your dotfiles targets and writes logs to `~/.local/state/dotfiles/`
  - can modify package-manager state and installed applications

---

## ━━ Project Structure

```text
.
├── install.sh
└── lib/
    ├── core.sh        # logging, UI, progress bar, task runner, shared helpers
    ├── packages.sh    # package managers + package install/upgrade logic
    ├── config.sh      # symlinks, dotfiles self-update, fonts, vim, tmux
    ├── apps.sh        # app installs (Alacritty, GitHub Desktop, Alfred, 1Password + mas, fastfetch, etc.)
    ├── macos.sh       # macOS defaults, Dock, Finder prefs, hostname handling
    └── scheduling.sh  # launchd / cron setup
```

Each module is intentionally scoped to keep maintenance manageable and avoid one monolithic shell script.

---

## ━━ Task Runner

The bootstrap flow is driven by a task list in `install.sh`.

Each task defines:

- section name
- function(s) to run (comma-separated for multi-step sections)
- platform scope
- whether interactivity is required

This keeps the top-level flow easy to read and easy to change.

---

## ━━ Function Naming Conventions

To keep shell code readable and avoid over-verbose helper names, functions follow a simple verb-first pattern:

- `is_*` / `has_*` for predicates that return success/failure
- `get_*` for value retrieval
- `print_*` for user-facing output
- `ensure_*` for idempotent "make sure this state exists"
- `install_*`, `remove_*`, `configure_*`, `setup_*` for imperative actions
- `verify_*` / `confirm_*` for post-action checks
- `mark_*` for counter/state bookkeeping side effects

Guidelines:

- Prefer concise names that communicate intent in 2-4 words.
- Avoid encoding implementation details in names unless needed for clarity.
- Keep related naming consistent across modules (for example, all package-manager predicates end in `_available`).
- If a helper only exists to support one flow, still name it as if it were a teammate-facing API.

Examples from this repo:

- `mark_command_installed`
- `remove_neofetch_via`
- `mark_1password_cli_installed`
- `print_tagged`

---

## ━━ Applications

### Alacritty

Install method depends on platform:

- macOS: installed from the latest GitHub release DMG
- Linux: installed via the system package manager (`apt`, `dnf`, or `pacman`)

### GitHub CLI (`gh`)

Installed via the active package manager:

- macOS: Homebrew
- Linux: `apt`, `dnf`, or `pacman`

If newly installed, the script may suggest:

```bash
gh auth login
gh auth setup-git
```

### GitHub Desktop

On macOS, installed from GitHub’s official distribution if not already present.

### 1Password

Install order on macOS:

1. Desktop app via Homebrew cask (if not present)
2. **1Password for Safari** via Homebrew **`mas`** + **`sudo mas get`** on the Mac App Store ID `1569813296` (skipped if the app is already in `/Applications`)
3. CLI (`op`) via Homebrew cask or Linux packages

Notes:

- Desktop app uses its built-in auto-updater
- The script does **not** modify 1Password application settings inside the apps
- **`mas`** is installed with Homebrew during **package checks** on macOS (same as `git`, `gh`, etc.); on Linux the installer **skips** `mas` because it is Mac App Store–only
- Mac App Store installs need an Apple ID session in the App Store app; the installer cannot sign in for you. If `mas` fails for account reasons, **Next steps** tells you to open the App Store, sign in, and re-run
- After a successful Safari app install, **Next steps** reminds you to enable the extension under Safari **Settings → Extensions**

### Alfred

On macOS, **Alfred** is installed with **`brew install --cask alfred`** when no Alfred app is found under `/Applications`, or when **`--force-brew`** is set and your existing copy is not managed by Homebrew (see `install_alfred_macos` in `lib/apps.sh`). The script does not change Spotlight shortcuts or Alfred’s sync folder; **Next steps** points you at your **AlfredSync** folder in iCloud Drive and the usual Spotlight / Alfred hotkey setup.

### GPG

Installs:

```bash
gnupg
```

If GPG is installed but no secret keys are present, the script may suggest retrieving your key material from 1Password and importing it.

---

## ━━ macOS Configuration

macOS settings are applied only in interactive runs (not `--scheduled` / non-interactive contexts).

### Interactive-only preference

The only prompt-driven preference is one-time hostname setup.

Hostname prompting is cookie-controlled so it is not repeated on every run.

### Declarative defaults engine

Most macOS defaults are now applied through a reusable declarative engine that:

- reads the current value
- compares it to the desired state
- writes only when needed
- verifies after writing

This includes global defaults (for example appearance/accent, Safari, trackpad, save/print panel preferences, and **menu bar clock**) plus **Dock** and **Finder** preferences.

Clock-related keys in `MACOS_DEFAULTS_COMMON` include **`AppleICUForce24HourTime`** on `NSGlobalDomain` (this is what actually forces 24-hour time in the menu bar on many macOS versions), plus **`com.apple.menuextra.clock`** (`Show24Hour`, **`ShowAMPM` false**, **`ShowDate` 1**, **`DateFormat` `MM/dd/yyyy`**). **`ShowAMPM` false** removes AM/PM; if the time still looks 12-hour until you toggle **System Settings → General → Language & Region → 24-Hour Time**, the ICU default above is the usual fix.

**Date format:** Apple often shows the date as a short month name plus day (for example `Apr 24`) in the menu bar even when `DateFormat` is set, because **Control Center** / menu bar modules can override legacy `menuextra.clock` formatting. The script still sets `DateFormat` when the system accepts it; for a strict numeric `MM/dd/yyyy` in the menu bar you may need an extra step in **System Settings → Control Center → Clock** (or adjust keys again after an OS upgrade).

If a defaults line fails verification, check `defaults read com.apple.menuextra.clock` and `defaults read -g AppleICUForce24HourTime`, then adjust `MACOS_DEFAULTS_COMMON` in `lib/macos.sh`.

If the menu bar clock does not refresh immediately after changes, logging out and back in or restarting **SystemUIServer** (`killall SystemUIServer`) often applies them without a full reboot.

### Dock

Dock preferences (same engine):

- autohide enabled
- **Recent applications** in the Dock hidden (`show-recents` false)

Dock is restarted only if something changed (skipped in scheduled mode, same pattern as Finder).

### Finder

Finder preferences are applied through the same engine, including settings such as:

- List view by default
- path bar
- status bar
- tab bar
- showing all filename extensions
- Home as the default new-window target
- current-folder search scope
- folders on top
- hiding selected desktop items

Finder is restarted only if something actually changed and a restart is needed.

---

## ━━ Scheduling

The script can configure weekly maintenance runs.

- macOS → `launchd`
- Linux → `cron`

Runs weekly:

```text
Monday @ 00:00
```

Scheduling logic lives in its own module: `lib/scheduling.sh`.

---

## ━━ Design Philosophy

- **Never fail fast** → always continue as far as possible
- **Verify everything**
- **Readable output > clever output**
- **No hidden magic**
- **Respect existing system state**
- **Prefer official distribution methods when they are a better fit**
- **Refactor toward declarative patterns when it reduces repetition**

---

## ━━ Current Areas of Focus

Recent refactoring themes:

- a declarative task runner
- a declarative macOS defaults engine
- cleaner separation of concerns across `lib/`
- less duplicated imperative shell code
- more consistent validation and output

Refactoring is ongoing.

---

## ━━ Attribution

The persistent progress bar implementation in this project was inspired by:

- **pollev/bash_progress_bar**
  - https://github.com/pollev/bash_progress_bar

The borrowed/adapted progress bar code is covered by the **MIT License** consistent with that upstream project.

```text
MIT License

Copyright (c) 2018 Polle Vanhoof

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

All other code in this repository is intentionally left **unlicensed** unless stated otherwise.

---

## ━━ Author

Benjamin Woodruff with assistance from ChatGPT/Cursor