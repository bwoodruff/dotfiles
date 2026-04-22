#   Dotfiles Bootstrap

_Disclaimer: This repo is public primarily for my benefit. It makes it easier to utilize the project as intended. If I had to sign into GitHub before I could access the project, I’d first have to install and set up 1Password, install `gh`, run `gh auth login`, and so on. I want to be able to clone this repo, run the script, and have the essentials largely in place._

A cross-platform bootstrap script for configuring a fresh system with:

- shell + terminal setup
- developer tooling
- dotfiles symlinks
- macOS preferences
- applications (Alacritty, GitHub Desktop, 1Password, etc.)

Designed to be:

- **idempotent** (safe to re-run)
- **resilient** (never stops on failure)
- **verifiable** (“trust but verify” after every step)
- **visually clean** (fastfetch-style output with persistent progress bar)

---

## ━━ Quick Start

```bash
git clone https://github.com/bwoodruff/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

---

## ━━ What It Does

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Environment  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Homebrew     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Directory    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Packages     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Apps         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Config       ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  macOS        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Summary      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Core features

- Installs and updates packages via Homebrew (macOS) or the system package manager (Linux)
- Installs apps like:
  - Alacritty
  - GitHub CLI (`gh`)
  - GitHub Desktop
  - 1Password
  - GPG
- Sets up:
  - `.zshrc`, `.vimrc`, tmux config, etc.
  - Oh My Zsh + Powerlevel10k
- Applies macOS preferences through a declarative defaults engine
- Applies Finder preferences through the same validation model
- Installs fonts
- Runs validation after every step
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

---

### Trust but Verify

Every action is validated (“trust but verify”):

- install → check binary or app exists
- symlink → verify correct target
- defaults write → read back and verify expected value
- permissions/xattrs → re-check resulting state

Failures are logged but the script continues as far as it reasonably can.

---

### Logging

Logs are written to:

```text
~/.local/state/dotfiles/install.log
```

Features:

- timestamped entries
- structured output
- command output indented underneath the relevant action
- log retention
- clear end-of-run summary counters

---

### Visual Output

- sectioned output
- clean `[INFO] [RUN] [OK] [WARN] [FAIL] [SKIP]` tags
- persistent progress bar
- optional fastfetch block near the end
- readable spacing and grouping

---

### Next Steps

The script may output a **Next steps** section at the end of the run.

- Only shown when manual follow-up is required
- Organized by tool (for example GitHub CLI, 1Password, or GPG)
- Each subsection appears only when relevant

This keeps output clean while still surfacing the things you actually need to do.

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
| `--strict-optional-configs` | Treat missing optional config sources as warnings |
| `--no-schedule` | Do not create/check the weekly scheduled run |
| `--no-upgrade` | Skip package-manager update/upgrade step |
| `-h`, `--help` | Show help |

---

## ━━ Project Structure

```text
.
├── install.sh
└── lib/
    ├── core.sh        # logging, UI, progress bar, task runner, shared helpers
    ├── packages.sh    # package managers + package install/upgrade logic
    ├── config.sh      # symlinks, dotfiles repo helpers, fonts, vim, tmux
    ├── apps.sh        # app installs (Alacritty, GitHub Desktop, 1Password, fastfetch, etc.)
    ├── macos.sh       # macOS defaults, Finder prefs, hostname handling
    └── scheduling.sh  # launchd / cron setup
```

Each module is intentionally scoped to keep the system maintainable and avoid one giant shell script.

---

## ━━ Task Runner

The bootstrap flow is driven by a declarative task list in `install.sh`.

Each task defines:

- section name
- function to run
- platform scope
- whether interactivity is required

That keeps the top-level flow readable and makes it easier to reorder, add, or skip work without rewriting the whole script.

---

## ━━ Applications

### Alacritty

Installed from GitHub releases rather than Homebrew.

### GitHub CLI (`gh`)

Installed via Homebrew.

If newly installed, the script may suggest:

```bash
gh auth login
gh auth setup-git
```

### GitHub Desktop

On macOS, installed from GitHub’s official distribution if not already present.

### 1Password

Install flow:

1. Desktop app (if not present)
2. Safari extension reminder/check
3. CLI (`op`)

Notes:

- Desktop app uses its built-in auto-updater
- Script does **not** modify 1Password application settings
- Safari extension installation/enabling is nudged, not fully automated

### GPG

Installs:

```bash
gnupg
```

If GPG is installed but no secret keys are present, the script may suggest retrieving your key material from 1Password and importing it.

---

## ━━ macOS Configuration

macOS settings are applied in interactive mode.

### Higher-level interactive preferences

The script can handle a small set of higher-level/personal preferences interactively, such as:

- dark appearance
- purple accent color
- one-time hostname setup

Hostname prompting is cookie-controlled so it is not repeated on every run.

### Declarative defaults engine

Most macOS defaults are now applied through a reusable declarative engine that:

- reads the current value
- compares it to the desired state
- writes only when needed
- verifies after writing

This includes many of the lower-level defaults and Finder preferences.

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

The script can self-schedule weekly maintenance runs.

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
- **Prefer official distribution methods when they offer a better result**
- **Refactor toward declarative patterns when it reduces repetition**

---

## ━━ Current Areas of Focus

The repo has recently been moving toward:

- a declarative task runner
- a declarative macOS defaults engine
- cleaner separation of concerns across `lib/`
- less duplicated imperative shell code
- more consistent validation and output

Further refactoring is ongoing.

---

## ━━ Attribution

The persistent progress bar implementation in this project was developed with heavy inspiration from:

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

Benjamin Woodruff with assistance from ChatGPT