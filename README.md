# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   Dotfiles Bootstrap
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
  - 1Password (desktop + CLI guidance)
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

Every action is validated:

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
- Desktop app uses built-in auto-updater
- Script does not override existing installs
- Safari extension install/enabling is nudged, not automated

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
- **Prefer official install methods where practical**

---

## ━━ Attribution

The persistent progress bar implementation in this project was developed with heavy inspiration from:

- **pollev/bash_progress_bar**
  - https://github.com/pollev/bash_progress_bar

The borrowed/adapted progress bar code is covered by the **MIT License** consistent with that upstream project.

All other code in this repository is intentionally left **unlicensed** unless stated otherwise.

---

## ━━ Author

Benjamin Woodruff