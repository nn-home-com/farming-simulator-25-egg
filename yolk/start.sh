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
DATA_DIR="/home/container/data"             # friendly top-level alias for game data

export GAME_DIR DOCS_DIR DEDI_DIR INSTALLER_DIR DLC_DIR DATA_DIR FS25_LIB FS25_CONFIG

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

# ---- 2b. Expose game data at a friendly top-level path ------------------------
# Savegames, mods, logs and config otherwise live deep inside the hidden Wine
# prefix ("...Documents/My Games/FarmingSimulator2025"), which the panel file
# manager hides. Point that location at /home/container/data via a symlink so the
# real, easy-to-find directory sits at the server root. Only done on a clean
# install: if a real directory already exists there (older servers), leave it
# untouched so existing data keeps working.
MYGAMES="${WINEPREFIX}/drive_c/users/container/Documents/My Games"
mkdir -p "$MYGAMES"
if [ ! -e "${MYGAMES}/FarmingSimulator2025" ]; then
    mkdir -p "$DATA_DIR"
    ln -s "$DATA_DIR" "${MYGAMES}/FarmingSimulator2025"
    log "Game data exposed at ${DATA_DIR} (savegames, mods, logs, config)."
elif [ -L "${MYGAMES}/FarmingSimulator2025" ]; then
    log "Game data available at ${DATA_DIR}."
else
    warn "Existing game data found in the Wine prefix; not relinking to ${DATA_DIR}."
fi

# ---- 3. Install game on first run ---------------------------------------------
if [ ! -f "${GAME_DIR}/dedicatedServer.exe" ]; then
    log "FS25 not installed yet — running installer..."
    # If no installer was uploaded, fetch it from the official GIANTS portal using
    # the operator's own serial (license-gated; see lib/download-game.sh).
    bash "${FS25_LIB}/download-game.sh" || {
        err "Automatic download failed. Upload the installer into ${INSTALLER_DIR}/"
        err "manually, or fix GAME_SERIAL, then restart."
        exit 1
    }
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

# The dedicated server binds its web portal to the container network IP, not
# loopback, so detect it and share it with the helper that drives the portal.
WEB_HOST=$(ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
[ -z "$WEB_HOST" ] && WEB_HOST=$(hostname -i 2>/dev/null | awk '{print $1}')
[ -z "$WEB_HOST" ] && WEB_HOST=127.0.0.1
export WEB_HOST
log "Web portal host detected as ${WEB_HOST}."

# ---- 5. Start the dedicated server (web portal) -------------------------------
WINE_LOG="${DEDI_DIR}/dedicatedServer.log"
mkdir -p "$DEDI_DIR/logs"
: > "$WINE_LOG"

log "Launching dedicatedServer.exe..."
# Run inside a Wine virtual desktop. The dedicated server spawns the game as a
# child process, and without a desktop that child cannot create its window
# ("no driver could be loaded") and dies before it ever reaches gameplay. The
# virtual desktop gives both processes a working window driver on the Xvfb display.
wine explorer /desktop=fs25,1280x720 "${GAME_DIR}/dedicatedServer.exe" >>"$WINE_LOG" 2>&1 &
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
log "Waiting for web portal on ${WEB_HOST}:${WEB_PORT}..."
for i in $(seq 1 60); do
    if nc -z "$WEB_HOST" "$WEB_PORT" 2>/dev/null; then
        log "Web portal is up."
        break
    fi
    sleep 2
done

if nc -z "$WEB_HOST" "$WEB_PORT" 2>/dev/null; then
    log "Requesting game session start via web portal..."
    node "${FS25_LIB}/start-game.mjs" || warn "Could not auto-start the session; start it manually via the web portal on port ${WEB_PORT}."
else
    warn "Web portal never came up. Inspect ${WINE_LOG}."
fi

# ---- 7. Stream the server log to the panel console ----------------------------
# The rich log is the timestamped session log under dedicated_server/logs/.
log "Server running. Streaming log (web portal: http://${WEB_HOST}:${WEB_PORT})."
SERVER_LOG=$(ls -t "${DEDI_DIR}/logs/"server_*.log 2>/dev/null | head -1)
[ -z "$SERVER_LOG" ] && SERVER_LOG="$WINE_LOG"
tail -n +1 -F "$SERVER_LOG" "$WINE_LOG" 2>/dev/null &
TAIL_PID=$!

# Keep PID1 alive while the Wine process runs; react to signals via the trap.
wait "$WINE_PID"
shutdown
