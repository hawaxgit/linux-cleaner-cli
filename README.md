# Linux Cleaner

A cross-distro Linux cleanup script that safely frees disk space by cleaning package caches, logs, temp files, and optional Docker/Flatpak/Snap data.

## Features

- ✅ Cross-distro support (auto-detects package manager)
- ✅ Safe cleanup (no risky automatic kernel removal)
- ✅ Package cache cleanup
- ✅ System journal cleanup (`journalctl`)
- ✅ Temporary file cleanup (`/tmp`, `/var/tmp`)
- ✅ Large log truncation in `/var/log`
- ✅ Optional user cache cleanup (`~/.cache`)
- ✅ Optional Flatpak cleanup
- ✅ Optional Snap cleanup (disabled revisions)
- ✅ Optional Docker cleanup
- ✅ `--dry-run` mode (preview commands before execution)
- ✅ `--install` mode (install to `/usr/local/bin`)
- ✅ Cleanup profiles: `safe`, `normal`, `aggressive`

---

## Supported Distributions

The script is designed to work on:

- **Ubuntu / Debian** (`apt`)
- **Arch Linux** (`pacman`)
- **Fedora / RHEL** (`dnf` / `yum`)
- **openSUSE** (`zypper`)
- **Alpine Linux** (`apk`)

---

## Why this script?

This project is built as a **safe baseline Linux cleaner**.

It avoids dangerous actions like:
- automatic kernel removal
- blindly deleting critical directories
- distro-specific destructive commands without checks

It is meant to be a practical CLI tool you can run on personal systems, workstations, and servers.

---

## Installation

### Option 1: Run directly

```bash
chmod +x linux-cleaner.sh
./linux-cleaner.sh --dry-run
```

### Option 2: Install globally

```bash
chmod +x linux-cleaner.sh
./linux-cleaner.sh --install
```

Then run it from anywhere:

```bash
linux-cleaner.sh --yes
```

---

## Usage

```bash
./linux-cleaner.sh [OPTIONS]
```

### Available Options

- `--install` → Install script to `/usr/local/bin`
- `--dry-run` → Show commands only (do not execute)
- `--yes` → Non-interactive mode (auto-confirm prompts)
- `--profile safe|normal|aggressive` → Cleanup profile (default: `normal`)
- `--docker` → Enable Docker cleanup
- `--no-user-cache` → Skip cleaning user cache (`~/.cache`)
- `--version` → Show script version
- `-h, --help` → Show help

---

## Examples

### Preview cleanup without making changes

```bash
./linux-cleaner.sh --dry-run --profile safe
```

### Run normal cleanup (non-interactive)

```bash
./linux-cleaner.sh --yes
```

### Run aggressive cleanup with Docker cleanup enabled

```bash
./linux-cleaner.sh --yes --profile aggressive --docker
```

### Skip user cache cleanup

```bash
./linux-cleaner.sh --yes --no-user-cache
```

---

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

---

## Logs

The script writes a runtime log file to:

```bash
/tmp/linux-cleaner_YYYYMMDD_HHMMSS.log
```

This helps with troubleshooting and reviewing what was cleaned.

---

## Roadmap

- [ ] `--report` (Markdown / HTML summary output)
- [ ] `--exclude` option (skip selected cache paths)
- [ ] App cache cleanup (`npm`, `pip`, `cargo`, etc.)
- [ ] systemd timer installer (scheduled cleanup)
- [ ] Colored output / improved CLI UI
- [ ] GitHub Actions with `shellcheck`

---

## License

MIT

---

## Contributing

Pull requests, ideas, and improvements are welcome.

If you find a distro-specific issue, please open an issue with:

- distro name and version
- command output / error message
- the exact command you ran (`--dry-run` output is very helpful)

---

## Author

Soroush @ Hawax
