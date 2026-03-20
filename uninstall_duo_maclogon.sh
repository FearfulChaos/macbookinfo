#!/bin/bash
# =============================================================================
# Duo Authentication for macOS (MacLogon) — Uninstall Script
# Targets: macOS 15 Sequoia / macOS 26 Tahoe
#
# This script removes the Duo MacLogon authorization plugin, restores the
# macOS authorization database to Apple defaults, and cleans up all
# associated configuration and offline-access data.
# 
# Macbooks refer to the system db for anything regarding user logins. So you're basically telling the machine to revert back to default db sign in without DUO.
# That's the point of this script. I had to do this shit for the NoMAD setup that I stupidly installed on my equip because I'm retarded.
#
# IMPORTANT: Run with sudo.  Back up your Mac before proceeding.
# =============================================================================

set -euo pipefail

LOG_PREFIX="[DuoUninstall]"
BACKUP_DIR="/var/tmp/duo_uninstall_backup_$(date +%Y%m%d_%H%M%S)"

# -- Duo MacLogon paths -------------------------------------------------
# You basically need to find the plist, bundle and plugins required to essentially tell DUO to fuck off.
PLUGIN_DIR="/Library/Security/SecurityAgentPlugins"
PLUGIN_BUNDLES=("DuoSecurityMacLogon.bundle" "MacLogon.bundle")
DUO_PLIST="/private/var/root/Library/Preferences/com.duosecurity.maclogon.plist"
AUTH_DB_RIGHT="system.login.console"

# -- Helper functions ---------------------------------------------------------
log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} [WARN] $*" >&2; }
die()  { echo "${LOG_PREFIX} [ERROR] $*" >&2; exit 1; }

