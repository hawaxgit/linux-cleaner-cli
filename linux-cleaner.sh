#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Linux Cleaner (Cross-Distro Base)
# Supports: Ubuntu/Debian, Arch, Fedora/RHEL, openSUSE, Alpine
# ==========================================

VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/${SCRIPT_NAME%.sh}_$(date +%Y%m%d_%H%M%S).log"

DRY_RUN=0
AUTO_YES=0
DO_INSTALL=0
PROFILE="normal"           # safe | normal | aggressive
ENABLE_DOCKER=0
CLEAN_USER_CACHE=1

# ---------- Root helper ----------
SUDO=()
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    echo "This script needs root privileges (sudo not found)." >&2
    exit 1
  fi
fi

# ---------- Helpers ----------
log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

cmd_to_string() {
  local out="" part
  for part in "$@"; do
    printf -v part '%q' "$part"
    out+="$part "
  done
  echo "${out% }"
}

run_cmd() {
  local desc="$1"; shift
  local cmd_str
  cmd_str="$(cmd_to_string "$@")"
  log "$desc"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[DRY-RUN] $cmd_str"
    return 0
  fi

  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ $rc -ne 0 ]]; then
    log "WARN: Command failed (exit $rc): $cmd_str"
    return $rc
  fi
  return 0
}

confirm() {
  local msg="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    return 0
  fi
  read -rp "$msg (y/n): " response
  [[ "$response" =~ ^[Yy]$ ]]
}

show_help() {
  cat <<EOF
Linux Cleaner v$VERSION

Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --install               Install script to /usr/local/bin
  --dry-run               Show commands only (do not execute)
  --yes                   Non-interactive mode (auto-confirm)
  --profile PROFILE       safe | normal | aggressive (default: normal)
  --docker                Enable Docker cleanup (if docker exists)
  --no-user-cache         Skip cleaning user cache (~/.cache)
  --version               Show version
  -h, --help              Show help

Examples:
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --yes --profile safe
  $SCRIPT_NAME --yes --profile aggressive --docker
  $SCRIPT_NAME --install
EOF
}

# ---------- Parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) AUTO_YES=1 ;;
    --docker) ENABLE_DOCKER=1 ;;
    --no-user-cache) CLEAN_USER_CACHE=0 ;;
    --version)
      echo "$VERSION"
      exit 0
      ;;
    --profile)
      shift
      PROFILE="${1:-}"
      if [[ ! "$PROFILE" =~ ^(safe|normal|aggressive)$ ]]; then
        echo "Invalid profile. Use: safe | normal | aggressive" >&2
        exit 1
      fi
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help
      exit 1
      ;;
  esac
  shift
done

# ---------- Real user / home ----------
TARGET_USER="${SUDO_USER:-$(id -un)}"
if require_cmd getent; then
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || true)"
else
  TARGET_HOME=""
fi
TARGET_HOME="${TARGET_HOME:-${HOME:-/root}}"

# ---------- Self-install ----------
if [[ "$DO_INSTALL" -eq 1 ]]; then
  CURRENT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
  DEST="/usr/local/bin/$SCRIPT_NAME"

  if [[ "$CURRENT_DIR" == "/usr/local/bin" ]]; then
    log "Script is already in /usr/local/bin"
    exit 0
  fi

  run_cmd "Installing script to /usr/local/bin" "${SUDO[@]}" install -m 755 "$0" "$DEST"
  log "Installed. Run it anywhere with: $SCRIPT_NAME"
  exit 0
fi

# ---------- Distro detection ----------
DISTRO_ID="unknown"
DISTRO_LIKE=""
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_LIKE="${ID_LIKE:-}"
fi

# ---------- Profile values ----------
JOURNAL_KEEP="14days"
LOG_TRUNCATE_THRESHOLD="+100M"

case "$PROFILE" in
  safe)
    JOURNAL_KEEP="30days"
    LOG_TRUNCATE_THRESHOLD="+500M"
    ;;
  normal)
    JOURNAL_KEEP="14days"
    LOG_TRUNCATE_THRESHOLD="+100M"
    ;;
  aggressive)
    JOURNAL_KEEP="7days"
    LOG_TRUNCATE_THRESHOLD="+50M"
    ;;
esac

# ---------- Start ----------
log "Starting Linux cleanup..."
log "Version: $VERSION"
log "Distro: $DISTRO_ID (like: $DISTRO_LIKE)"
log "Profile: $PROFILE"
log "Target user/home: $TARGET_USER / $TARGET_HOME"
log "Log file: $LOG_FILE"

