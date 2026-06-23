#!/bin/bash
# Main lifecycle for the headless FS25 dedicated server.
#
#   1. Bring up a virtual X display (Wine needs one even headless).
#   2. Initialise the Wine prefix on first run.
#   3. If the game is not installed yet, run the silent installer + DLCs and the
#      one-time CD-key activation (see lib/install-game.sh).
#   4. Render the two config XMLs from the environment variables.
#   5. Launch dedicatedServer.exe (the web control portal on $WEB_PORT).
#   6. Ask the web portal to start the actual game session.
#   7. Tail the server log to stdout so it shows up in the panel console.
#   8. On SIGINT/SIGTERM, shut the server down cleanly.
set -uo pipefail

FS25_LIB="/opt/fs25/lib"
FS25_CONFIG="/opt/fs25/config"

# ---- Paths (everything persistent lives under /home/container) ----------------
export WINEPREFIX="/home/container/.fs25prefix"
export WINEARCH="win64"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="mscoree=d;mshtml=d"
export DISPLAY=":0"

GAME_DIR="${WINEPREFIX}/drive_c/Program Files (x86)/Farming Simulator 2025"
DOCS_DIR="${WINEPREFIX}/drive_c/users/container/Documents/My Games/FarmingSimulator2025"
DEDI_DIR="${DOCS_DIR}/dedicated_server"
INSTALLER_DIR="/home/container/installer"   # user uploads the game installer here
DLC_DIR="/home/container/dlc"               # user uploads DLC installers here

export GAME_DIR DOCS_DIR DEDI_DIR INSTALLER_DIR DLC_DIR FS25_LIB FS25_CONFIG

# ---- Defaults for tunables (egg variables override these) ----------------------
export WEB_PORT="${WEB_PORT:-7999}"
export WEB_USERNAME="${WEB_USERNAME:-admin}"
export WEB_PASSWORD="${WEB_PASSWORD:-changeme}"

log()  { echo -e "\e[36m[fs25]\e[0m $*"; }
warn() { echo -e "\e[33m[fs25] WARN:\e[0m $*"; }
err()  { echo -e "\e[31m[fs25] ERROR:\e[0m $*"; }

mkdir -p "$INSTALLER_DIR" "$DLC_DIR"

# ---- Compliance notice --------------------------------------------------------
# This image ships NO game content and circumvents NO copy protection. It runs
# the unmodified GIANTS installer and online activation. Operating it requires a
# legitimately purchased FS25 dedicated-server license; the operator is solely
# responsible for license compliance. See COMPLIANCE.md.
compliance_notice() {
    echo "=============================================================="
    echo " Farming Simulator 25 dedicated server (Wine)"
    echo " You must run a LEGITIMATELY LICENSED copy. This image contains"
    echo " no game files and does not bypass any GIANTS license check."
    echo " The Steam version cannot host a dedicated server."
    echo "=============================================================="
}
compliance_notice

# ---- 1. Virtual display -------------------------------------------------------
log "Starting virtual display (Xvfb on ${DISPLAY})..."
Xvfb "$DISPLAY" -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 2

# ---- 2. Wine prefix -----------------------------------------------------------
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    log "Initialising Wine prefix at ${WINEPREFIX} (first run, this can take a minute)..."
    wineboot --init >/tmp/wineboot.log 2>&1
    wineserver -w
fi

# ---- 3. Install game on first run ---------------------------------------------
if [ ! -f "${GAME_DIR}/dedicatedServer.exe" ]; then
    log "FS25 not installed yet — running installer..."
    if ! bash "${FS25_LIB}/install-game.sh"; then
        err "Installation failed. Check the log above. The server cannot start."
        err "Make sure the installer is uploaded to: ${INSTALLER_DIR}/"
        exit 1
    fi
else
    log "FS25 already installed."
    # Pick up any newly uploaded DLCs without reinstalling the base game.
    bash "${FS25_LIB}/install-game.sh" --dlc-only || warn "DLC pass reported problems (continuing)."
fi

# ---- 4. Render configuration from environment ---------------------------------
bash "${FS25_LIB}/configure.sh"

# ---- 5. Start the dedicated server (web portal) -------------------------------
SERVER_LOG="${DEDI_DIR}/dedicatedServer.log"
mkdir -p "$DEDI_DIR"
: > "$SERVER_LOG"

log "Launching dedicatedServer.exe..."
wine "${GAME_DIR}/dedicatedServer.exe" >>"$SERVER_LOG" 2>&1 &
WINE_PID=$!

# ---- 8. Clean shutdown handler ------------------------------------------------
shutdown() {
    log "Shutdown requested — stopping FS25 server..."
    node "${FS25_LIB}/start-game.mjs" --stop >/dev/null 2>&1 || true
    sleep 3
    wineserver -k >/dev/null 2>&1 || true
    kill "$WINE_PID"  >/dev/null 2>&1 || true
    kill "$TAIL_PID"  >/dev/null 2>&1 || true
    kill "$XVFB_PID"  >/dev/null 2>&1 || true
    exit 0
}
trap shutdown SIGINT SIGTERM

# ---- 6. Wait for the web portal, then start the game session ------------------
log "Waiting for web portal on 127.0.0.1:${WEB_PORT}..."
for i in $(seq 1 60); do
    if nc -z 127.0.0.1 "$WEB_PORT" 2>/dev/null; then
        log "Web portal is up."
        break
    fi
    sleep 2
done

if nc -z 127.0.0.1 "$WEB_PORT" 2>/dev/null; then
    log "Requesting game session start via web portal..."
    node "${FS25_LIB}/start-game.mjs" || warn "Could not auto-start the session; start it manually via the web portal on port ${WEB_PORT}."
else
    warn "Web portal never came up. Inspect ${SERVER_LOG}."
fi

# ---- 7. Stream the server log to the panel console ----------------------------
log "Server running. Streaming log (web portal: http://<server-ip>:${WEB_PORT})."
tail -n +1 -F "$SERVER_LOG" &
TAIL_PID=$!

# Keep PID1 alive while the Wine process runs; react to signals via the trap.
wait "$WINE_PID"
shutdown