# -- Pre-flight --------------------------------------------------------
if [[ $(id -u) -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
fi

log "========================================"
log "Duo MacLogon Uninstaller"
log "$(date)"
log "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
log "========================================"

# -- Create backup directory --------------------------------------------------
mkdir -p "${BACKUP_DIR}"
log "Backup directory: ${BACKUP_DIR}"

# =============================================
# 1. Restore the authorization DB
# =============================================
log ""
log "--- Step 1: Authorization database ---"

# Export current right so we have a rollback copy
if security authorizationdb read "${AUTH_DB_RIGHT}" > "${BACKUP_DIR}/auth_db_${AUTH_DB_RIGHT}.plist" 2>/dev/null; then
    log "Backed up '${AUTH_DB_RIGHT}' to ${BACKUP_DIR}/"
else
    warn "Could not back up '${AUTH_DB_RIGHT}' — it may already be at defaults."
fi

# Check whether Duo mechanisms are present
if security authorizationdb read "${AUTH_DB_RIGHT}" 2>/dev/null | grep -qi "duo"; then
    log "Duo mechanisms detected in '${AUTH_DB_RIGHT}'. Resetting to Apple defaults..."

    # The safest restore: write the built-in default rule back.
    # 'security authorizationdb reset system.login.console' is not a real
    # subcommand, so we remove Duo entries from the mechanisms array and
    # write the cleaned plist back.

    TEMP_PLIST="${BACKUP_DIR}/auth_db_clean.plist"
    security authorizationdb read "${AUTH_DB_RIGHT}" > "${TEMP_PLIST}" 2>/dev/null

    # Build a list of mechanism indices that reference Duo, then delete
    # them in reverse order so that index positions remain stable.
    DUO_INDICES=()
    mech_count=$(/usr/libexec/PlistBuddy -c "Print :mechanisms" "${TEMP_PLIST}" 2>/dev/null | grep -c '^ ' || true)
    for (( idx=0; idx<mech_count; idx++ )); do
        entry=$(/usr/libexec/PlistBuddy -c "Print :mechanisms:${idx}" "${TEMP_PLIST}" 2>/dev/null || true)
        if [[ "${entry}" == *DuoSecurityMacLogon* ]] || [[ "${entry}" == *duo* ]]; then
            DUO_INDICES+=("${idx}")
        fi
    done

    # Delete in reverse order
    for (( i=${#DUO_INDICES[@]}-1; i>=0; i-- )); do
        didx="${DUO_INDICES[$i]}"
        /usr/libexec/PlistBuddy -c "Delete :mechanisms:${didx}" "${TEMP_PLIST}"
        log "  Removed mechanism at index ${didx}"
    done

    # Write the cleaned plist back into the authorization database
    if security authorizationdb write "${AUTH_DB_RIGHT}" < "${TEMP_PLIST}" 2>/dev/null; then
        log "Authorization database restored (Duo mechanisms removed)."
    else
        warn "Failed to write cleaned authorization DB. You may need to reset manually."
        warn "  Backup plist saved at: ${BACKUP_DIR}/auth_db_${AUTH_DB_RIGHT}.plist"
    fi
else
    log "No Duo mechanisms found in '${AUTH_DB_RIGHT}'. Skipping."
fi

# =============================================
# 2. Authorization plugin bundle
# =============================================
log ""
log "--- Step 2: Plugin bundle ---"

FOUND_PLUGIN=false
for PLUGIN_BUNDLE in "${PLUGIN_BUNDLES[@]}"; do
    if [[ -d "${PLUGIN_DIR}/${PLUGIN_BUNDLE}" ]]; then
        cp -R "${PLUGIN_DIR}/${PLUGIN_BUNDLE}" "${BACKUP_DIR}/"
        log "Backed up plugin bundle to ${BACKUP_DIR}/${PLUGIN_BUNDLE}"

        rm -rf "${PLUGIN_DIR}/${PLUGIN_BUNDLE}"
        log "Removed ${PLUGIN_DIR}/${PLUGIN_BUNDLE}"
        FOUND_PLUGIN=true
    fi
done

if [[ "${FOUND_PLUGIN}" == false ]]; then
    log "No known Duo plugin bundles found. Checking for others..."
    shopt -s nullglob
    for bundle in "${PLUGIN_DIR}"/*uo* "${PLUGIN_DIR}"/*acLogon*; do
        warn "Found possible Duo bundle: ${bundle}"
    done
    shopt -u nullglob
fi

# =============================================
# 3. Duo configuration plist
# =============================================
log ""
log "--- Step 3: Configuration plist ---"

if [[ -f "${DUO_PLIST}" ]]; then
    cp "${DUO_PLIST}" "${BACKUP_DIR}/"
    log "Backed up ${DUO_PLIST}"

    rm -f "${DUO_PLIST}"
    log "Removed ${DUO_PLIST}"
else
    log "Configuration plist not found. Skipping."
fi

# =============================================
# 4. Remove offline-access data (per-user)
# =============================================
log ""
log "--- Step 4: Offline access & per-user data ---"

# Offline access keys are stored under each user's root-owned Duo directory
# and in the system keychain.  Clean both locations.
OFFLINE_PATHS=(
    "/private/var/root/Library/Application Support/Duo Security"
    "/private/var/root/Library/Application Support/com.duosecurity.maclogon"
    "/Library/Application Support/Duo Security"
    "/Library/Application Support/com.duosecurity.maclogon"
)

for opath in "${OFFLINE_PATHS[@]}"; do
    if [[ -d "${opath}" ]]; then
        cp -R "${opath}" "${BACKUP_DIR}/" 2>/dev/null || true
        rm -rf "${opath}"
        log "Removed ${opath}"
    fi
done

# Per-user caches / preferences
for user_home in /Users/*; do
    [[ -d "${user_home}" ]] || continue
    username="$(basename "${user_home}")"
    [[ "${username}" == "Shared" ]] && continue

    for sub in \
        "Library/Preferences/com.duosecurity.maclogon.plist" \
        "Library/Caches/com.duosecurity.maclogon" \
        "Library/Application Support/Duo Security" \
        "Library/Application Support/com.duosecurity.maclogon"; do
        target="${user_home}/${sub}"
        if [[ -e "${target}" ]]; then
            rm -rf "${target}"
            log "Removed ${target} (user: ${username})"
        fi
    done
done

# =============================================
# 5. System Keychain
# =============================================
log ""
log "--- Step 5: Keychain cleanup ---"

if security find-generic-password -l "Duo Security" /Library/Keychains/System.keychain &>/dev/null; then
    security delete-generic-password -l "Duo Security" /Library/Keychains/System.keychain &>/dev/null && \
        log "Removed 'Duo Security' entry from System keychain." || \
        warn "Could not remove keychain entry. You may need to clean it manually via Keychain Access. Refer to macOS Docs for Keychain Access"
else
    log "No Duo keychain entries found. Skipping."
fi

# =============================================
# 6. Clean up!
# =============================================
log ""
log "--- Step 6: Installer receipts ---"

shopt -s nullglob
for receipt in /var/db/receipts/com.duosecurity.maclogon.*; do
    rm -f "${receipt}"
    log "Removed receipt: ${receipt}"
done
for receipt in /var/db/receipts/com.duo.maclogon.*; do
    rm -f "${receipt}"
    log "Removed receipt: ${receipt}"
done
shopt -u nullglob

# =============================================
# GG
# =============================================
log ""
log "========================================"
log "Duo MacLogon uninstall complete."
log "Backups saved to: ${BACKUP_DIR}"
log "Don't forget to delete the user in the DUO Admin portal!!!!"
log "A REBOOT is recommended to ensure the"
log "login window loads without the Duo plugin."
log "========================================"

exit 0