initial_used_bytes="$(df -B1 --output=used / | tail -n 1 | tr -d ' ')"
log "Initial disk usage:"
df -h / | tee -a "$LOG_FILE"

# ==========================================================
# 1) Package cleanup (distro-specific)
# ==========================================================
cleanup_packages() {
  if require_cmd apt-get; then
    log "Detected APT (Ubuntu/Debian)."
    run_cmd "APT: autoremove" "${SUDO[@]}" apt-get autoremove -y || true
    run_cmd "APT: autoclean" "${SUDO[@]}" apt-get autoclean -y || true

    if [[ "$PROFILE" == "aggressive" ]]; then
      if confirm "APT: Run full cache clean (apt-get clean)?"; then
        run_cmd "APT: clean" "${SUDO[@]}" apt-get clean || true
      fi
    fi

  elif require_cmd pacman; then
    log "Detected pacman (Arch Linux)."

    if require_cmd paccache; then
      local keep=2
      [[ "$PROFILE" == "safe" ]] && keep=3
      [[ "$PROFILE" == "aggressive" ]] && keep=1
      run_cmd "Pacman: paccache keep last $keep versions" "${SUDO[@]}" paccache "-rk${keep}" || true
    else
      log "paccache not found (pacman-contrib missing)."
      if confirm "Run pacman -Sc instead?"; then
        run_cmd "Pacman: cache clean" "${SUDO[@]}" pacman -Sc --noconfirm || true
      fi
    fi

    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
    if [[ ${#orphans[@]} -gt 0 ]]; then
      log "Found orphan packages: ${orphans[*]}"
      if confirm "Remove orphan packages?"; then
        run_cmd "Pacman: remove orphans" "${SUDO[@]}" pacman -Rns --noconfirm "${orphans[@]}" || true
      fi
    else
      log "No orphan packages found."
    fi

  elif require_cmd dnf; then
    log "Detected DNF (Fedora/RHEL)."
    run_cmd "DNF: autoremove" "${SUDO[@]}" dnf autoremove -y || true
    run_cmd "DNF: clean all" "${SUDO[@]}" dnf clean all || true

  elif require_cmd yum; then
    log "Detected YUM (older RHEL/CentOS)."
    run_cmd "YUM: autoremove" "${SUDO[@]}" yum autoremove -y || true
    run_cmd "YUM: clean all" "${SUDO[@]}" yum clean all || true

  elif require_cmd zypper; then
    log "Detected zypper (openSUSE)."
    run_cmd "Zypper: clean all caches" "${SUDO[@]}" zypper clean --all || true
    log "TIP: Review unneeded packages manually: zypper packages --unneeded"

  elif require_cmd apk; then
    log "Detected apk (Alpine)."
    run_cmd "APK: cache clean" "${SUDO[@]}" apk cache clean || true

  else
    log "WARN: No supported package manager found."
  fi
}

# ==========================================================
# 2) Journald cleanup
# ==========================================================
cleanup_journal() {
  if require_cmd journalctl; then
    run_cmd "Systemd journal vacuum ($JOURNAL_KEEP)" "${SUDO[@]}" journalctl --vacuum-time="$JOURNAL_KEEP" || true
  else
    log "journalctl not found; skipping journald cleanup."
  fi
}

# ==========================================================
# 3) Temp cleanup (safe)
# ==========================================================
cleanup_temp() {
  if require_cmd systemd-tmpfiles; then
    run_cmd "Cleaning temp files via systemd-tmpfiles" "${SUDO[@]}" systemd-tmpfiles --clean || true
  else
    log "systemd-tmpfiles not found; using fallback (older files only)."
    run_cmd "Cleanup /tmp older than 3 days" "${SUDO[@]}" find /tmp -xdev -mindepth 1 -mtime +3 -delete || true
    run_cmd "Cleanup /var/tmp older than 7 days" "${SUDO[@]}" find /var/tmp -xdev -mindepth 1 -mtime +7 -delete || true
  fi
}

# ==========================================================
# 4) Large log files cleanup
# ==========================================================
cleanup_large_logs() {
  if [[ -d /var/log ]]; then
    run_cmd "Truncating huge logs in /var/log ($LOG_TRUNCATE_THRESHOLD)" \
      "${SUDO[@]}" find /var/log -type f -size "$LOG_TRUNCATE_THRESHOLD" -exec truncate -s 0 {} \; || true
  fi
}

# ==========================================================
# 5) User cache cleanup
# ==========================================================
cleanup_user_cache() {
  if [[ "$CLEAN_USER_CACHE" -ne 1 ]]; then
    log "Skipping user cache cleanup (--no-user-cache)."
    return 0
  fi

  if [[ ! -d "$TARGET_HOME/.cache" ]]; then
    log "No user cache directory found: $TARGET_HOME/.cache"
    return 0
  fi

  if confirm "Clear user cache in $TARGET_HOME/.cache ?"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[DRY-RUN] find '$TARGET_HOME/.cache' -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
    else
      find "$TARGET_HOME/.cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>&1 | tee -a "$LOG_FILE" || true
    fi
  else
    log "Skipped user cache cleanup."
  fi
}

# ==========================================================
# 6) Flatpak cleanup
# ==========================================================
cleanup_flatpak() {
  if ! require_cmd flatpak; then
    return 0
  fi

  if ! confirm "Remove unused Flatpak runtimes/apps?"; then
    log "Skipped Flatpak cleanup."
    return 0
  fi

  run_cmd "Flatpak system cleanup" "${SUDO[@]}" flatpak uninstall --unused -y || true

  if [[ "$TARGET_USER" != "root" ]] && require_cmd sudo; then
    run_cmd "Flatpak user cleanup ($TARGET_USER)" sudo -u "$TARGET_USER" flatpak uninstall --unused -y || true
  fi
}

# ==========================================================
# 7) Snap cleanup (disabled revisions)
# ==========================================================
cleanup_snap() {
  if ! require_cmd snap; then
    return 0
  fi

  if ! confirm "Clean old disabled Snap revisions?"; then
    log "Skipped Snap cleanup."
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[DRY-RUN] snap list --all | awk '/disabled/{print \$1, \$3}'"
    return 0
  fi

  mapfile -t disabled_snaps < <(snap list --all 2>/dev/null | awk '/disabled/{print $1 " " $3}')
  if [[ ${#disabled_snaps[@]} -eq 0 ]]; then
    log "No disabled Snap revisions found."
    return 0
  fi

  for item in "${disabled_snaps[@]}"; do
    name="${item% *}"
    rev="${item##* }"
    run_cmd "Removing Snap disabled revision: $name ($rev)" "${SUDO[@]}" snap remove "$name" --revision="$rev" || true
  done
}

# ==========================================================
# 8) Docker cleanup (optional)
# ==========================================================
cleanup_docker() {
  if [[ "$ENABLE_DOCKER" -ne 1 ]]; then
    log "Docker cleanup disabled (use --docker to enable)."
    return 0
  fi

  if ! require_cmd docker; then
    log "Docker not installed; skipping."
    return 0
  fi

  if [[ "$PROFILE" == "aggressive" ]]; then
    if confirm "Docker aggressive cleanup (images + volumes) ?"; then
      run_cmd "Docker system prune -a --volumes" "${SUDO[@]}" docker system prune -a --volumes -f || true
    else
      run_cmd "Docker system prune (default)" "${SUDO[@]}" docker system prune -f || true
    fi
  else
    run_cmd "Docker system prune (default)" "${SUDO[@]}" docker system prune -f || true
  fi
}

# ---------- Execute ----------
cleanup_packages
cleanup_journal
cleanup_temp
cleanup_large_logs
cleanup_user_cache
cleanup_flatpak
cleanup_snap
cleanup_docker

# ---------- Final stats ----------
final_used_bytes="$(df -B1 --output=used / | tail -n 1 | tr -d ' ')"
log "Final disk usage:"
df -h / | tee -a "$LOG_FILE"

freed_bytes=$(( initial_used_bytes - final_used_bytes ))
if [[ "$freed_bytes" -ge 0 ]]; then
  if require_cmd numfmt; then
    freed_human="$(numfmt --to=iec-i --suffix=B "$freed_bytes")"
  else
    freed_human="${freed_bytes} bytes"
  fi
  log "Total space cleared: $freed_human"
else
  increased=$(( -freed_bytes ))
  if require_cmd numfmt; then
    increased_human="$(numfmt --to=iec-i --suffix=B "$increased")"
  else
    increased_human="${increased} bytes"
  fi
  log "Note: Disk usage increased by $increased_human (can happen due to metadata/log updates)."
fi

log "Cleanup finished successfully."
