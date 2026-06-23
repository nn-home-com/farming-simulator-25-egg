#!/bin/bash
# Silent installation of FS25 + DLCs under Wine, plus the one-time CD-key step.
#
# Expects (exported by start.sh): WINEPREFIX, GAME_DIR, DOCS_DIR, INSTALLER_DIR,
# DLC_DIR, FS25_CONFIG. With --dlc-only it skips the base game install and only
# processes newly uploaded DLCs.
#
# POLICY: This script runs the unmodified GIANTS installer and its online
# activation. It must NEVER patch binaries, block/redirect GIANTS activation
# servers, fake license files, or otherwise weaken copy protection. The serial
# is supplied by the operator and validated by GIANTS online — keep it that way.
set -uo pipefail

DLC_ONLY=0
[ "${1:-}" = "--dlc-only" ] && DLC_ONLY=1

DLC_PREFIX="FarmingSimulator25_"

log()  { echo -e "\e[36m[fs25/install]\e[0m $*"; }
warn() { echo -e "\e[33m[fs25/install] WARN:\e[0m $*"; }
err()  { echo -e "\e[31m[fs25/install] ERROR:\e[0m $*"; }

# ---- Locate / extract the base installer -------------------------------------
find_installer() {
    if [ -f "${INSTALLER_DIR}/FarmingSimulator2025.exe" ]; then
        echo "${INSTALLER_DIR}/FarmingSimulator2025.exe"; return 0
    fi
    if [ -f "${INSTALLER_DIR}/Setup.exe" ]; then
        echo "${INSTALLER_DIR}/Setup.exe"; return 0
    fi
    # Try to extract a distribution image (.img / .zip) once.
    local img
    img=$(ls "${INSTALLER_DIR}"/FarmingSimulator25_*_ESD.img \
             "${INSTALLER_DIR}"/FarmingSimulator25_*.zip 2>/dev/null | head -n1)
    if [ -n "$img" ]; then
        log "Extracting ${img##*/}..."
        7z x "$img" -o"${INSTALLER_DIR}" -y -bso0 -bsp0 || return 1
        [ -f "${INSTALLER_DIR}/FarmingSimulator2025.exe" ] && { echo "${INSTALLER_DIR}/FarmingSimulator2025.exe"; return 0; }
        [ -f "${INSTALLER_DIR}/Setup.exe" ] && { echo "${INSTALLER_DIR}/Setup.exe"; return 0; }
    fi
    return 1
}

# ---- One-time CD-key / activation --------------------------------------------
# The base installer is fully silent, but the very first launch of the game
# requires a CD-key to be entered, which generates the *.dat license files.
# There is no documented CLI for this, so we drive the dialog with xdotool.
# This is best-effort and may need tuning against the real dialog layout.
activate_license() {
    if ls "${DOCS_DIR}"/*.dat >/dev/null 2>&1; then
        log "License files already present, skipping activation."
        return 0
    fi
    if [ -z "${GAME_SERIAL:-}" ]; then
        err "No license (*.dat) files and GAME_SERIAL is empty."
        err "Set the GAME_SERIAL variable to your FS25 key, or perform a one-time"
        err "manual activation and upload the generated *.dat files into:"
        err "  ${DOCS_DIR}/"
        return 1
    fi

    log "Activating with provided CD-key via xdotool..."
    # The launcher shows the "Please enter your Farming Simulator 25 Product Key"
    # dialog; the input field is auto-focused. Coordinates below are for the fixed
    # 1280x720 Xvfb that start.sh creates. The field auto-formats into 5-char
    # groups and ignores typed dashes, so we strip them before typing.
    local serial_clean
    serial_clean=$(printf '%s' "${GAME_SERIAL}" | tr -d '[:space:]-')

    wine "${GAME_DIR}/FarmingSimulator2025.exe" >/tmp/fs25-activate.log 2>&1 &
    local game_pid=$!
    sleep 30  # give the activation dialog time to render

    # Focus + clear the field, type the key, click the "Activate >" button.
    xdotool mousemove 746 361 click 1; sleep 0.5
    xdotool key --clearmodifiers ctrl+a; xdotool key --clearmodifiers Delete; sleep 0.5
    xdotool type --clearmodifiers "${serial_clean}"; sleep 1.5
    xdotool mousemove 875 536 click 1   # "Activate >"

    # The .dat license files appear within a few seconds of a successful activation.
    local ok=0
    for _ in $(seq 1 12); do
        sleep 5
        if ls "${DOCS_DIR}"/*.dat >/dev/null 2>&1; then ok=1; break; fi
    done

    # After activation the launcher tries to start the 3D game and shows a GPU
    # warning ("Could not init 3D system" -> Yes/No). Dismiss it with "No", then stop.
    xdotool mousemove 675 435 click 1 2>/dev/null || true; sleep 2
    wineserver -k >/dev/null 2>&1 || true
    kill "$game_pid" >/dev/null 2>&1 || true
    sleep 3

    if [ "$ok" -eq 1 ]; then
        log "Activation succeeded — license files generated."
        return 0
    fi
    err "Activation did not produce license files. The CD-key automation may need"
    err "adjusting for this game version. See ACTIVATION.md for the manual path."
    return 1
}

# ---- DLC installation ---------------------------------------------------------
install_dlcs() {
    shopt -s nullglob
    local installed=0
    for dlc in "${DLC_DIR}/${DLC_PREFIX}"*.exe; do
        local base name
        base="$(basename "$dlc")"
        name="${base#${DLC_PREFIX}}"; name="${name%%_*}"
        if [ -f "${DOCS_DIR}/pdlc/${name}.dlc" ]; then
            continue  # already installed
        fi
        log "Installing DLC: ${name}"
        wine "$dlc" >/tmp/fs25-dlc-${name}.log 2>&1
        if [ -f "${DOCS_DIR}/pdlc/${name}.dlc" ]; then
            log "  ${name} installed."
            installed=$((installed+1))
        else
            warn "  ${name} installer ran but the DLC did not register."
        fi
    done
    [ "$installed" -gt 0 ] && log "Installed ${installed} new DLC(s)."
    return 0
}

# ---- Base game install --------------------------------------------------------
if [ "$DLC_ONLY" -eq 0 ]; then
    installer="$(find_installer)" || {
        err "No installer found in ${INSTALLER_DIR}/."
        err "Upload FarmingSimulator2025.exe (or the *_ESD.img / .zip) there and restart."
        exit 1
    }
    log "Running silent install: ${installer##*/}"
    wine "$installer" /SILENT /NOCANCEL /NOICONS /SUPPRESSMSGBOXES >/tmp/fs25-setup.log 2>&1 || {
        err "Silent install failed — see /tmp/fs25-setup.log"
        exit 1
    }
    [ -f "${GAME_DIR}/dedicatedServer.exe" ] || { err "dedicatedServer.exe missing after install."; exit 1; }
    log "Base game installed."

    activate_license || exit 1
fi

install_dlcs
log "Install step complete."
