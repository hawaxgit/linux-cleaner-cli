# Linux Admin & Cleaner v2.0

A cross-distro Linux admin toolkit that combines **disk cleanup**, **network auditing**, **security checks**, **health monitoring**, and **developer cache cleanup** — all in a single hardened Bash script.

---

## ✨ What's New in v2.0

| Feature | v1 | v2 |
|---|---|---|
| Colored terminal output | ❌ | ✅ ANSI colors |
| Network analysis module | ❌ | ✅ ports, firewall, connections |
| Security audit module | ❌ | ✅ SUID, SSH, sudo, passwords |
| System health check | ❌ | ✅ CPU/RAM/disk/services |
| App cache cleaner | ❌ | ✅ npm/pip/cargo/go/maven/gradle |
| Markdown report output | ❌ | ✅ `--report` flag |
| Modular execution | ❌ | ✅ run any combination |
| ASCII banner | ❌ | ✅ |

---

## 📦 Modules

### `--clean` *(default)*
Package manager cache, systemd journal, temp files, large logs, user cache, Flatpak, Snap, Docker.

### `--network`
- Network interfaces and default gateway
- DNS resolver check
- All listening TCP ports with owning process
- Active established connection count
- Firewall status (ufw / firewalld / iptables)
- Scan for open sensitive ports (FTP, Telnet, SMB, Redis, MongoDB, etc.)

### `--security`
- SUID/SGID binary scan (outside standard paths)
- World-writable file detection
- `/etc/passwd` shell user review
- Empty/locked password account check
- SSH hardening check (`PermitRootLogin`, `PasswordAuthentication`, `X11Forwarding`, etc.)
- NOPASSWD sudo entry detection
- Recent failed login attempts

### `--health`
- Uptime
- CPU load average with threshold alerts
- Memory usage with low-memory warnings
- Disk usage per mount with >85% / >90% alerts
- Failed systemd services
- OOM kill detection from journal
- Top 10 memory-consuming processes

### `--app-cache`
- npm cache
- pip / pip3 cache
- Cargo (Rust) registry
- Go module cache
- Maven local repository
- Gradle caches

---

## 🖥️ Supported Distributions

| Distro | Package Manager |
|---|---|
| Ubuntu / Debian | `apt` |
| Arch Linux | `pacman` + `paccache` |
| Fedora / RHEL | `dnf` |
| CentOS (older) | `yum` |
| openSUSE | `zypper` |
| Alpine Linux | `apk` |

---

## 🚀 Installation

**Option 1 — Run directly:**
```bash
git clone https://github.com/hawaxgit/linux-admin-cleaner.git
cd linux-admin-cleaner
chmod +x linux-admin-cleaner.sh
sudo ./linux-admin-cleaner.sh --dry-run --all
```

**Option 2 — Install globally:**
```bash
chmod +x linux-admin-cleaner.sh
sudo ./linux-admin-cleaner.sh --install
# Then run from anywhere:
sudo linux-admin-cleaner.sh --yes --all
```

---

## ⚙️ Usage

```bash
sudo ./linux-admin-cleaner.sh [OPTIONS] [MODULES]
```

### Modules

| Flag | Description |
|---|---|
| `--clean` | Run disk/package cleanup *(default if no module specified)* |
| `--network` | Run network analysis & port audit |
| `--security` | Run security audit |
| `--health` | Run system health check |
| `--app-cache` | Clean developer/app caches |
| `--all` | Enable all modules |

### Options

| Flag | Description |
|---|---|
| `--install` | Install script to `/usr/local/bin` |
| `--dry-run` | Preview commands without executing |
| `--yes` | Non-interactive, auto-confirm all prompts |
| `--profile safe\|normal\|aggressive` | Cleanup aggressiveness (default: `normal`) |
| `--docker` | Enable Docker cleanup |
| `--no-user-cache` | Skip `~/.cache` cleanup |
| `--report [FILE]` | Generate Markdown report (default: `/tmp/report-DATE.md`) |
| `--version` | Show version |
| `-h, --help` | Show help |

---

## 💡 Examples

```bash
# Preview everything, no changes
sudo ./linux-admin-cleaner.sh --dry-run --all

# Safe cleanup only, non-interactive
sudo ./linux-admin-cleaner.sh --yes --profile safe

# Full aggressive cleanup + Docker
sudo ./linux-admin-cleaner.sh --yes --profile aggressive --docker

# Security + network audit with report
sudo ./linux-admin-cleaner.sh --yes --security --network --report /root/audit.md

# Full run with report saved to custom path
sudo ./linux-admin-cleaner.sh --yes --all --report /root/reports/$(hostname)-$(date +%F).md

# Health check + app cache cleanup only
sudo ./linux-admin-cleaner.sh --yes --health --app-cache
```

---

## 🔒 Profiles

| Profile | Journal Retention | Log Truncation Threshold | Behavior |
|---|---|---|---|
| `safe` | 30 days | > 500MB | Conservative, minimal risk |
| `normal` | 14 days | > 100MB | Balanced, recommended default |
| `aggressive` | 7 days | > 50MB | Deep clean, prompts for destructive actions |

---

## 📋 Report Output

Use `--report` to generate a structured Markdown report:

```bash
sudo ./linux-admin-cleaner.sh --yes --all --report /tmp/server-audit.md
```

The report includes:
- System metadata (hostname, distro, kernel, date)
- Network findings with open port table
- Security findings with severity indicators
- Health metrics and alerts
- Disk usage before/after
- Space freed summary

---

## 📁 What Gets Cleaned

Depending on active modules and options:

- Package manager cache (apt, pacman, dnf, yum, zypper, apk)
- Orphan packages (Arch)
- systemd journal logs
- Temporary files (`/tmp`, `/var/tmp`)
- Large files in `/var/log`
- User cache (`~/.cache`)
- Unused Flatpak runtimes
- Disabled Snap revisions
- Unused Docker resources *(optional)*
- npm, pip, cargo, Go, Maven, Gradle caches *(--app-cache)*

---

## ⚠️ Safety Notes

- Always run `--dry-run` first on production systems
- The security audit is **read-only** — it never modifies files
- User cache cleanup may cause apps to rebuild on next launch
- Docker cleanup with `--profile aggressive` removes **all** unused images and volumes
- On Arch: `paccache` requires `pacman-contrib`

---

## 📄 Logs

Runtime log is always written to:
```
/tmp/linux-admin-cleaner_YYYYMMDD_HHMMSS.log
```

---

## 🗺️ Roadmap

- [ ] `--exclude` option (skip specific paths/modules)
- [ ] systemd timer installer (scheduled cleanup)
- [ ] HTML report format
- [ ] Email report delivery
- [ ] GitHub Actions CI with ShellCheck
- [ ] Rootkit basic detection (chkrootkit/rkhunter wrapper)
- [ ] Automatic update check

---

## 📜 License

MIT

---

## 🤝 Contributing

Pull requests, issues, and improvements are welcome.

When reporting a bug, please include:
- Distro name and version
- Command output or error message
- The exact command you ran (`--dry-run` output is very helpful)

---

## 👤 Author

**Soroush @ Hawax**
