#!/bin/zsh
#
# configure_timemachine.sh
# Configures Time Machine to back up to a local external drive.
# Compatible with macOS Ventura (13.x) and Sonoma (14.x).
#
# Usage: sudo zsh configure_timemachine.sh

set -euo pipefail

# --- Preflight checks --------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run with sudo."
    echo "  sudo zsh $0"
    exit 1
fi

os_ver="$(sw_vers -productVersion)"
major_ver="${os_ver%%.*}"

if [[ "$major_ver" -ne 13 && "$major_ver" -ne 14 ]]; then
    echo "Error: This script supports macOS Ventura (13) and Sonoma (14)."
    echo "  Detected version: $os_ver"
    exit 1
fi

# Check for Full Disk Access by attempting to read a TCC-protected path.
if ! ls /Library/Application\ Support/com.apple.TCC/ &>/dev/null; then
    echo "Warning: Your terminal app does not have Full Disk Access."
    echo ""
    echo "Opening System Settings > Privacy & Security > Full Disk Access ..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    echo ""
    echo "Please grant Full Disk Access to your terminal app, then press Enter to continue."
    read -r
    if ! ls /Library/Application\ Support/com.apple.TCC/ &>/dev/null; then
        echo "Error: Full Disk Access still not detected."
        echo "  You may need to restart your terminal after granting the permission."
        exit 1
    fi
fi

echo "macOS $os_ver detected. Proceeding with Time Machine configuration."
echo ""

# --- Select local drive -------------------------------------------------------

echo "Available volumes:"
echo "---"
ls /Volumes/
echo "---"
echo ""
read "tm_vol?Enter the volume name exactly as shown above: "

if [[ -z "$tm_vol" ]]; then
    echo "Error: No volume name entered."
    exit 1
fi

tm_mount="/Volumes/${tm_vol}"

if [[ ! -d "$tm_mount" ]]; then
    echo "Error: ${tm_mount} not found. Make sure the drive is connected and mounted."
    exit 1
fi

# --- Optional: Exclude paths --------------------------------------------------

excludes=()
echo ""
read "add_excludes?Would you like to exclude any directories from backup? (y/n): "

if [[ "$add_excludes" == "y" ]]; then
    echo "Enter full paths to exclude, one per line. Enter a blank line when done."
    while true; do
        read "exc_path?  Path: "
        if [[ -z "$exc_path" ]]; then
            break
        fi
        if [[ -e "$exc_path" ]]; then
            excludes+=("$exc_path")
        else
            echo "  Warning: '$exc_path' does not exist. Skipping."
        fi
    done
fi

# --- Apply configuration -----------------------------------------------------

echo ""
echo "==> Setting Time Machine destination to ${tm_mount} ..."
tmutil setdestination -a "$tm_mount"

echo "==> Enabling Time Machine ..."
tmutil enable

if [[ ${#excludes[@]} -gt 0 ]]; then
    for exc in "${excludes[@]}"; do
        echo "==> Excluding: $exc"
        tmutil addexclusion "$exc"
    done
fi

# --- Optional: Start an immediate backup --------------------------------------

echo ""
read "start_now?Start an immediate backup now? (y/n): "

if [[ "$start_now" == "y" ]]; then
    echo "==> Starting backup ..."
    tmutil startbackup --block
    echo "Backup complete."
else
    echo "Backup will begin automatically on the next scheduled interval."
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "Time Machine configuration complete."
echo "  Destination : ${tm_mount}"
echo "  Exclusions  : ${#excludes[@]}"
tmutil destinationinfo
