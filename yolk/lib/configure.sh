#!/bin/bash
# Render the two FS25 config XMLs from environment variables and place them where
# the dedicated server expects them. Runs on every boot so panel changes apply.
#
# Expects (exported by start.sh): GAME_DIR, DEDI_DIR, FS25_CONFIG, WEB_*.
set -uo pipefail

log() { echo -e "\e[36m[fs25/config]\e[0m $*"; }

mkdir -p "$DEDI_DIR"

# Defaults (egg variables override via the environment).
: "${SERVER_NAME:=FS25 Server}"
: "${ADMIN_PASSWORD:=}"
: "${GAME_PASSWORD:=}"
: "${SAVEGAME_INDEX:=1}"
: "${MAX_PLAYERS:=12}"
: "${SERVER_PORT:=10823}"
: "${SERVER_LANGUAGE:=en}"
: "${AUTO_SAVE_INTERVAL:=180.000000}"
: "${STATS_INTERVAL:=360.000000}"
: "${CROSSPLAY:=true}"
: "${PAUSE_IF_EMPTY:=2}"
: "${MAP_ID:=MapUS}"

render() {
    local tmpl="$1" out="$2"
    sed \
        -e "s|%%WEB_PORT%%|${WEB_PORT}|g" \
        -e "s|%%WEB_USERNAME%%|${WEB_USERNAME}|g" \
        -e "s|%%WEB_PASSWORD%%|${WEB_PASSWORD}|g" \
        -e "s|%%SERVER_NAME%%|${SERVER_NAME}|g" \
        -e "s|%%ADMIN_PASSWORD%%|${ADMIN_PASSWORD}|g" \
        -e "s|%%GAME_PASSWORD%%|${GAME_PASSWORD}|g" \
        -e "s|%%SAVEGAME_INDEX%%|${SAVEGAME_INDEX}|g" \
        -e "s|%%MAX_PLAYERS%%|${MAX_PLAYERS}|g" \
        -e "s|%%SERVER_PORT%%|${SERVER_PORT}|g" \
        -e "s|%%LANGUAGE%%|${SERVER_LANGUAGE}|g" \
        -e "s|%%AUTO_SAVE_INTERVAL%%|${AUTO_SAVE_INTERVAL}|g" \
        -e "s|%%STATS_INTERVAL%%|${STATS_INTERVAL}|g" \
        -e "s|%%CROSSPLAY%%|${CROSSPLAY}|g" \
        -e "s|%%PAUSE_IF_EMPTY%%|${PAUSE_IF_EMPTY}|g" \
        -e "s|%%MAP_ID%%|${MAP_ID}|g" \
        "$tmpl" > "$out"
}

render "${FS25_CONFIG}/dedicatedServer.xml.tmpl"       "${GAME_DIR}/dedicatedServer.xml"
render "${FS25_CONFIG}/dedicatedServerConfig.xml.tmpl" "${DEDI_DIR}/dedicatedServerConfig.xml"

log "Configuration written (server='${SERVER_NAME}', port=${SERVER_PORT}, map=${MAP_ID})."
