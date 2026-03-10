#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Linux Admin & Cleaner v3.0
# Cross-Distro: Ubuntu/Debian, Arch, Fedora/RHEL, openSUSE, Alpine
# Modules: Cleanup | Network Audit | Security Audit | Health Check | App Cache
# Interactive TUI Menu (pure Bash, no dialog/whiptail needed)
# Author: Soroush @ Hawax
# ==========================================

VERSION="3.0.0"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/${SCRIPT_NAME%.sh}_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE=""
REPORT_MODE=0

DRY_RUN=0
AUTO_YES=0
DO_INSTALL=0
PROFILE="normal"
ENABLE_DOCKER=0
CLEAN_USER_CACHE=1

# ---------- Module flags ----------
MOD_CLEAN=1
MOD_NETWORK=0
MOD_SECURITY=0
MOD_HEALTH=0
MOD_APPCACHE=0

# ---------- ANSI Colors ----------
if [[ -t 1 ]]; then
  C_RESET="\e[0m"
  C_BOLD="\e[1m"
  C_RED="\e[31m"
  C_GREEN="\e[32m"
  C_YELLOW="\e[33m"
  C_BLUE="\e[34m"
  C_CYAN="\e[36m"
  C_MAGENTA="\e[35m"
  C_GRAY="\e[90m"
else
  C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW=""
  C_BLUE="" C_CYAN="" C_MAGENTA="" C_GRAY=""
fi

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
  local msg="[$(date '+%F %T')] $*"
  echo -e "$msg" | tee -a "$LOG_FILE"
}

log_section() {
  local title="$1"
  local line="════════════════════════════════════════════════════════"
  echo -e "\n${C_BOLD}${C_BLUE}${line}${C_RESET}" | tee -a "$LOG_FILE"
  echo -e "${C_BOLD}${C_CYAN}  ▶  ${title}${C_RESET}" | tee -a "$LOG_FILE"
  echo -e "${C_BOLD}${C_BLUE}${line}${C_RESET}\n" | tee -a "$LOG_FILE"
}

log_ok()   { echo -e "${C_GREEN}  ✔  $*${C_RESET}" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${C_YELLOW}  ⚠  $*${C_RESET}" | tee -a "$LOG_FILE"; }
log_err()  { echo -e "${C_RED}  ✖  $*${C_RESET}" | tee -a "$LOG_FILE"; }
log_info() { echo -e "${C_CYAN}  ℹ  $*${C_RESET}" | tee -a "$LOG_FILE"; }
log_find() { echo -e "${C_MAGENTA}  ►  $*${C_RESET}" | tee -a "$LOG_FILE"; }

spinner_start() {
  local msg="$1"
  echo -ne "${C_GRAY}  ⟳  ${msg}...${C_RESET}"
}
spinner_stop() {
  echo -e "\r${C_GREEN}  ✔  Done.${C_RESET}                    "
}

require_cmd() { command -v "$1" >/dev/null 2>&1; }

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
  local cmd_str; cmd_str="$(cmd_to_string "$@")"
  log_info "$desc"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo -e "${C_GRAY}    [DRY-RUN] $cmd_str${C_RESET}" | tee -a "$LOG_FILE"
    return 0
  fi
  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then
    log_warn "Command failed (exit $rc): $cmd_str"
    return $rc
  fi
  return 0
}

confirm() {
  local msg="$1"
  [[ "$AUTO_YES" -eq 1 ]] && return 0
  echo -ne "${C_YELLOW}  ?  ${msg} (y/n): ${C_RESET}"
  read -r response
  [[ "$response" =~ ^[Yy]$ ]]
}

report_add() {
  [[ "$REPORT_MODE" -eq 1 ]] && echo "$*" >> "$REPORT_FILE"
}

show_help() {
  cat <<EOF

${C_BOLD}${C_CYAN}Linux Admin & Cleaner v${VERSION}${C_RESET}

${C_BOLD}Usage:${C_RESET} $SCRIPT_NAME [OPTIONS] [MODULES]

${C_BOLD}Modules (default: --clean only):${C_RESET}
  --clean               Run disk/package cleanup (default)
  --network             Run network analysis & port audit
  --security            Run security audit (SUID, SSH, permissions)
  --health              Run system health check
  --app-cache           Clean app caches (npm, pip, cargo, go, maven)
  --all                 Enable all modules

${C_BOLD}Cleanup Options:${C_RESET}
  --profile PROFILE     safe | normal | aggressive (default: normal)
  --docker              Enable Docker cleanup
  --no-user-cache       Skip cleaning user cache (~/.cache)

${C_BOLD}General Options:${C_RESET}
  --install             Install script to /usr/local/bin
  --dry-run             Show commands only (do not execute)
  --yes                 Non-interactive (auto-confirm all prompts)
  --report [FILE]       Generate Markdown report (default: /tmp/report.md)
  --version             Show version
  -h, --help            Show this help

${C_BOLD}Examples:${C_RESET}
  $SCRIPT_NAME --dry-run --all
  $SCRIPT_NAME --yes --clean --profile aggressive --docker
  $SCRIPT_NAME --yes --security --network --report
  $SCRIPT_NAME --yes --all --report /root/audit-$(date +%F).md
  $SCRIPT_NAME --install

EOF
}

# ==========================================================
# INTERACTIVE MENU SYSTEM
# Number-based selection, live output per step, summary + loop
# ==========================================================

tui_clear_screen() { printf '\033[2J\033[H'; }
cleanup_on_exit() {
  tput rmcup 2>/dev/null || true   # exit alt screen if active
  tput cnorm 2>/dev/null || true   # restore cursor
  tput sgr0  2>/dev/null || true   # reset colors
  stty sane  2>/dev/null || true   # restore terminal settings
  echo ""                           # clean newline
}
trap cleanup_on_exit EXIT INT TERM

# ── Menu color palette ────────────────────────────────────
M_NUM="\e[1;38;5;220m"     # number — yellow
M_LABEL="\e[1;38;5;255m"   # label  — white
M_DESC="\e[38;5;244m"       # desc   — gray
M_SEP="\e[38;5;240m"        # separator line
M_RUN="\e[1;38;5;46m"       # run/ok — green
M_WARN="\e[1;38;5;196m"     # warning/quit — red
M_DIM="\e[38;5;235m"        # dim
M_STEP="\e[1;38;5;39m"      # step header — blue
M_OK="\e[1;38;5;46m"        # ok result
M_ERR="\e[1;38;5;196m"      # error result
M_INFO="\e[38;5;250m"       # info text

menu_logo() {
  echo -e "\e[1;38;5;34m"
  echo '    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗'
  echo '    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝'
  echo '    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ '
  echo '    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ '
  echo '    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗'
  echo '    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝'
  echo -e "${M_DIM}    ── Linux Admin & Cleaner  v${VERSION}  ·  by Hawax ──${C_RESET}"
  echo ""
}

menu_line() { echo -e "${M_SEP}    $(printf '─%.0s' $(seq 1 55))${C_RESET}"; }

menu_show() {
  tui_clear_screen
  menu_logo
  echo -e "${M_LABEL}    WHAT DO YOU WANT TO DO?${C_RESET}"
  echo -e "${M_DESC}    Enter numbers separated by spaces  (e.g.  1 3 4  or  * r)${C_RESET}"
  echo ""
  menu_line
  echo -e "${M_DESC}    System Tools${C_RESET}"
  menu_line
  echo ""
  printf "  ${M_NUM}  1  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Disk Cleanup"     "Package cache · journal · temp · logs · snap · flatpak"
  printf "  ${M_NUM}  2  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Network Audit"    "Interfaces · open ports · firewall · sensitive services"
  printf "  ${M_NUM}  3  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Security Audit"   "SUID · SSH config · sudo entries · password check"
  printf "  ${M_NUM}  4  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Health Check"     "CPU · RAM · disk usage · failed services · OOM kills"
  printf "  ${M_NUM}  5  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "App Cache"        "npm · pip · cargo · Go · Maven · Gradle"
  echo ""
  menu_line
  echo -e "${M_WARN}    Network Security${C_RESET}"
  menu_line
  echo ""
  printf "  ${M_NUM}  6  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Port Scanner"     "Scan open ports on any target IP (nmap / bash fallback)"
  printf "  ${M_NUM}  7  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "ARP Scan"         "Discover all devices on local network"
  printf "  ${M_NUM}  8  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Brute-Force Monitor" "Failed logins · attacking IPs · fail2ban · root SSH"
  printf "  ${M_NUM}  9  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Bandwidth Monitor" "Live speed · total traffic · top connections · nethogs"
  echo ""
  menu_line
  echo -e "${M_DESC}    Options — add to your selection:${C_RESET}"
  menu_line
  echo ""
  printf "  ${M_NUM}  d  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Docker cleanup"   "Add to '1' or alone (auto-enables Disk Cleanup)"
  printf "  ${M_NUM}  r  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Generate Report"  "Works with any module — saves results to /tmp/"
  printf "  ${M_NUM}  n  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Dry Run"          "Works with any module — preview only, no changes"
  echo ""
  menu_line
  echo ""
  printf "  ${M_RUN}  *  ${C_RESET}  ${M_LABEL}%-22s${C_RESET}  ${M_DESC}%s${C_RESET}\n" \
    "Run ALL modules"  "Executes 1–9 at once"
  printf "  ${M_WARN}  q  ${C_RESET}  ${M_LABEL}%s${C_RESET}\n" "Quit"
  echo ""
  menu_line
  echo ""
  echo -e "${M_DESC}    Profile: ${C_RESET}${M_INFO}${PROFILE}${C_RESET}${M_DESC}  ·  change: p=safe  p=normal  p=aggressive${C_RESET}"
  echo ""
  echo -ne "${M_RUN}  ❯ ${C_RESET}"
}

