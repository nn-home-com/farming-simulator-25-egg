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
        # Note: logs go to stderr so they don't pollute the path on stdout that
        # the caller captures via installer="$(find_installer)".
        log "Extracting ${img##*/}..." >&2
        7z x "$img" -o"${INSTALLER_DIR}" -y -bso0 -bsp0 >&2 || return 1
        # The image is fully extracted now; drop it to reclaim ~21 GB (and lower
        # peak disk during install). Re-download happens automatically if needed.
        case "${KEEP_INSTALLER:-false}" in 1|true|yes|on) : ;; *) rm -f "$img" >&2 || true ;; esac
        [ -f "${INSTALLER_DIR}/FarmingSimulator2025.exe" ] && { echo "${INSTALLER_DIR}/FarmingSimulator2025.exe"; return 0; }
        [ -f "${INSTALLER_DIR}/Setup.exe" ] && { echo "${INSTALLER_DIR}/Setup.exe"; return 0; }
    fi
    return 1
}

# Remove installer artifacts once the game is installed. The *_ESD.img plus the
# extracted Setup-*.bin files are ~40+ GB and serve no purpose post-install.
cleanup_installer() {
    case "${KEEP_INSTALLER:-false}" in
        1|true|yes|on) log "KEEP_INSTALLER set — keeping installer files."; return 0 ;;
    esac
    log "Cleaning up installer files to reclaim disk space..."
    rm -f "${INSTALLER_DIR}"/*.img \
          "${INSTALLER_DIR}"/*.zip \
          "${INSTALLER_DIR}"/Setup-*.bin \
          "${INSTALLER_DIR}"/Setup.exe \
          "${INSTALLER_DIR}"/autorun.inf \
          "${INSTALLER_DIR}"/FarmingSimulator2025.exe 2>/dev/null || true
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
# GIANTS DLC installers are GUI-only — they ignore /SILENT and require an online
# product-key activation, so there is no way to unpack them headlessly (the
# payload inside the NSIS installer is only a <dlcStub> XML; the real .dlc is
# produced by the activation). We therefore drive the dialogs with xdotool.
#
# The flow, verified against the real installer on FS25 1.20 in a 1280x720 Xvfb:
#
#   1. Window "FarmingSimulator2025": "Please enter your <product> Product Key"
#      -> type the serial into the auto-focused field, click "Activate >"
#   2. The product window opens and installs
#   3. A small "Installation successful." message box appears -> OK, then the
#      installer exits by itself
#
# Step 3 is the awkward one: that box carries no window title of its own and
# shows up at an unpredictable moment, so there is nothing reliable to wait for.
# We therefore just click the OK position periodically — a click there while the
# wizard is still working does nothing — and treat the installer exiting as the
# clean finish.
#
# As a bounded fallback we stop once the new .dlc has not changed size for
# DLC_STABLE_WAIT seconds. Killing the installer at that point is safe and not a
# guess: the resulting file was verified byte-identical (SHA256) to one produced
# by a fully hand-clicked run. The new .dlc is identified by diffing the pdlc
# directory rather than guessing its name from the installer's filename.
DLC_TIMEOUT="${DLC_TIMEOUT:-900}"          # absolute ceiling per DLC (seconds)
DLC_STABLE_WAIT="${DLC_STABLE_WAIT:-30}"   # .dlc unchanged this long = finished

pdlc_snapshot() { ls "${DOCS_DIR}/pdlc" 2>/dev/null | sort; }
pdlc_bytes()    { du -sb "${DOCS_DIR}/pdlc" 2>/dev/null | cut -f1; }

install_one_dlc() {
    local dlc="$1" name="$2"
    local serial_clean=""
    [ -n "${GAME_SERIAL:-}" ] && serial_clean=$(printf '%s' "${GAME_SERIAL}" | tr -d '[:space:]-')

    mkdir -p "${DOCS_DIR}/pdlc"
    local before; before="$(pdlc_snapshot)"

    wine "$dlc" >"/tmp/fs25-dlc-${name}.log" 2>&1 &
    local pid=$!

    local stage=key start elapsed=0 stable=0 since_click=0 last_bytes exited=0
    start=$(date +%s)
    last_bytes="$(pdlc_bytes)"

    while :; do
        sleep 3
        elapsed=$(( $(date +%s) - start ))

        # Cleanest possible finish: the installer ended on its own.
        if ! kill -0 "$pid" 2>/dev/null; then
            exited=1
            log "  ${name}: installer finished on its own after ${elapsed}s."
            break
        fi

        if [ "$elapsed" -ge "$DLC_TIMEOUT" ]; then
            warn "  ${name}: timeout after ${elapsed}s — aborting this DLC."
            break
        fi

        # Fill in the product-key dialog if it shows up. It only appears the
        # FIRST time a given DLC is activated on this machine; on a re-install
        # the installer goes straight to installing. So this must never gate the
        # rest of the loop — an earlier version did, and then sat there until the
        # timeout on every re-install.
        #
        # Match "FarmingSimulator2025" (no spaces): that is the key dialog. The
        # install wizard is titled "Farming Simulator 25 - <product>" and must
        # not be mistaken for it.
        if [ "$stage" = key ]; then
            if [ -n "$serial_clean" ] && [ "$elapsed" -ge 12 ] \
               && xdotool search --onlyvisible --name "FarmingSimulator2025" >/dev/null 2>&1; then
                xdotool mousemove 747 361 click 1; sleep 0.5
                xdotool key --clearmodifiers ctrl+a; xdotool key --clearmodifiers Delete; sleep 0.5
                xdotool type --clearmodifiers --delay 40 "${serial_clean}"; sleep 2
                xdotool mousemove 884 536 click 1        # "Activate >"
                log "  ${name}: product key entered."
                stage=confirm
            elif [ "$elapsed" -ge 30 ]; then
                stage=confirm       # no key dialog — already activated before
            fi
        fi

        # Keep tapping OK. The success box has no window title to wait for, and
        # clicking that spot while the wizard is still busy is a no-op.
        if [ "$stage" = confirm ]; then
            since_click=$((since_click + 3))
            if [ "$since_click" -ge 6 ]; then
                xdotool mousemove 641 382 click 1 >/dev/null 2>&1 || true
                since_click=0
            fi
        fi

        # Bounded fallback: the payload has stopped changing.
        local now_bytes; now_bytes="$(pdlc_bytes)"
        if [ "$now_bytes" != "$last_bytes" ]; then
            stable=0; last_bytes="$now_bytes"
        else
            stable=$((stable + 3))
        fi
        if [ "$stable" -ge "$DLC_STABLE_WAIT" ] \
           && [ -n "$(comm -13 <(printf '%s\n' "$before") <(pdlc_snapshot) | grep -v '^$')" ]; then
            log "  ${name}: payload unchanged for ${stable}s — finishing up."
            break
        fi
    done

    # Only force it down if it did not end on its own; never leave it running.
    if [ "$exited" -eq 0 ] && kill -0 "$pid" 2>/dev/null; then
        xdotool mousemove 641 382 click 1 >/dev/null 2>&1 || true   # one last OK
        sleep 5
        kill "$pid" >/dev/null 2>&1 || true
        sleep 2
        kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    sleep 2

    # What actually landed in pdlc/ decides — no filename guessing.
    local added
    added="$(comm -13 <(printf '%s\n' "$before") <(pdlc_snapshot) | grep -v '^$' || true)"
    if [ -n "$added" ]; then
        log "  ${name} installed ($(printf '%s' "$added" | tr '\n' ' ')) after ${elapsed}s."
        return 0
    fi

    warn "  ${name} did not register (continuing without it). Check"
    warn "  /tmp/fs25-dlc-${name}.log; the installer needs a valid product key."
    return 1
}

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
        install_one_dlc "$dlc" "$name" && installed=$((installed+1))
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
    cleanup_installer
fi

install_dlcs
log "Install step complete."
