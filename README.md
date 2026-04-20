# 
#   Dotfiles Bootstrap
# 

_Disclaimer: This repo is public primarily for my benefit. It makes it easier to utilize the project as intended... If I had to sign into GitHub before I could access the project I'd have to install and set up 1Password, install `gh` and run `gh auth login`, ... etc. I just want to be able to clone this repo, run the script, and have the essentials largely in place.__

A cross-platform bootstrap script for configuring a fresh system with:

- shell + terminal setup
- developer tooling
- dotfiles symlinks
- macOS preferences
- applications (Alacritty, 1Password, etc.)

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
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Packages     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Apps         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Config       ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  macOS        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  Summary      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Core features

- Installs and updates packages via Homebrew (macOS) or system package manager (Linux)
- Installs apps like:
  - Alacritty (GitHub release)
  - GitHub CLI (`gh`)
  - 1Password (desktop + CLI setup)
  - GPG
- Sets up:
  - `.zshrc`, `.vimrc`, tmux config, etc.
  - Oh My Zsh + Powerlevel10k (non-interrupting)
- Applies macOS preferences:
  - dark mode
  - purple accent color
  - natural scrolling
  - Finder configuration
- Installs fonts
- Runs validation after every step
- Automatically clears macOS quarantine attributes for downloaded binaries to prevent first-launch Gatekeeper prompts

---

## ━━ Script Behavior

### Idempotent

You can safely run the script repeatedly:

```bash
./install.sh
./install.sh --pull-dotfiles
./install.sh --scheduled
```

Nothing is duplicated or broken on re-run.

---

### Trust but Verify

Every action is validated (“trust but verify”):

- install → check binary exists
- symlink → verify correct target
- permission → re-check mode/xattr

Failures are logged but **never stop execution**.

---

### Logging

Logs are written to:

```text
~/.local/state/dotfiles/install.log
```

Features:
- timestamped entries
- structured output
- command output indented
- retention:
  - first run preserved permanently
  - last 7 runs kept

---

### Visual Output

- fastfetch-style sections
- clean `[INFO] [RUN] [OK] [WARN] [FAIL]` tags
- persistent progress bar
- readable spacing and grouping

---

### Next Steps

The script may output a **Next steps** section at the end of the run.

- Only shown when manual follow-up is required
- Organized by tool (e.g. GitHub CLI, 1Password, GPG)
- Each subsection appears only when relevant

This keeps output clean while still guiding required manual steps.

---

## ━━ Flags

```bash
./install.sh [options]
```

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would happen without making changes |
| `--quiet` | Minimal output |
| `--scheduled` | Non-interactive mode (for cron/launchd) |
| `--pull-dotfiles` | Pull latest changes before applying |
| `--force-brew` | Prefer Homebrew even if system tools exist |

---

## ━━ Project Structure

```text
.
├── install.sh
└── lib/
    ├── core.sh       # logging, UI, progress bar, helpers
    ├── packages.sh   # package managers + installs
    ├── config.sh     # symlinks, git config, dotfiles
    ├── apps.sh       # app installs (Alacritty, 1Password, etc.)
    └── macos.sh      # macOS preferences
```

Each module is intentionally scoped to keep the system maintainable and avoid large monolithic scripts.

---

## ━━ Applications

### Alacritty
Installed from GitHub releases (not Homebrew).

### GitHub CLI (`gh`)
Installed via Homebrew.

If newly installed:

```bash
gh auth login
gh auth setup-git
```

### 1Password

Install flow:

1. Desktop app (if not present)
2. Safari extension (manual prompt)
3. CLI (`op`) via Homebrew

Notes:
- Desktop app uses its built-in auto-updater
- Script does **not** modify 1Password application settings
- Some settings (e.g. SSH agent, CLI integration) are integrity-protected and must be configured inside the app
- Safari extension installation/enabling is nudged, not automated

### GPG

Installs:

```bash
gnupg
```

Next steps (manual):

```bash
gpg --full-generate-key
gpg --list-secret-keys
```

---

## ━━ macOS Configuration

Applies safe defaults in interactive mode only.

### System
- Dark mode
- Purple accent color
- Natural scroll direction

### Finder
- List view
- Path bar + status bar + tab bar
- Show all filename extensions
- New windows open to Home
- Search current folder
- Folders on top
- Cleaned-up Finder behavior/preferences

---

## ━━ Scheduling

The script can self-schedule:

- macOS → `launchd`
- Linux → `cron`

Runs weekly:

```text
Monday @ 00:00
```

---

## ━━ Design Philosophy

- **Never fail fast** → always continue
- **Verify everything**
- **Readable output > clever output**
- **No hidden magic**
- **Respect existing system state**
- **Prefer official distribution methods when they provide better update or security guarantees (e.g. 1Password, Alacritty)**

---

## ━━ Attribution

The persistent progress bar implementation in this project was developed with heavy inspiration from:

- **pollev/bash_progress_bar**
  - https://github.com/pollev/bash_progress_bar

The borrowed/adapted progress bar code is covered by the **MIT License** consistent with that upstream project.

```
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