menu_step_header() {
  local num="$1" name="$2" icon="$3"
  echo ""
  echo -e "${M_STEP}  ╔══════════════════════════════════════════════════════╗${C_RESET}"
  printf  "${M_STEP}  ║${C_RESET}  ${M_NUM}[%s]${C_RESET}  ${M_LABEL}%-46s${C_RESET}${M_STEP}║${C_RESET}\n" "$num" "$icon  $name"
  echo -e "${M_STEP}  ╚══════════════════════════════════════════════════════╝${C_RESET}"
  echo ""
}

menu_step_result() {
  local rc="$1" name="$2"
  if [[ "$rc" -eq 0 ]]; then
    echo -e "\n  ${M_OK}✔  $name — done${C_RESET}"
  else
    echo -e "\n  ${M_ERR}✖  $name — finished with warnings (exit $rc)${C_RESET}"
  fi
  echo ""
}

menu_summary() {
  local freed="$1"; shift
  local ran=("$@")
  echo ""
  echo -e "${M_STEP}  ╔══════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${M_STEP}  ║${C_RESET}  ${M_LABEL}SUMMARY$(printf '%*s' 47 '')${M_STEP}║${C_RESET}"
  echo -e "${M_STEP}  ╠══════════════════════════════════════════════════════╣${C_RESET}"
  for item in "${ran[@]}"; do
    printf "${M_STEP}  ║${C_RESET}  ${M_OK}✔${C_RESET}  ${M_INFO}%-49s${C_RESET}${M_STEP}║${C_RESET}\n" "$item"
  done
  echo -e "${M_STEP}  ╠══════════════════════════════════════════════════════╣${C_RESET}"
  printf  "${M_STEP}  ║${C_RESET}  ${M_LABEL}%-20s${C_RESET}${M_RUN}%-31s${C_RESET}${M_STEP}║${C_RESET}\n" \
    "Space freed:" "$freed"
  printf  "${M_STEP}  ║${C_RESET}  ${M_LABEL}%-20s${C_RESET}${M_INFO}%-31s${C_RESET}${M_STEP}║${C_RESET}\n" \
    "Log file:" "$LOG_FILE"
  if [[ "$REPORT_MODE" -eq 1 ]]; then
    printf "${M_STEP}  ║${C_RESET}  ${M_LABEL}%-20s${C_RESET}${M_INFO}%-31s${C_RESET}${M_STEP}║${C_RESET}\n" \
      "Report:" "$REPORT_FILE"
  fi
  echo -e "${M_STEP}  ╚══════════════════════════════════════════════════════╝${C_RESET}"
  echo ""
}

tui_main_menu() {
  AUTO_YES=1
  tput smcup 2>/dev/null || true   # enter alternate screen
  while true; do
    menu_show
    local input=""
    read -r input
    echo ""
    [[ "$input" =~ ^[qQ]$ ]] && tput rmcup 2>/dev/null || true; [[ "$input" =~ ^[qQ]$ ]] && echo -e "${M_WARN}  Bye.${C_RESET}\n" && exit 0
    [[ -z "$input" ]] && continue

    MOD_CLEAN=0; MOD_NETWORK=0; MOD_SECURITY=0; MOD_HEALTH=0; MOD_APPCACHE=0
    MOD_PORTSCAN=0; MOD_ARPSCAN=0; MOD_BRUTEFORCE=0; MOD_BANDWIDTH=0
    ENABLE_DOCKER=0; REPORT_MODE=0; DRY_RUN=0

    local token
    for token in $input; do
      case "$token" in
        1)    MOD_CLEAN=1 ;;
        2)    MOD_NETWORK=1 ;;
        3)    MOD_SECURITY=1 ;;
        4)    MOD_HEALTH=1 ;;
        5)    MOD_APPCACHE=1 ;;
        6)    MOD_PORTSCAN=1 ;;
        7)    MOD_ARPSCAN=1 ;;
        8)    MOD_BRUTEFORCE=1 ;;
        9)    MOD_BANDWIDTH=1 ;;
        \*)   MOD_CLEAN=1; MOD_NETWORK=1; MOD_SECURITY=1; MOD_HEALTH=1; MOD_APPCACHE=1
              MOD_PORTSCAN=1; MOD_ARPSCAN=1; MOD_BRUTEFORCE=1; MOD_BANDWIDTH=1 ;;
        d|D)  ENABLE_DOCKER=1 ;;
        r|R)  REPORT_MODE=1
              [[ -z "$REPORT_FILE" ]] && \
                REPORT_FILE="/tmp/linux-admin-report-$(date +%Y%m%d_%H%M%S).md" ;;
        n|N)  DRY_RUN=1 ;;
        p=safe|p=normal|p=aggressive) PROFILE="${token#p=}" ;;
        q|Q)  echo -e "${M_WARN}  Bye.${C_RESET}\n"; exit 0 ;;
        *)    echo -e "${M_WARN}  Unknown option: '${token}' — ignored.${C_RESET}" ;;
      esac
    done

    if [[ "$MOD_CLEAN" -eq 0 && "$MOD_NETWORK" -eq 0 && "$MOD_SECURITY" -eq 0 \
       && "$MOD_HEALTH" -eq 0 && "$MOD_APPCACHE" -eq 0 \
       && "$MOD_PORTSCAN" -eq 0 && "$MOD_ARPSCAN" -eq 0 \
       && "$MOD_BRUTEFORCE" -eq 0 && "$MOD_BANDWIDTH" -eq 0 ]]; then
      # d alleine → implizit Disk Cleanup aktivieren
      if [[ "$ENABLE_DOCKER" -eq 1 ]]; then
        echo -e "${M_INFO}  Hint: 'd' runs together with Disk Cleanup — activating module 1 automatically.${C_RESET}\n"
        MOD_CLEAN=1
      else
        echo -e "${M_WARN}  No module selected. Enter at least one number (1–5) or * for all.${C_RESET}\n"
        sleep 1; continue
      fi
    fi

    # Re-init distro + profile
    DISTRO_ID="unknown"; DISTRO_LIKE=""; DISTRO_PRETTY="Unknown"
    if [[ -r /etc/os-release ]]; then
      source /etc/os-release
      DISTRO_ID="${ID:-unknown}"; DISTRO_LIKE="${ID_LIKE:-}"
      DISTRO_PRETTY="${PRETTY_NAME:-$DISTRO_ID}"
    fi
    case "$PROFILE" in
      safe)       JOURNAL_KEEP="30days"; LOG_TRUNCATE_THRESHOLD="+500M" ;;
      normal)     JOURNAL_KEEP="14days"; LOG_TRUNCATE_THRESHOLD="+100M" ;;
      aggressive) JOURNAL_KEEP="7days";  LOG_TRUNCATE_THRESHOLD="+50M" ;;
    esac
    [[ "$DRY_RUN" -eq 1 ]] && echo -e "${M_WARN}  DRY-RUN mode — no changes will be made.${C_RESET}\n"

    if [[ "$REPORT_MODE" -eq 1 ]]; then
      { echo "# Linux Admin & Cleaner Report"
        echo "**Date:** $(date '+%F %T')"
        echo "**Host:** $(hostname)"
        echo "**Distro:** $DISTRO_PRETTY"
        echo "**Profile:** $PROFILE"
      } > "$REPORT_FILE"
    fi

    local initial_bytes
    initial_bytes="$(df -B1 --output=used / | tail -n 1 | tr -d ' ')"
    local ran_modules=()
    local rc=0

    if [[ "$MOD_CLEAN" -eq 1 ]]; then
      menu_step_header 1 "Disk Cleanup" ">>>"
      rc=0
      cleanup_packages  || rc=$?
      cleanup_journal   || rc=$?
      cleanup_temp      || rc=$?
      cleanup_large_logs || rc=$?
      cleanup_user_cache || rc=$?
      cleanup_flatpak   || rc=$?
      cleanup_snap      || rc=$?
      cleanup_docker    || rc=$?
      menu_step_result $rc "Disk Cleanup"
      ran_modules+=("Disk Cleanup")
    fi
    if [[ "$MOD_NETWORK" -eq 1 ]]; then
      menu_step_header 2 "Network Audit" ">>>"
      rc=0; run_network_audit || rc=$?
      menu_step_result $rc "Network Audit"
      ran_modules+=("Network Audit")
    fi
    if [[ "$MOD_SECURITY" -eq 1 ]]; then
      menu_step_header 3 "Security Audit" ">>>"
      rc=0; run_security_audit || rc=$?
      menu_step_result $rc "Security Audit"
      ran_modules+=("Security Audit")
    fi
    if [[ "$MOD_HEALTH" -eq 1 ]]; then
      menu_step_header 4 "Health Check" ">>>"
      rc=0; run_health_check || rc=$?
      menu_step_result $rc "Health Check"
      ran_modules+=("Health Check")
    fi
    if [[ "$MOD_APPCACHE" -eq 1 ]]; then
      menu_step_header 5 "App Cache Cleanup" ">>>"
      rc=0; run_appcache_clean || rc=$?
      menu_step_result $rc "App Cache Cleanup"
      ran_modules+=("App Cache Cleanup")
    fi
    if [[ "$MOD_PORTSCAN" -eq 1 ]]; then
      menu_step_header 6 "Port Scanner" ">>>"
      rc=0; run_port_scanner || rc=$?
      menu_step_result $rc "Port Scanner"
      ran_modules+=("Port Scanner")
    fi
    if [[ "$MOD_ARPSCAN" -eq 1 ]]; then
      menu_step_header 7 "ARP Scan" ">>>"
      rc=0; run_arp_scan || rc=$?
      menu_step_result $rc "ARP Scan"
      ran_modules+=("ARP Scan")
    fi
    if [[ "$MOD_BRUTEFORCE" -eq 1 ]]; then
      menu_step_header 8 "Brute-Force Monitor" ">>>"
      rc=0; run_bruteforce_monitor || rc=$?
      menu_step_result $rc "Brute-Force Monitor"
      ran_modules+=("Brute-Force Monitor")
    fi
    if [[ "$MOD_BANDWIDTH" -eq 1 ]]; then
      menu_step_header 9 "Bandwidth Monitor" ">>>"
      rc=0; run_bandwidth_monitor || rc=$?
      menu_step_result $rc "Bandwidth Monitor"
      ran_modules+=("Bandwidth Monitor")
    fi

    local final_bytes
    final_bytes="$(df -B1 --output=used / | tail -n 1 | tr -d ' ')"
    local freed_bytes=$(( initial_bytes - final_bytes ))
    local freed_human="${freed_bytes} bytes"
    if require_cmd numfmt; then
      freed_human="$(numfmt --to=iec-i --suffix=B "$freed_bytes" 2>/dev/null || echo "${freed_bytes} bytes")"
    fi
    [[ "$freed_bytes" -lt 0 ]] && freed_human="~0 (metadata updates)"

    if [[ "$REPORT_MODE" -eq 1 ]]; then
      { echo ""; echo "---"
        echo "**Space freed:** $freed_human"
        echo "*Generated by linux-admin-cleaner v${VERSION} — $(date '+%F %T')*"
      } >> "$REPORT_FILE"
      echo -e "\n  ${M_OK}✔  Report saved: $REPORT_FILE${C_RESET}"
    fi

    menu_summary "$freed_human" "${ran_modules[@]}"
    echo -e "${M_DESC}  Log: ${M_INFO}${LOG_FILE}${C_RESET}\n"

    echo -ne "${M_DESC}  Run again? ${C_RESET}${M_NUM}[y/n]${C_RESET}${M_RUN} ❯ ${C_RESET}"
    local again=""
    read -r again
    echo ""
    [[ ! "$again" =~ ^[Yy]$ ]] && tput rmcup 2>/dev/null || true && echo -e "${M_OK}  Done. Bye!${C_RESET}\n" && exit 0
  done
}


