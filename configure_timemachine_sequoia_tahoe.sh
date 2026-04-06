#!/bin/zsh
#
# configure_timemachine_sequoia_tahoe.sh
# Configures Time Machine to back up to a local external drive.
# Compatible with macOS Sequoia (15.x) and Tahoe (26.x).
#
# Usage: sudo zsh configure_timemachine_sequoia_tahoe.sh

set -euo pipefail

# --- Preflight checks --------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run with sudo."
    echo "  sudo zsh $0"
    exit 1
fi

os_ver="$(sw_vers -productVersion)"
major_ver="${os_ver%%.*}"

if [[ "$major_ver" -ne 15 && "$major_ver" -ne 26 ]]; then
    echo "Error: This script supports macOS Sequoia (15) and Tahoe (26)."
    echo "  Detected version: $os_ver"
    echo "  Please use this script for newer versions of macOS."
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
tmutil setdestination "$tm_mount"

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
    tmutil startbackup &>/dev/null

    # Wait briefly for the backup process to initialise.
    sleep 3

    bar_width=40
    while true; do
        tm_status="$(tmutil status 2>/dev/null)"

        # Exit the loop once Time Machine is no longer running a backup.
        if ! echo "$tm_status" | grep -q 'Running = 1'; then
            break
        fi

        # Extract the Percent value (0.0 – 1.0) from tmutil status output.
        pct_raw="$(echo "$tm_status" | grep 'Percent' | sed 's/[^0-9.]//g')"
        if [[ -z "$pct_raw" ]]; then
            pct_raw="0"
        fi

        # Convert to integer percentage (0 – 100).
        pct_int=$(printf '%.0f' "$(echo "$pct_raw * 100" | bc)")
        filled=$(( pct_int * bar_width / 100 ))
        empty=$(( bar_width - filled ))

        bar="$(printf '#%.0s' {1..$filled})$(printf '-%.0s' {1..$empty})"
        printf "\r  [%s] %3d%%" "$bar" "$pct_int"

        sleep 2
    done

    # Print a complete bar on finish.
    printf "\r  [%s] 100%%\n" "$(printf '#%.0s' {1..$bar_width})"
    echo "Backup complete."
    echo ""
    echo "Time Machine Backup successful, carefully eject the external hard drive using Finder."
else
    echo "Backup will begin automatically on the next scheduled interval."
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "Time Machine configuration complete."
echo "  Destination : ${tm_mount}"
echo "  Exclusions  : ${#excludes[@]}"
tmutil destinationinfo
