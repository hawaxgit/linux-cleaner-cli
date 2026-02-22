# linux-cleaner-cli
Linux Cleaner is a cross-distro CLI tool for safely reclaiming disk space on Linux systems by cleaning package caches, system logs, temporary files, and optional container/package manager leftovers.

# Linux Cleaner

A cross-distro Linux cleanup script for freeing disk space safely.

It supports:

- Ubuntu / Debian (APT)
- Arch Linux (pacman)
- Fedora / RHEL (dnf / yum)
- openSUSE (zypper)
- Alpine (apk)

## Features

- Auto-detects distro and package manager
- Safe temp cleanup (`systemd-tmpfiles` if available)
- Journal cleanup (`journalctl --vacuum-time=...`)
- Large log truncation in `/var/log`
- Optional user cache cleanup (`~/.cache`)
- Optional Flatpak cleanup
- Optional Snap cleanup (disabled revisions)
- Optional Docker cleanup
- Profiles: `safe`, `normal`, `aggressive`
- `--dry-run` mode (preview commands without running)
- `--install` to install into `/usr/local/bin`

## Why this script?

This script is made as a **safe baseline cleaner**.  
It avoids risky actions like automatic kernel removal and does not blindly wipe critical directories.

## Installation

### Option 1: Run directly
```bash
chmod +x linux-cleaner.sh

./linux-cleaner.sh --dry-run
```
## Then run it from anywhere:
```bash
linux-cleaner.sh --yes
```

## Usage
````bash
./linux-cleaner.sh [OPTIONS]
````

## Available Options
- `--install` → Install script to `/usr/local/bin`
- `--dry-run` → Show commands only (do not execute)
- `--yes` → Non-interactive mode (auto-confirm prompts)
- `--profile safe|normal|aggressive` → Cleanup profile (default: `normal`)
- `--docker` → Enable Docker cleanup
- `--no-user-cache` → Skip cleaning user cache (`~/.cache`)
- `--version` → Show script version
- `-h, --help` → Show help

## Examples
# Preview cleanup without making changes
````bash
./linux-cleaner.sh --dry-run --profile safe
````
# Run normal cleanup (non-interactive)
````bash
./linux-cleaner.sh --yes
````
## Run aggressive cleanup with Docker cleanup enabled
````bash
./linux-cleaner.sh --yes --profile aggressive --docker
````
## Skip user cache cleanup
````bash
./linux-cleaner.sh --yes --no-user-cache
````
## Profiles

### `safe`
- Keeps more journal logs
- Truncates only very large log files
- Most conservative cleanup behavior

### `normal`
- Balanced cleanup mode
- Recommended default for most users

### `aggressive`
- Cleans more aggressively
- Shorter journal retention
- Smaller log truncation threshold
- Can prune Docker more deeply (with confirmation)

---

## What gets cleaned?

Depending on your distro and enabled options, the script may clean:

- package manager cache (`apt`, `pacman`, `dnf`, `yum`, `zypper`, `apk`)
- orphan packages (Arch Linux / `pacman`)
- systemd journal logs
- temporary files (`/tmp`, `/var/tmp`)
- very large files in `/var/log`
- user cache (`~/.cache`)
- unused Flatpak runtimes/apps
- disabled Snap revisions
- unused Docker resources (optional)

---

## Safety Notes

- Some actions require `sudo`
- Always use `--dry-run` first if you want to preview actions
- User cache cleanup may cause apps (browser/IDE/etc.) to rebuild cache on next launch
- On Arch Linux, `paccache` is provided by `pacman-contrib`
- Docker cleanup can remove unused images, containers, and volumes (depending on mode)

## Author

Soroush @ hawaxgit