# ---------- Parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)      DO_INSTALL=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --yes)          AUTO_YES=1 ;;
    --docker)       ENABLE_DOCKER=1 ;;
    --no-user-cache) CLEAN_USER_CACHE=0 ;;
    --clean)        MOD_CLEAN=1 ;;
    --network)      MOD_NETWORK=1 ;;
    --security)     MOD_SECURITY=1 ;;
    --health)       MOD_HEALTH=1 ;;
    --app-cache)    MOD_APPCACHE=1 ;;
    --all)
      MOD_CLEAN=1; MOD_NETWORK=1; MOD_SECURITY=1; MOD_HEALTH=1; MOD_APPCACHE=1
      ;;
    --report)
      REPORT_MODE=1
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        REPORT_FILE="$2"; shift
      else
        REPORT_FILE="/tmp/linux-admin-report-$(date +%Y%m%d_%H%M%S).md"
      fi
      ;;
    --version) echo "$VERSION"; exit 0 ;;
    --profile)
      shift
      PROFILE="${1:-}"
      if [[ ! "$PROFILE" =~ ^(safe|normal|aggressive)$ ]]; then
        echo "Invalid profile. Use: safe | normal | aggressive" >&2; exit 1
      fi
      ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
  esac
  shift
done

# ---------- Launch TUI if no args given ----------
# If the script is started without any arguments (and not --install),
# drop into the interactive menu instead of showing help.
_HAS_ARGS=0
for _a in "$@"; do
  case "$_a" in --install|--version|-h|--help) ;; *) _HAS_ARGS=1 ;; esac
done
if [[ "$_HAS_ARGS" -eq 0 && "$DO_INSTALL" -eq 0 ]]; then
  # Check we're in an interactive terminal
  if [[ -t 0 && -t 1 ]]; then
    tui_main_menu
  else
    show_help; exit 0
  fi
fi

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
    log_ok "Script is already in /usr/local/bin"; exit 0
  fi
  run_cmd "Installing to /usr/local/bin" "${SUDO[@]}" install -m 755 "$0" "$DEST"
  log_ok "Installed. Run from anywhere: sudo $SCRIPT_NAME"
  exit 0
fi

# ---------- Distro detection ----------
DISTRO_ID="unknown"
DISTRO_LIKE=""
DISTRO_PRETTY="Unknown"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_LIKE="${ID_LIKE:-}"
  DISTRO_PRETTY="${PRETTY_NAME:-$DISTRO_ID}"
fi

# ---------- Profile values ----------
JOURNAL_KEEP="14days"
LOG_TRUNCATE_THRESHOLD="+100M"
case "$PROFILE" in
  safe)       JOURNAL_KEEP="30days"; LOG_TRUNCATE_THRESHOLD="+500M" ;;
  normal)     JOURNAL_KEEP="14days"; LOG_TRUNCATE_THRESHOLD="+100M" ;;
  aggressive) JOURNAL_KEEP="7days";  LOG_TRUNCATE_THRESHOLD="+50M" ;;
esac

# ---------- Init report ----------
if [[ "$REPORT_MODE" -eq 1 ]]; then
  {
    echo "# Linux Admin & Cleaner Report"
    echo "**Date:** $(date '+%F %T')"
    echo "**Host:** $(hostname)"
    echo "**Distro:** $DISTRO_PRETTY"
    echo "**Kernel:** $(uname -r)"
    echo "**Profile:** $PROFILE"
    echo "**User:** $TARGET_USER"
    echo ""
  } > "$REPORT_FILE"
  log_ok "Report initialized: $REPORT_FILE"
fi

# ---------- Banner (shown when run via CLI flags, not menu) ----------
echo -e "\e[1;38;5;34m"
cat <<'BANNER'
  ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
  ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
  ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝
  ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗
  ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
  ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
BANNER
echo -e "${C_RESET}"

log "Version : $VERSION"
log "Distro  : $DISTRO_PRETTY"
log "Profile : $PROFILE"
log "User    : $TARGET_USER @ $TARGET_HOME"
log "Log     : $LOG_FILE"
[[ "$REPORT_MODE" -eq 1 ]] && log "Report  : $REPORT_FILE"
[[ "$DRY_RUN" -eq 1 ]]    && log_warn "DRY-RUN mode enabled — no changes will be made."

