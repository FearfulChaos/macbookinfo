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
#  Export to Excel spreadsheet (.xlsx)
# ─────────────────────────────────────────────
OUTFILE="$HOME/Desktop/DeviceInfo_$(date '+%Y-%m-%d_%H%M%S').xlsx"

OSFULL="$OS_NAME $OS_VER (Build $OS_BUILD)"
CPUFULL="$CPU ($CPU_CORES physical / $CPU_THREADS logical)"
USER_NAME=$(whoami)

# Write a self-contained Python xlsx generator to a temp file.
# Uses only built-in modules (zipfile) — no Excel or pip install needed.
TMPSCRIPT=$(mktemp /tmp/device_info_XXXXXX.py)
cat > "$TMPSCRIPT" << 'PYEOF'
import sys, zipfile

def esc(s):
    return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")

args   = sys.argv[1:]
outf   = args[0]
pairs  = list(zip(args[1::2], args[2::2]))
rows   = [("Field", "Value")] + pairs

# Build shared-string table
strings, idx = [], {}
def si(s):
    if s not in idx:
        idx[s] = len(strings)
        strings.append(s)
    return idx[s]
for f, v in rows:
    si(f); si(v)

# sheet1.xml
sheet_rows = ""
for ri, (f, v) in enumerate(rows, 1):
    sheet_rows += (f'<row r="{ri}">'
                   f'<c r="A{ri}" t="s"><v>{si(f)}</v></c>'
                   f'<c r="B{ri}" t="s"><v>{si(v)}</v></c>'
                   f'</row>')
sheet_xml = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
             f'<sheetData>{sheet_rows}</sheetData></worksheet>')

# sharedStrings.xml
ss_items = "".join(f'<si><t xml:space="preserve">{esc(s)}</t></si>' for s in strings)
ss_xml = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          f'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
          f' count="{len(strings)}" uniqueCount="{len(strings)}">'
          f'{ss_items}</sst>')

wb_xml = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
          ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="Device Info" sheetId="1" r:id="rId1"/></sheets></workbook>')

wb_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
           '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
           '<Relationship Id="rId1"'
           ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"'
           ' Target="worksheets/sheet1.xml"/>'
           '<Relationship Id="rId2"'
           ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings"'
           ' Target="sharedStrings.xml"/></Relationships>')

content_types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                 '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                 '<Default Extension="xml" ContentType="application/xml"/>'
                 '<Override PartName="/xl/workbook.xml"'
                 ' ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
                 '<Override PartName="/xl/worksheets/sheet1.xml"'
                 ' ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                 '<Override PartName="/xl/sharedStrings.xml"'
                 ' ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
                 '</Types>')

root_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             '<Relationship Id="rId1"'
             ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"'
             ' Target="xl/workbook.xml"/></Relationships>')

with zipfile.ZipFile(outf, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml',       content_types)
    z.writestr('_rels/.rels',               root_rels)
    z.writestr('xl/workbook.xml',           wb_xml)
    z.writestr('xl/_rels/workbook.xml.rels', wb_rels)
    z.writestr('xl/worksheets/sheet1.xml',  sheet_xml)
    z.writestr('xl/sharedStrings.xml',      ss_xml)
PYEOF

python3 "$TMPSCRIPT" "$OUTFILE" \
  "Model"        "$MODEL"        \
  "Hostname"     "$HOSTNAME"     \
  "User"         "$USER_NAME"    \
  "IP Address"   "$IP"           \
  "MAC Address"  "$MAC"          \
  "OS Version"   "$OSFULL"       \
  "Architecture" "$ARCH_LABEL"   \
  "CPU"          "$CPUFULL"      \
  "GPU"          "$GPU"          \
  "Memory"       "${MEM_GB} GB" \
  "Storage (/)"  "$DISK_INFO"    \
  "Uptime"       "$UPTIME"
EXIT_CODE=$?
rm -f "$TMPSCRIPT"

if [[ $EXIT_CODE -eq 0 ]]; then
  printf "${BOLD}${CYAN}%-16s${RESET} %s\n" "Exported:" "$OUTFILE"
else
  printf "${BOLD}\033[31m%-16s${RESET} %s\n" "Export failed:" "Check that Python 3 is installed."
fi
divider
