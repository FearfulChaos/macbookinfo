#!/usr/bin/env bash

# ─────────────────────────────────────────────
#  MacBook Device Info
# ─────────────────────────────────────────────

BOLD="\033[1m"
CYAN="\033[36m"
RESET="\033[0m"

label() { printf "${BOLD}${CYAN}%-16s${RESET} %s\n" "$1" "$2"; }
divider() { printf "${CYAN}%s${RESET}\n" "────────────────────────────────────────"; }

divider
printf "${BOLD}   MacBook Device Information${RESET}\n"
divider

# Hostname
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
label "Hostname:" "$HOSTNAME"

# Current User
label "User:" "$(whoami)"

# IP Address (prefer en0, fall back to first active interface)
IP=$(ipconfig getifaddr en0 2>/dev/null)
if [[ -z "$IP" ]]; then
  IP=$(ifconfig | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}')
fi
label "IP Address:" "${IP:-N/A}"

# MAC Address (en0)
MAC=$(ifconfig en0 2>/dev/null | awk '/ether/{print $2}')
label "MAC Address:" "${MAC:-N/A}"

# OS Version
OS_NAME=$(sw_vers -productName)
OS_VER=$(sw_vers -productVersion)
OS_BUILD=$(sw_vers -buildVersion)
label "OS Version:" "$OS_NAME $OS_VER (Build $OS_BUILD)"

# Model Identifier
MODEL=$(sysctl -n hw.model 2>/dev/null)
label "Model:" "${MODEL:-N/A}"

# Architecture
ARCH=$(uname -m)
case "$ARCH" in
  arm64)  ARCH_LABEL="Apple Silicon (arm64)" ;;
  x86_64) ARCH_LABEL="Intel (x86_64)" ;;
  *)      ARCH_LABEL="$ARCH" ;;
esac
label "Architecture:" "$ARCH_LABEL"

# CPU
CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
CPU_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null)
CPU_THREADS=$(sysctl -n hw.logicalcpu 2>/dev/null)
label "CPU:" "$CPU"
label "CPU Cores:" "$CPU_CORES physical / $CPU_THREADS logical"

# GPU
GPU=$(system_profiler SPDisplaysDataType 2>/dev/null \
  | awk -F': ' '/Chipset Model/{print $2; exit}')
label "GPU:" "${GPU:-N/A}"

# Memory
MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null)
MEM_GB=$(( MEM_BYTES / 1073741824 ))
label "Memory:" "${MEM_GB} GB"

# Storage
DISK_INFO=$(df -H / | awk 'NR==2 {printf "%s total, %s used, %s free", $2, $3, $4}')
label "Storage (/):" "$DISK_INFO"

# Uptime
UPTIME=$(uptime | sed 's/.*up //' | sed 's/,.*//')
label "Uptime:" "$UPTIME"

divider

# ─────────────────────────────────────────────
#  Export to Numbers spreadsheet
# ─────────────────────────────────────────────
OUTFILE="$HOME/Desktop/DeviceInfo_$(date '+%Y-%m-%d_%H%M%S').numbers"

OSFULL="$OS_NAME $OS_VER (Build $OS_BUILD)"
CPUFULL="$CPU ($CPU_CORES physical / $CPU_THREADS logical)"
USER_NAME=$(whoami)

# Write AppleScript to a temp file to avoid heredoc escaping issues
TMPSCRIPT=$(mktemp /tmp/device_info_XXXXXX.applescript)
{
  echo "set outputPath to \"$OUTFILE\""
  echo "tell application \"Numbers\""
  echo "  set doc to make new document"
  echo "  tell sheet 1 of doc"
  echo "    tell table 1"
  echo "      set column count to 2"
  echo "      set row count to 13"
  echo "      set value of cell 1 of column 1 to \"Field\""
  echo "      set value of cell 1 of column 2 to \"Value\""
  echo "      set value of cell 2 of column 1 to \"Model\""
  echo "      set value of cell 2 of column 2 to \"$MODEL\""
  echo "      set value of cell 3 of column 1 to \"Hostname\""
  echo "      set value of cell 3 of column 2 to \"$HOSTNAME\""
  echo "      set value of cell 4 of column 1 to \"User\""
  echo "      set value of cell 4 of column 2 to \"$USER_NAME\""
  echo "      set value of cell 5 of column 1 to \"IP Address\""
  echo "      set value of cell 5 of column 2 to \"$IP\""
  echo "      set value of cell 6 of column 1 to \"MAC Address\""
  echo "      set value of cell 6 of column 2 to \"$MAC\""
  echo "      set value of cell 7 of column 1 to \"OS Version\""
  echo "      set value of cell 7 of column 2 to \"$OSFULL\""
  echo "      set value of cell 8 of column 1 to \"Architecture\""
  echo "      set value of cell 8 of column 2 to \"$ARCH_LABEL\""
  echo "      set value of cell 9 of column 1 to \"CPU\""
  echo "      set value of cell 9 of column 2 to \"$CPUFULL\""
  echo "      set value of cell 10 of column 1 to \"GPU\""
  echo "      set value of cell 10 of column 2 to \"$GPU\""
  echo "      set value of cell 11 of column 1 to \"Memory\""
  echo "      set value of cell 11 of column 2 to \"${MEM_GB} GB\""
  echo "      set value of cell 12 of column 1 to \"Storage (/)\""
  echo "      set value of cell 12 of column 2 to \"$DISK_INFO\""
  echo "      set value of cell 13 of column 1 to \"Uptime\""
  echo "      set value of cell 13 of column 2 to \"$UPTIME\""
  echo "    end tell"
  echo "  end tell"
  echo "  save doc in POSIX file outputPath"
  echo "  close doc"
  echo "end tell"
} > "$TMPSCRIPT"

osascript "$TMPSCRIPT"
EXIT_CODE=$?
rm -f "$TMPSCRIPT"

if [[ $EXIT_CODE -eq 0 ]]; then
  printf "${BOLD}${CYAN}%-16s${RESET} %s\n" "Exported:" "$OUTFILE"
else
  printf "${BOLD}\033[31m%-16s${RESET} %s\n" "Export failed:" "Check that Numbers is installed."
fi
divider