# ==========================================================
# MODULE 1: DISK / PACKAGE CLEANUP
# ==========================================================
cleanup_packages() {
  log_section "Package Manager Cleanup"
  if require_cmd apt-get; then
    log_info "Detected APT (Ubuntu/Debian)"
    run_cmd "APT: autoremove" "${SUDO[@]}" apt-get autoremove -y || true
    run_cmd "APT: autoclean" "${SUDO[@]}" apt-get autoclean -y || true
    if [[ "$PROFILE" == "aggressive" ]]; then
      if confirm "APT: Full cache clean (apt-get clean)?"; then
        run_cmd "APT: clean" "${SUDO[@]}" apt-get clean || true
      fi
    fi
  elif require_cmd pacman; then
    log_info "Detected pacman (Arch Linux)"
    if require_cmd paccache; then
      local keep=2
      [[ "$PROFILE" == "safe" ]]       && keep=3
      [[ "$PROFILE" == "aggressive" ]] && keep=1
      run_cmd "Pacman: paccache keep last $keep" "${SUDO[@]}" paccache "-rk${keep}" || true
    else
      log_warn "paccache not found (install pacman-contrib)"
      if confirm "Run pacman -Sc instead?"; then
        run_cmd "Pacman: cache clean" "${SUDO[@]}" pacman -Sc --noconfirm || true
      fi
    fi
    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
    if [[ ${#orphans[@]} -gt 0 ]]; then
      log_warn "Orphan packages: ${orphans[*]}"
      if confirm "Remove orphans?"; then
        run_cmd "Pacman: remove orphans" "${SUDO[@]}" pacman -Rns --noconfirm "${orphans[@]}" || true
      fi
    else
      log_ok "No orphan packages found."
    fi
  elif require_cmd dnf; then
    log_info "Detected DNF (Fedora/RHEL)"
    run_cmd "DNF: autoremove" "${SUDO[@]}" dnf autoremove -y || true
    run_cmd "DNF: clean all" "${SUDO[@]}" dnf clean all || true
  elif require_cmd yum; then
    log_info "Detected YUM (RHEL/CentOS)"
    run_cmd "YUM: autoremove" "${SUDO[@]}" yum autoremove -y || true
    run_cmd "YUM: clean all" "${SUDO[@]}" yum clean all || true
  elif require_cmd zypper; then
    log_info "Detected zypper (openSUSE)"
    run_cmd "Zypper: clean caches" "${SUDO[@]}" zypper clean --all || true
  elif require_cmd apk; then
    log_info "Detected apk (Alpine)"
    run_cmd "APK: cache clean" "${SUDO[@]}" apk cache clean || true
  else
    log_warn "No supported package manager found."
  fi
}

cleanup_journal() {
  log_section "Systemd Journal Cleanup"
  if require_cmd journalctl; then
    run_cmd "Journal vacuum ($JOURNAL_KEEP)" "${SUDO[@]}" journalctl --vacuum-time="$JOURNAL_KEEP" || true
    log_ok "Journal cleaned."
  else
    log_warn "journalctl not found; skipping."
  fi
}

cleanup_temp() {
  log_section "Temp File Cleanup"
  if require_cmd systemd-tmpfiles; then
    run_cmd "systemd-tmpfiles --clean" "${SUDO[@]}" systemd-tmpfiles --clean || true
  else
    run_cmd "Cleanup /tmp (>3d)" "${SUDO[@]}" find /tmp -xdev -mindepth 1 -mtime +3 -delete || true
    run_cmd "Cleanup /var/tmp (>7d)" "${SUDO[@]}" find /var/tmp -xdev -mindepth 1 -mtime +7 -delete || true
  fi
  log_ok "Temp files cleaned."
}

cleanup_large_logs() {
  log_section "Large Log File Cleanup"
  if [[ -d /var/log ]]; then
    local found
    found=$(find /var/log -type f -size "$LOG_TRUNCATE_THRESHOLD" 2>/dev/null | wc -l)
    if [[ "$found" -gt 0 ]]; then
      log_warn "Found $found log file(s) larger than threshold $LOG_TRUNCATE_THRESHOLD"
      run_cmd "Truncating large logs" \
        "${SUDO[@]}" find /var/log -type f -size "$LOG_TRUNCATE_THRESHOLD" -exec truncate -s 0 {} \; || true
      log_ok "Large logs truncated."
    else
      log_ok "No oversized logs found (threshold: $LOG_TRUNCATE_THRESHOLD)."
    fi
  fi
}

cleanup_user_cache() {
  log_section "User Cache Cleanup (~/.cache)"
  if [[ "$CLEAN_USER_CACHE" -ne 1 ]]; then
    log_info "Skipped (--no-user-cache)."
    return 0
  fi
  if [[ ! -d "$TARGET_HOME/.cache" ]]; then
    log_info "No cache directory found at $TARGET_HOME/.cache"
    return 0
  fi
  local cache_size
  cache_size=$(du -sh "$TARGET_HOME/.cache" 2>/dev/null | cut -f1 || echo "?")
  log_info "Cache size: $cache_size at $TARGET_HOME/.cache"
  if confirm "Clear user cache ($cache_size)?"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[DRY-RUN] Would remove: $TARGET_HOME/.cache/*"
    else
      find "$TARGET_HOME/.cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>&1 | tee -a "$LOG_FILE" || true
      log_ok "User cache cleared."
    fi
  fi
}

cleanup_flatpak() {
  require_cmd flatpak || return 0
  log_section "Flatpak Cleanup"
  if confirm "Remove unused Flatpak runtimes?"; then
    run_cmd "Flatpak system cleanup" "${SUDO[@]}" flatpak uninstall --unused -y || true
    if [[ "$TARGET_USER" != "root" ]] && require_cmd sudo; then
      run_cmd "Flatpak user cleanup" sudo -u "$TARGET_USER" flatpak uninstall --unused -y || true
    fi
    log_ok "Flatpak cleanup done."
  fi
}

cleanup_snap() {
  require_cmd snap || return 0
  log_section "Snap Cleanup"
  if ! confirm "Remove disabled Snap revisions?"; then return 0; fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] Would check snap disabled revisions."
    return 0
  fi
  mapfile -t disabled_snaps < <(snap list --all 2>/dev/null | awk '/disabled/{print $1 " " $3}')
  if [[ ${#disabled_snaps[@]} -eq 0 ]]; then
    log_ok "No disabled Snap revisions found."
    return 0
  fi
  for item in "${disabled_snaps[@]}"; do
    local name="${item% *}" rev="${item##* }"
    run_cmd "Remove Snap: $name rev $rev" "${SUDO[@]}" snap remove "$name" --revision="$rev" || true
  done
}

cleanup_docker() {
  if [[ "$ENABLE_DOCKER" -ne 1 ]]; then
    return 0
  fi
  log_section "Docker Cleanup"
  if ! require_cmd docker; then
    log_warn "Docker not installed; skipping."; return 0
  fi
  if [[ "$PROFILE" == "aggressive" ]]; then
    if confirm "Docker AGGRESSIVE cleanup (images + volumes)?"; then
      run_cmd "Docker prune -a --volumes" "${SUDO[@]}" docker system prune -a --volumes -f || true
    else
      run_cmd "Docker prune (default)" "${SUDO[@]}" docker system prune -f || true
    fi
  else
    run_cmd "Docker prune (default)" "${SUDO[@]}" docker system prune -f || true
  fi
  log_ok "Docker cleanup done."
}

# ==========================================================
# MODULE 2: NETWORK ANALYSIS
# ==========================================================
run_network_audit() {
  log_section "Network Analysis & Port Audit"
  report_add "## Network Analysis"
  report_add ""

  # Interfaces
  log_info "Network interfaces:"
  if require_cmd ip; then
    ip -brief address 2>/dev/null | tee -a "$LOG_FILE" | while read -r line; do report_add "    $line"; done
  elif require_cmd ifconfig; then
    ifconfig 2>/dev/null | head -40 | tee -a "$LOG_FILE"
  fi

  # Default route
  log_info "Default gateway:"
  if require_cmd ip; then
    ip route show default 2>/dev/null | tee -a "$LOG_FILE"
  fi

  # DNS
  log_info "DNS servers:"
  if [[ -f /etc/resolv.conf ]]; then
    grep "^nameserver" /etc/resolv.conf | tee -a "$LOG_FILE"
  fi

  # Open listening ports
  log_info "Listening ports:"
  if require_cmd ss; then
    echo -e "${C_BOLD}Proto  Local Address          Process${C_RESET}" | tee -a "$LOG_FILE"
    "${SUDO[@]}" ss -tlnp 2>/dev/null | tail -n +2 | tee -a "$LOG_FILE"
    report_add "### Listening Ports"
    report_add '```'
    "${SUDO[@]}" ss -tlnp 2>/dev/null >> "$REPORT_FILE" 2>/dev/null || true
    report_add '```'
  elif require_cmd netstat; then
    "${SUDO[@]}" netstat -tlnp 2>/dev/null | tee -a "$LOG_FILE"
  else
    log_warn "Neither ss nor netstat found."
  fi

  # Active connections count
  if require_cmd ss; then
    local estab
    estab=$("${SUDO[@]}" ss -tn state established 2>/dev/null | tail -n +2 | wc -l)
    log_info "Established TCP connections: ${C_BOLD}$estab${C_RESET}"
    report_add "**Established TCP connections:** $estab"
  fi

  # Firewall status
  log_info "Firewall status:"
  if require_cmd ufw; then
    "${SUDO[@]}" ufw status verbose 2>/dev/null | tee -a "$LOG_FILE" || true
    report_add "### UFW Status"
    report_add '```'
    "${SUDO[@]}" ufw status verbose 2>/dev/null >> "$REPORT_FILE" 2>/dev/null || true
    report_add '```'
  elif require_cmd firewall-cmd; then
    "${SUDO[@]}" firewall-cmd --state 2>/dev/null | tee -a "$LOG_FILE" || true
    "${SUDO[@]}" firewall-cmd --list-all 2>/dev/null | tee -a "$LOG_FILE" || true
  elif require_cmd iptables; then
    local rules
    rules=$("${SUDO[@]}" iptables -L -n --line-numbers 2>/dev/null | wc -l)
    log_info "iptables rules: $rules lines"
    report_add "**iptables rules:** $rules lines"
  else
    log_warn "No supported firewall tool found (ufw/firewalld/iptables)."
  fi

  # Check for open common dangerous ports
  log_info "Checking commonly sensitive ports..."
  local sensitive_ports=(21 23 25 110 111 135 137 139 445 512 513 514 1433 3306 5432 6379 27017)
  local found_sensitive=0
  for port in "${sensitive_ports[@]}"; do
    if "${SUDO[@]}" ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      log_warn "Sensitive port OPEN: ${C_BOLD}$port${C_RESET} ($(get_port_name "$port"))"
      report_add "- ⚠️  Port **$port** ($(get_port_name "$port")) is open"
      found_sensitive=1
    fi
  done
  if [[ "$found_sensitive" -eq 0 ]]; then
    log_ok "No commonly sensitive ports detected as open."
    report_add "- ✅ No commonly sensitive ports open"
  fi

  log_ok "Network audit complete."
  report_add ""
}

get_port_name() {
  case "$1" in
    21)    echo "FTP" ;;
    23)    echo "Telnet" ;;
    25)    echo "SMTP" ;;
    110)   echo "POP3" ;;
    111)   echo "RPC/Portmapper" ;;
    135)   echo "MS RPC" ;;
    137)   echo "NetBIOS" ;;
    139)   echo "NetBIOS" ;;
    445)   echo "SMB" ;;
    512)   echo "rexec" ;;
    513)   echo "rlogin" ;;
    514)   echo "rsh/syslog" ;;
    1433)  echo "MSSQL" ;;
    3306)  echo "MySQL" ;;
    5432)  echo "PostgreSQL" ;;
    6379)  echo "Redis" ;;
    27017) echo "MongoDB" ;;
    *)     echo "unknown" ;;
  esac
}

# ==========================================================
# MODULE 6: PORT SCANNER  (target IP eingeben)
# ==========================================================
run_port_scanner() {
  log_section "Port Scanner"
  report_add "## Port Scanner"
  report_add ""

  echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Target IP / Host: ${C_RESET}"
  local target=""
  read -r target
  [[ -z "$target" ]] && log_warn "No target given. Skipping." && return 0

  echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Port range (e.g. 1-1024, default 1-1024): ${C_RESET}"
  local range=""
  read -r range
  [[ -z "$range" ]] && range="1-1024"

  log_info "Scanning $target ports $range ..."
  report_add "**Target:** $target  |  **Range:** $range"
  report_add ""

  # nmap preferred — fallback to pure bash TCP probe
  if require_cmd nmap; then
    log_info "Using nmap..."
    local nmap_out
    nmap_out=$("${SUDO[@]}" nmap -sS -p "$range" --open -T4 "$target" 2>/dev/null || \
               nmap -sT -p "$range" --open -T4 "$target" 2>/dev/null || true)
    echo "$nmap_out" | tee -a "$LOG_FILE"
    report_add '```'
    echo "$nmap_out" >> "$REPORT_FILE" 2>/dev/null || true
    report_add '```'
  else
    log_warn "nmap not found — using basic bash TCP probe (slow for large ranges)."
    local start end
    start="${range%-*}"
    end="${range#*-}"
    [[ "$start" == "$range" ]] && end="$start"   # single port
    local open_ports=()
    for (( p=start; p<=end; p++ )); do
      if timeout 0.5 bash -c "echo >/dev/tcp/$target/$p" 2>/dev/null; then
        log_find "OPEN  $p/tcp  ($(get_port_name "$p"))"
        open_ports+=("$p")
        report_add "- ✅ Port **$p** open ($(get_port_name "$p"))"
      fi
    done
    [[ ${#open_ports[@]} -eq 0 ]] && log_ok "No open ports found in range $range."
  fi

  log_ok "Port scan complete."
  report_add ""
}

# ==========================================================
# MODULE 7: ARP SCAN  (devices on local network)
# ==========================================================
run_arp_scan() {
  log_section "ARP Scan — Local Network Devices"
  report_add "## ARP Scan"
  report_add ""

  # Detect local subnet automatically
  local iface subnet
  iface=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
  subnet=$(ip -o -f inet addr show "${iface:-}" 2>/dev/null \
    | awk '{print $4}' | head -1)

  if [[ -z "$subnet" ]]; then
    echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Could not detect subnet. Enter manually (e.g. 192.168.1.0/24): ${C_RESET}"
    read -r subnet
  else
    log_info "Detected subnet: ${C_BOLD}$subnet${C_RESET} on interface ${C_BOLD}$iface${C_RESET}"
    echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Scan $subnet? or enter different subnet: ${C_RESET}"
    local custom=""
    read -r custom
    [[ -n "$custom" ]] && subnet="$custom"
  fi

  [[ -z "$subnet" ]] && log_warn "No subnet given. Skipping." && return 0

  report_add "**Subnet scanned:** $subnet"
  report_add ""
  report_add "| IP Address | MAC Address | Vendor |"
  report_add "|---|---|---|"

  if require_cmd arp-scan; then
    log_info "Using arp-scan on $subnet ..."
    local result
    result=$("${SUDO[@]}" arp-scan "$subnet" 2>/dev/null || true)
    echo "$result" | tee -a "$LOG_FILE"
    # Parse into report
    echo "$result" | grep -E '^[0-9]' | while IFS=$'\t' read -r ip mac vendor; do
      report_add "| $ip | $mac | $vendor |"
    done
  elif require_cmd nmap; then
    log_info "Using nmap ping scan on $subnet ..."
    local result
    result=$("${SUDO[@]}" nmap -sn "$subnet" 2>/dev/null || true)
    echo "$result" | tee -a "$LOG_FILE"
    echo "$result" | grep "Nmap scan report" | awk '{print $NF}' | while read -r ip; do
      local mac
      mac=$(arp -n "$ip" 2>/dev/null | awk '/ether/{print $3}' || echo "unknown")
      report_add "| $ip | $mac | — |"
    done
  else
    log_warn "Neither arp-scan nor nmap found."
    log_info "Trying basic ping sweep (slow)..."
    local net="${subnet%.*}"
    for i in $(seq 1 254); do
      if ping -c1 -W1 "${net}.${i}" &>/dev/null; then
        local mac
        mac=$(arp -n "${net}.${i}" 2>/dev/null | awk '/ether/{print $3}' || echo "?")
        log_find "${net}.${i}  —  $mac"
        report_add "| ${net}.${i} | $mac | — |"
      fi
    done
  fi

  log_ok "ARP scan complete."
  report_add ""
}

# ==========================================================
# MODULE 8: BRUTE-FORCE / LOGIN MONITOR
# ==========================================================
run_bruteforce_monitor() {
  log_section "Brute-Force & Login Attack Monitor"
  report_add "## Brute-Force Monitor"
  report_add ""

  local issues=0

  # --- Failed SSH attempts ---
  log_info "Failed SSH login attempts (last 50):"
  local ssh_fails=""
  if require_cmd journalctl; then
    ssh_fails=$("${SUDO[@]}" journalctl -u ssh -u sshd --no-pager --since "7 days ago" 2>/dev/null \
      | grep -i "failed\|invalid\|refused" | tail -50 || true)
  elif [[ -f /var/log/auth.log ]]; then
    ssh_fails=$("${SUDO[@]}" grep -i "failed password\|invalid user" /var/log/auth.log 2>/dev/null | tail -50 || true)
  elif [[ -f /var/log/secure ]]; then
    ssh_fails=$("${SUDO[@]}" grep -i "failed password\|invalid user" /var/log/secure 2>/dev/null | tail -50 || true)
  fi

  if [[ -n "$ssh_fails" ]]; then
    local count; count=$(echo "$ssh_fails" | wc -l)
    log_warn "Found ${C_BOLD}$count${C_RESET} failed SSH login attempts in last 7 days."
    echo "$ssh_fails" | tee -a "$LOG_FILE"
    report_add "### Failed SSH Attempts (last 7 days)"
    report_add "**Count:** $count"
    report_add '```'
    echo "$ssh_fails" >> "$REPORT_FILE" 2>/dev/null || true
    report_add '```'
    (( issues++ )) || true

    # Top attacking IPs
    log_info "Top 10 attacking IPs:"
    local top_ips
    top_ips=$(echo "$ssh_fails" \
      | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | sort | uniq -c | sort -rn | head -10 || true)
    if [[ -n "$top_ips" ]]; then
      echo "$top_ips" | while read -r cnt ip; do
        log_find "  ${C_BOLD}$cnt${C_RESET} attempts  →  $ip"
      done
      report_add "**Top Attacking IPs:**"
      report_add '```'
      echo "$top_ips" >> "$REPORT_FILE" 2>/dev/null || true
      report_add '```'
    fi
  else
    log_ok "No failed SSH attempts found in the last 7 days."
    report_add "- ✅ No failed SSH attempts found"
  fi

  # --- Currently banned IPs (fail2ban) ---
  log_info "Checking fail2ban status..."
  if require_cmd fail2ban-client; then
    local banned
    banned=$("${SUDO[@]}" fail2ban-client status sshd 2>/dev/null || \
             "${SUDO[@]}" fail2ban-client status 2>/dev/null || true)
    if [[ -n "$banned" ]]; then
      echo "$banned" | tee -a "$LOG_FILE"
      report_add "### Fail2ban Status"
      report_add '```'
      echo "$banned" >> "$REPORT_FILE" 2>/dev/null || true
      report_add '```'
    fi
  else
    log_info "fail2ban not installed (recommended for SSH protection)."
    report_add "- ℹ️  fail2ban not installed — consider installing it"
  fi

  # --- Successful logins ---
  log_info "Recent successful logins:"
  if require_cmd last; then
    last 2>/dev/null | head -20 | tee -a "$LOG_FILE" || true
  fi

  # --- Currently logged in users ---
  log_info "Users currently logged in:"
  if require_cmd who; then
    who | tee -a "$LOG_FILE" || true
  fi

  # --- Root login check ---
  log_info "Checking for direct root SSH logins..."
  local root_logins=""
  if require_cmd journalctl; then
    root_logins=$("${SUDO[@]}" journalctl -u ssh -u sshd --no-pager --since "30 days ago" 2>/dev/null \
      | grep "Accepted.*root" || true)
  elif [[ -f /var/log/auth.log ]]; then
    root_logins=$("${SUDO[@]}" grep "Accepted.*root" /var/log/auth.log 2>/dev/null || true)
  fi
  if [[ -n "$root_logins" ]]; then
    log_warn "Direct root SSH logins detected:"
    echo "$root_logins" | while read -r line; do log_find "$line"; done
    report_add "- ⚠️  **Direct root logins detected** — disable PermitRootLogin"
    (( issues++ )) || true
  else
    log_ok "No direct root SSH logins found."
    report_add "- ✅ No direct root logins"
  fi

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    log_ok "Brute-force monitor complete — no critical issues."
    report_add "✅ **No critical brute-force issues found.**"
  else
    log_warn "Brute-force monitor — ${issues} issue(s) found. Review above."
    report_add "⚠️ **$issues issue(s) found.**"
  fi
  report_add ""
}

# ==========================================================
# MODULE 9: BANDWIDTH MONITOR  (live + summary)
# ==========================================================
run_bandwidth_monitor() {
  log_section "Bandwidth Monitor"
  report_add "## Bandwidth Monitor"
  report_add ""

  # Detect primary interface
  local iface
  iface=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
  if [[ -z "$iface" ]]; then
    echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Interface (e.g. eth0, ens3): ${C_RESET}"
    read -r iface
  else
    log_info "Detected interface: ${C_BOLD}$iface${C_RESET}"
  fi
  [[ -z "$iface" ]] && log_warn "No interface given. Skipping." && return 0

  local rx_file="/sys/class/net/${iface}/statistics/rx_bytes"
  local tx_file="/sys/class/net/${iface}/statistics/tx_bytes"

  if [[ ! -f "$rx_file" ]]; then
    log_warn "/sys/class/net/$iface not found. Check interface name."
    return 1
  fi

  # --- Snapshot over 5 seconds ---
  log_info "Sampling traffic on $iface for 5 seconds..."
  local rx1 tx1 rx2 tx2
  rx1=$(cat "$rx_file"); tx1=$(cat "$tx_file")
  sleep 5
  rx2=$(cat "$rx_file"); tx2=$(cat "$tx_file")

  local rx_diff=$(( rx2 - rx1 ))
  local tx_diff=$(( tx2 - tx1 ))
  local rx_kbps=$(( rx_diff / 1024 / 5 ))
  local tx_kbps=$(( tx_diff / 1024 / 5 ))

  log_ok "Interface: ${C_BOLD}$iface${C_RESET}"
  log_ok "  ↓  Download: ${C_BOLD}${rx_kbps} KB/s${C_RESET}"
  log_ok "  ↑  Upload:   ${C_BOLD}${tx_kbps} KB/s${C_RESET}"

  report_add "**Interface:** $iface"
  report_add "| Direction | Speed |"
  report_add "|---|---|"
  report_add "| ↓ Download | ${rx_kbps} KB/s |"
  report_add "| ↑ Upload   | ${tx_kbps} KB/s |"

  # --- Total traffic since boot ---
  local rx_total tx_total
  rx_total=$(cat "$rx_file")
  tx_total=$(cat "$tx_file")
  local rx_mb=$(( rx_total / 1024 / 1024 ))
  local tx_mb=$(( tx_total / 1024 / 1024 ))
  log_info "Total since boot — ↓ ${rx_mb} MB received  |  ↑ ${tx_mb} MB sent"
  report_add ""
  report_add "**Total since boot:** ↓ ${rx_mb} MB received  |  ↑ ${tx_mb} MB sent"

  # --- Top network connections ---
  log_info "Top active network connections:"
  if require_cmd ss; then
    "${SUDO[@]}" ss -tnp 2>/dev/null | head -20 | tee -a "$LOG_FILE" || true
  fi

  # --- Optional: live monitor with nethogs/iftop ---
  if require_cmd nethogs; then
    echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Launch live nethogs monitor? (30s) [y/n]: ${C_RESET}"
    local ans=""
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      log_info "Launching nethogs for 30 seconds (Ctrl+C to stop early)..."
      timeout 30 "${SUDO[@]}" nethogs "$iface" 2>/dev/null || true
    fi
  elif require_cmd iftop; then
    echo -ne "${M_RUN}  ❯ ${C_RESET}${M_LABEL}Launch live iftop monitor? (30s) [y/n]: ${C_RESET}"
    local ans=""
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      log_info "Launching iftop for 30 seconds..."
      timeout 30 "${SUDO[@]}" iftop -i "$iface" 2>/dev/null || true
    fi
  else
    log_info "Tip: install 'nethogs' or 'iftop' for per-process live bandwidth monitoring."
  fi

  log_ok "Bandwidth monitor complete."
  report_add ""
}

# ==========================================================
# MODULE 3: SECURITY AUDIT
# ==========================================================
run_security_audit() {
  log_section "Security Audit"
  report_add "## Security Audit"
  report_add ""
  local issues=0

  # --- SUID/SGID binaries ---
  log_info "Scanning for SUID/SGID binaries (excluding known safe paths)..."
  local suid_list
  suid_list=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null \
    | grep -Ev '^(/usr/bin|/usr/sbin|/bin|/sbin|/usr/lib|/usr/libexec)' \
    | head -30 || true)
  if [[ -n "$suid_list" ]]; then
    log_warn "Unusual SUID/SGID files found (outside standard paths):"
    echo "$suid_list" | while read -r f; do
      log_find "$f"
      report_add "- ⚠️  SUID/SGID: \`$f\`"
    done
    (( issues++ )) || true
  else
    log_ok "No unusual SUID/SGID binaries found."
    report_add "- ✅ No unusual SUID/SGID binaries"
  fi

  # --- World-writable files/dirs (outside /tmp /proc /sys /dev) ---
  log_info "Scanning for world-writable files (excluding /tmp, /proc, /sys, /dev)..."
  local ww_list
  ww_list=$(find / -xdev -perm -0002 -not -path '/proc/*' -not -path '/sys/*' \
    -not -path '/dev/*' -not -path '/tmp/*' -not -path '/run/*' \
    -type f 2>/dev/null | head -20 || true)
  if [[ -n "$ww_list" ]]; then
    log_warn "World-writable files found:"
    echo "$ww_list" | while read -r f; do
      log_find "$f"
      report_add "- ⚠️  World-writable: \`$f\`"
    done
    (( issues++ )) || true
  else
    log_ok "No world-writable files outside temp paths."
    report_add "- ✅ No world-writable files found"
  fi

  # --- /etc/passwd integrity ---
  log_info "Checking for non-standard shell users in /etc/passwd..."
  local shell_users
  shell_users=$(grep -vE '(nologin|false|sync|halt|shutdown)$' /etc/passwd \
    | grep -vE '^(root|#)' | awk -F: '{print $1 " → " $7}' || true)
  if [[ -n "$shell_users" ]]; then
    log_warn "Users with interactive shells (review recommended):"
    echo "$shell_users" | while read -r line; do
      log_find "$line"
      report_add "- ℹ️  Shell user: $line"
    done
  else
    log_ok "No unexpected shell users found."
    report_add "- ✅ No unexpected shell users"
  fi

  # --- Empty password check ---
  log_info "Checking for accounts with empty passwords..."
  local empty_pass
  empty_pass=$("${SUDO[@]}" awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null | grep -v '^$' || true)
  if [[ -n "$empty_pass" ]]; then
    log_warn "Accounts with empty/locked passwords: $empty_pass"
    report_add "- ⚠️  Accounts with empty passwords: $empty_pass"
    (( issues++ )) || true
  else
    log_ok "No empty-password accounts found."
    report_add "- ✅ No empty-password accounts"
  fi

  # --- SSH hardening check ---
  log_info "Checking SSH configuration..."
  local sshd_conf="/etc/ssh/sshd_config"
  if [[ -f "$sshd_conf" ]]; then
    report_add "### SSH Configuration"
    local ssh_checks=(
      "PermitRootLogin:no:Root login should be disabled"
      "PasswordAuthentication:no:Password auth should be disabled (use keys)"
      "X11Forwarding:no:X11 Forwarding should be disabled"
      "PermitEmptyPasswords:no:Empty passwords must be denied"
      "Protocol:2:Only Protocol 2 should be allowed"
    )
    for check in "${ssh_checks[@]}"; do
      local setting="${check%%:*}"
      local rest="${check#*:}"
      local expected="${rest%%:*}"
      local desc="${rest#*:}"
      local current
      current=$("${SUDO[@]}" grep -iE "^[[:space:]]*${setting}[[:space:]]" "$sshd_conf" 2>/dev/null | awk '{print $2}' | head -1 || echo "default")
      if [[ -z "$current" || "$current" == "default" ]]; then
        log_warn "$setting not explicitly set (check distro default) — $desc"
        report_add "- ⚠️  \`$setting\` not set — $desc"
      elif [[ "${current,,}" == "${expected,,}" ]]; then
        log_ok "$setting = $current ✔"
        report_add "- ✅ \`$setting\` = $current"
      else
        log_warn "$setting = $current (expected: $expected) — $desc"
        report_add "- ⚠️  \`$setting\` = $current (expected: $expected)"
        (( issues++ )) || true
      fi
    done
  else
    log_info "sshd_config not found (SSH may not be installed)."
  fi

  # --- Sudo without password ---
  log_info "Checking for NOPASSWD sudo entries..."
  local nopasswd
  nopasswd=$("${SUDO[@]}" grep -ri "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#' || true)
  if [[ -n "$nopasswd" ]]; then
    log_warn "NOPASSWD sudo entries found:"
    echo "$nopasswd" | while read -r line; do
      log_find "$line"
      report_add "- ⚠️  NOPASSWD sudo: $line"
    done
    (( issues++ )) || true
  else
    log_ok "No NOPASSWD sudo entries."
    report_add "- ✅ No NOPASSWD sudo entries"
  fi

  # --- Failed login attempts ---
  log_info "Recent failed login attempts (last 20):"
  if require_cmd lastb; then
    "${SUDO[@]}" lastb 2>/dev/null | head -20 | tee -a "$LOG_FILE" || true
  elif [[ -f /var/log/auth.log ]]; then
    "${SUDO[@]}" grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 | tee -a "$LOG_FILE" || true
  elif [[ -f /var/log/secure ]]; then
    "${SUDO[@]}" grep "Failed password" /var/log/secure 2>/dev/null | tail -10 | tee -a "$LOG_FILE" || true
  fi

  # --- Summary ---
  echo ""
  if [[ "$issues" -eq 0 ]]; then
    log_ok "Security audit complete — ${C_BOLD}no critical issues found.${C_RESET}"
    report_add ""
    report_add "✅ **Security audit: No critical issues found.**"
  else
    log_warn "Security audit complete — ${C_BOLD}${issues} issue(s) found. Review above.${C_RESET}"
    report_add ""
    report_add "⚠️ **Security audit: $issues issue(s) found. Review report.**"
  fi
  report_add ""
}

# ==========================================================
# MODULE 4: SYSTEM HEALTH CHECK
# ==========================================================
run_health_check() {
  log_section "System Health Check"
  report_add "## System Health Check"
  report_add ""

  # Uptime
  log_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
  report_add "**Uptime:** $(uptime -p 2>/dev/null || uptime)"

  # CPU load
  local load1 load5 load15 cpus
  if [[ -f /proc/loadavg ]]; then
    read -r load1 load5 load15 _ < /proc/loadavg
    cpus=$(nproc 2>/dev/null || echo 1)
    log_info "Load average: ${C_BOLD}$load1 $load5 $load15${C_RESET} (CPUs: $cpus)"
    report_add "**Load average:** $load1 / $load5 / $load15 (CPUs: $cpus)"
    local load_int=${load1%.*}
    if (( load_int >= cpus * 2 )); then
      log_warn "HIGH CPU load detected!"
      report_add "- ⚠️  High CPU load!"
    elif (( load_int >= cpus )); then
      log_warn "Elevated CPU load."
      report_add "- ⚠️  Elevated CPU load"
    else
      log_ok "CPU load normal."
      report_add "- ✅ CPU load normal"
    fi
  fi

  # Memory
  if require_cmd free; then
    local mem_line
    mem_line=$(free -h | grep "^Mem:")
    local total avail
    total=$(echo "$mem_line" | awk '{print $2}')
    avail=$(echo "$mem_line" | awk '{print $7}')
    log_info "Memory — Total: ${C_BOLD}$total${C_RESET}  Available: ${C_BOLD}$avail${C_RESET}"
    report_add "**Memory:** Total $total / Available $avail"
    local avail_mb
    avail_mb=$(free -m | awk '/^Mem:/{print $7}')
    if (( avail_mb < 256 )); then
      log_warn "LOW MEMORY: only ${avail_mb}MB available!"
      report_add "- ⚠️  Low memory: ${avail_mb}MB available"
    elif (( avail_mb < 512 )); then
      log_warn "Memory somewhat low: ${avail_mb}MB available."
      report_add "- ⚠️  Memory low: ${avail_mb}MB"
    else
      log_ok "Memory OK: ${avail_mb}MB available."
      report_add "- ✅ Memory OK"
    fi
  fi

  # Disk usage
  log_info "Disk usage:"
  df -h --output=target,size,used,avail,pcent 2>/dev/null | grep -v tmpfs | tee -a "$LOG_FILE" || df -h | tee -a "$LOG_FILE"
  report_add "### Disk Usage"
  report_add '```'
  df -h --output=target,size,used,avail,pcent 2>/dev/null | grep -v tmpfs >> "$REPORT_FILE" 2>/dev/null || true
  report_add '```'

  # Check disks over 85%
  while IFS= read -r line; do
    local pct mp
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mp=$(echo "$line" | awk '{print $1}')
    [[ "$pct" =~ ^[0-9]+$ ]] || continue
    if (( pct >= 90 )); then
      log_warn "CRITICAL: ${C_BOLD}${mp}${C_RESET} is ${pct}% full!"
      report_add "- ⚠️  **$mp** is ${pct}% full (CRITICAL)"
    elif (( pct >= 85 )); then
      log_warn "WARNING: ${mp} is ${pct}% full."
      report_add "- ⚠️  $mp is ${pct}% full"
    fi
  done < <(df --output=target,pcent 2>/dev/null | tail -n +2 | grep -v tmpfs || true)

  # Failed systemd services
  if require_cmd systemctl; then
    log_info "Failed systemd services:"
    local failed_svcs
    failed_svcs=$(systemctl list-units --state=failed --no-pager --no-legend 2>/dev/null || true)
    if [[ -n "$failed_svcs" ]]; then
      log_warn "Failed services:"
      echo "$failed_svcs" | tee -a "$LOG_FILE"
      report_add "### Failed Services"
      report_add '```'
      echo "$failed_svcs" >> "$REPORT_FILE"
      report_add '```'
    else
      log_ok "No failed systemd services."
      report_add "- ✅ No failed services"
    fi
  fi

  # Last kernel panic / OOM check
  if require_cmd journalctl; then
    log_info "Checking for recent OOM kills..."
    local oom_count
    oom_count=$("${SUDO[@]}" journalctl -k -b -p err --no-pager 2>/dev/null | grep -ci "oom" || echo 0)
    if (( oom_count > 0 )); then
      log_warn "OOM events in current boot: $oom_count"
      report_add "- ⚠️  OOM events this boot: $oom_count"
    else
      log_ok "No OOM events in current boot."
      report_add "- ✅ No OOM kills this boot"
    fi
  fi

  # Top 10 memory consumers
  log_info "Top 10 memory consumers:"
  ps aux --sort=-%mem 2>/dev/null | awk 'NR==1 || NR<=11 {printf "%-12s %5s %5s %s\n",$1,$2,$3,$11}' | tee -a "$LOG_FILE" || true

  log_ok "Health check complete."
  report_add ""
}

# ==========================================================
# MODULE 5: APP CACHE CLEANER
# ==========================================================
run_appcache_clean() {
  log_section "App Cache Cleanup"
  report_add "## App Cache Cleanup"
  report_add ""

  # npm cache
  if require_cmd npm; then
    local npm_size
    npm_size=$(du -sh "$(npm config get cache 2>/dev/null)" 2>/dev/null | cut -f1 || echo "?")
    log_info "npm cache size: $npm_size"
    if confirm "Clean npm cache?"; then
      run_cmd "npm cache clean" npm cache clean --force || true
      log_ok "npm cache cleaned."
      report_add "- ✅ npm cache cleaned ($npm_size freed)"
    else
      report_add "- ⏭️  npm cache skipped"
    fi
  fi

  # pip cache
  if require_cmd pip; then
    log_info "Cleaning pip cache..."
    if confirm "Clean pip cache?"; then
      run_cmd "pip cache purge" pip cache purge 2>/dev/null || true
      log_ok "pip cache cleaned."
      report_add "- ✅ pip cache cleaned"
    fi
  elif require_cmd pip3; then
    if confirm "Clean pip3 cache?"; then
      run_cmd "pip3 cache purge" pip3 cache purge 2>/dev/null || true
      log_ok "pip3 cache cleaned."
      report_add "- ✅ pip3 cache cleaned"
    fi
  fi

  # cargo / rust registry
  if require_cmd cargo; then
    local cargo_registry="$TARGET_HOME/.cargo/registry"
    if [[ -d "$cargo_registry" ]]; then
      local cargo_size
      cargo_size=$(du -sh "$cargo_registry" 2>/dev/null | cut -f1 || echo "?")
      log_info "Cargo registry cache: $cargo_size"
      if confirm "Clean Cargo registry cache ($cargo_size)?"; then
        if [[ "$DRY_RUN" -ne 1 ]]; then
          rm -rf "$cargo_registry" 2>&1 | tee -a "$LOG_FILE" || true
        fi
        log_ok "Cargo registry cleaned."
        report_add "- ✅ Cargo registry cleaned ($cargo_size freed)"
      fi
    fi
  fi

  # Go module cache
  if require_cmd go; then
    log_info "Cleaning Go module cache..."
    if confirm "Run go clean -modcache?"; then
      run_cmd "go clean -modcache" go clean -modcache || true
      log_ok "Go module cache cleaned."
      report_add "- ✅ Go module cache cleaned"
    fi
  fi

  # Maven local repository
  if [[ -d "$TARGET_HOME/.m2/repository" ]]; then
    local mvn_size
    mvn_size=$(du -sh "$TARGET_HOME/.m2/repository" 2>/dev/null | cut -f1 || echo "?")
    log_info "Maven local repo: $mvn_size"
    if confirm "Clean Maven local repository ($mvn_size)?"; then
      if [[ "$DRY_RUN" -ne 1 ]]; then
        rm -rf "$TARGET_HOME/.m2/repository" 2>&1 | tee -a "$LOG_FILE" || true
      fi
      log_ok "Maven repository cleaned."
      report_add "- ✅ Maven repo cleaned ($mvn_size freed)"
    fi
  fi

  # Gradle cache
  if [[ -d "$TARGET_HOME/.gradle/caches" ]]; then
    local gradle_size
    gradle_size=$(du -sh "$TARGET_HOME/.gradle/caches" 2>/dev/null | cut -f1 || echo "?")
    log_info "Gradle cache: $gradle_size"
    if confirm "Clean Gradle cache ($gradle_size)?"; then
      if [[ "$DRY_RUN" -ne 1 ]]; then
        rm -rf "$TARGET_HOME/.gradle/caches" 2>&1 | tee -a "$LOG_FILE" || true
      fi
      log_ok "Gradle cache cleaned."
      report_add "- ✅ Gradle cache cleaned ($gradle_size freed)"
    fi
  fi

  log_ok "App cache cleanup complete."
  report_add ""
}

# ==========================================================
# MAIN EXECUTION
# ==========================================================
initial_used_bytes="$(df -B1 --output=used / | tail -n 1 | tr -d ' ')"
log_info "Initial disk usage:"
df -h / | tee -a "$LOG_FILE"
report_add "## Initial Disk Usage"
report_add '```'
df -h / >> "$REPORT_FILE" 2>/dev/null || true
report_add '```'
report_add ""

# Execute modules
if [[ "$MOD_CLEAN" -eq 1 ]]; then
  cleanup_packages
  cleanup_journal
  cleanup_temp
  cleanup_large_logs
  cleanup_user_cache
  cleanup_flatpak
  cleanup_snap
  cleanup_docker
fi

[[ "$MOD_NETWORK"  -eq 1 ]] && run_network_audit
[[ "$MOD_SECURITY" -eq 1 ]] && run_security_audit
[[ "$MOD_HEALTH"   -eq 1 ]] && run_health_check
[[ "$MOD_APPCACHE" -eq 1 ]] && run_appcache_clean

# ---------- Final stats ----------
final_used_bytes="$(df -B1 --output=used / | tail -n 1 | tr -d ' ')"
log_section "Summary"
log_info "Final disk usage:"
df -h / | tee -a "$LOG_FILE"

report_add "## Final Disk Usage"
report_add '```'
df -h / >> "$REPORT_FILE" 2>/dev/null || true
report_add '```'
report_add ""

freed_bytes=$(( initial_used_bytes - final_used_bytes ))
if [[ "$freed_bytes" -ge 0 ]]; then
  freed_human="$freed_bytes bytes"
  require_cmd numfmt && freed_human="$(numfmt --to=iec-i --suffix=B "$freed_bytes")"
  log_ok "${C_BOLD}Total space freed: $freed_human${C_RESET}"
  report_add "**Total space freed:** $freed_human"
else
  increased=$(( -freed_bytes ))
  increased_human="$increased bytes"
  require_cmd numfmt && increased_human="$(numfmt --to=iec-i --suffix=B "$increased")"
  log_info "Disk usage increased by $increased_human (normal: log/metadata updates)."
  report_add "**Note:** Disk usage increased by $increased_human (log/metadata updates)"
fi

if [[ "$REPORT_MODE" -eq 1 ]]; then
  {
    echo ""
    echo "---"
    echo "*Generated by linux-admin-cleaner v${VERSION} — $(date '+%F %T')*"
  } >> "$REPORT_FILE"
  echo -e "\n${C_BOLD}${C_GREEN}  ✔  Report saved: $REPORT_FILE${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}  ✔  All done! Log: $LOG_FILE${C_RESET}\n"
