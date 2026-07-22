#!/bin/bash
# Automatic, license-gated download of the FS25 installer (+ DLCs) from the
# OFFICIAL GIANTS download portal, using the operator's own serial.
#
# Expects (exported by start.sh): INSTALLER_DIR, DLC_DIR, GAME_SERIAL.
#
# How it works (it mirrors exactly what a human does in the browser):
#   1. POST the serial to https://eshop.giants-software.com/downloads.php
#      (form field `activationKey`). A VALID serial makes the portal return a
#      page containing official CDN download links; an invalid/empty serial
#      returns just the "Please enter your key" form (no links).
#   2. Scrape the official CDN link for the base game (*_ESD.img) and DLCs
#      (*.exe) out of that response.
#   3. Download them from the GIANTS CDN (resumable) with the required Referer.
#
# POLICY / COMPLIANCE: This downloads NOTHING without a valid serial. We never
# hardcode a CDN URL and never bypass the serial gate — the serial must be
# accepted by the GIANTS portal or we abort. We host/redistribute nothing; we
# only automate the operator fetching their OWN licensed copy from GIANTS'
# official servers. Keep it that way: do not add fallback URLs that skip the
# portal's serial check.
set -uo pipefail

# --dlc-only: skip the base game entirely and just fetch DLC installers. Used on
# every boot of an already-installed server so newly bought DLCs turn up without
# anyone having to upload an .exe by hand.
DLC_ONLY=0
[ "${1:-}" = "--dlc-only" ] && DLC_ONLY=1

PORTAL="https://eshop.giants-software.com/downloads.php"
# The CDN gates downloads on this Referer; it is also the legit portal page.
REFERER="$PORTAL"
UA="Mozilla/5.0 (fs25-egg)"

log()  { echo -e "\e[36m[fs25/download]\e[0m $*"; }
warn() { echo -e "\e[33m[fs25/download] WARN:\e[0m $*"; }
err()  { echo -e "\e[31m[fs25/download] ERROR:\e[0m $*"; }

# Honour an opt-out (default: enabled).
case "${AUTO_DOWNLOAD:-true}" in
    0|false|no|off) log "Auto-download disabled (AUTO_DOWNLOAD=${AUTO_DOWNLOAD}). Skipping."; exit 0 ;;
esac

# If the operator already uploaded an installer, respect it and don't download.
# (Irrelevant in --dlc-only mode: the base game is not the point there.)
if [ "$DLC_ONLY" -eq 0 ] \
   && ls "${INSTALLER_DIR}"/FarmingSimulator2025.exe \
         "${INSTALLER_DIR}"/Setup.exe \
         "${INSTALLER_DIR}"/FarmingSimulator25_*_ESD.img \
         "${INSTALLER_DIR}"/FarmingSimulator25_*.zip >/dev/null 2>&1; then
    log "An installer is already present in ${INSTALLER_DIR}/ — skipping download."
    exit 0
fi

if [ -z "${GAME_SERIAL:-}" ]; then
    warn "GAME_SERIAL is empty — cannot auto-download. Set your CD-key or upload"
    warn "the installer into ${INSTALLER_DIR}/ manually."
    exit 0
fi

# In --dlc-only mode this runs on every boot, so it must never be able to stop a
# server from starting: any problem below is a warning and a clean exit 0.
if [ "$DLC_ONLY" -eq 1 ]; then
    case "${DOWNLOAD_DLC:-true}" in
        0|false|no|off) log "DLC download disabled (DOWNLOAD_DLC=${DOWNLOAD_DLC})."; exit 0 ;;
    esac
fi

mkdir -p "$INSTALLER_DIR" "$DLC_DIR"

# ---- 1. Ask the portal for the download links --------------------------------
# Build the POST body in a private temp file so the serial never appears in the
# process list (`ps`) or in any log. Serials are URL-safe ([A-Z0-9-]).
PORTAL_HTML="$(mktemp)"
BODY="$(mktemp)"
chmod 600 "$BODY" "$PORTAL_HTML"
cleanup() { rm -f "$BODY" "$PORTAL_HTML"; }
trap cleanup EXIT

printf 'activationKey=%s&foobar=DOWNLOAD' "${GAME_SERIAL}" > "$BODY"

log "Requesting download links from the GIANTS portal..."
if ! curl -s -A "$UA" --data "@${BODY}" "$PORTAL" -o "$PORTAL_HTML"; then
    if [ "$DLC_ONLY" -eq 1 ]; then
        warn "Could not reach the GIANTS portal — skipping the DLC check this boot."
        exit 0
    fi
    err "Could not reach the GIANTS download portal (${PORTAL})."
    exit 1
fi
rm -f "$BODY"   # serial no longer needed; drop it early

# ---- 2. Scrape the official CDN links ----------------------------------------
# Base game: the Windows disc image (*_ESD.img). (*.dmg is the macOS build.)
IMG_URL=$(grep -ioE 'https://cdn[0-9]*\.giants-software\.com/[^"]+_ESD\.img' "$PORTAL_HTML" | head -n1)

if [ -z "$IMG_URL" ]; then
    if [ "$DLC_ONLY" -eq 1 ]; then
        # No links at all means the serial was not accepted. Not fatal here —
        # the game is already installed and running matters more.
        warn "The portal returned no links for your serial — skipping DLC check."
        exit 0
    fi
    err "The portal returned no download link for your serial."
    err "That usually means the CD-key is invalid/not a GIANTS server license,"
    err "or the portal layout changed. Check GAME_SERIAL, or upload the installer"
    err "manually into ${INSTALLER_DIR}/."
    exit 1
fi

# ---- helper: resumable download with progress --------------------------------
download() {
    local url="$1" dest="$2" label="$3"
    local total cur pct
    total=$(curl -sI -A "$UA" -e "$REFERER" "$url" \
            | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tail -n1)

    if [ -f "$dest" ] && [ -n "$total" ]; then
        local have; have=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        if [ "$have" = "$total" ]; then
            log "${label}: already fully downloaded (${total} bytes)."
            return 0
        fi
        log "${label}: resuming (${have}/${total} bytes already present)."
    fi

    log "${label}: downloading ${total:-?} bytes -> ${dest##*/}"
    # -C - resumes a partial file; -L follows redirects; --retry rides out drops.
    curl -L -A "$UA" -e "$REFERER" -C - --retry 5 --retry-delay 5 \
         -o "$dest" "$url" >/tmp/fs25-curl.log 2>&1 &
    local pid=$!

    # Print a clean one-line-per-tick progress to the panel console.
    while kill -0 "$pid" 2>/dev/null; do
        cur=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        if [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null; then
            pct=$(( cur * 100 / total ))
            log "${label}: ${pct}% (${cur}/${total} bytes)"
        else
            log "${label}: ${cur} bytes"
        fi
        sleep 20
    done
    wait "$pid"; local rc=$?

    if [ "$rc" -ne 0 ]; then
        err "${label}: download failed (curl rc=${rc}). See /tmp/fs25-curl.log"
        return 1
    fi
    if [ -n "$total" ]; then
        cur=$(stat -c%s "$dest" 2>/dev/null || echo 0)
        if [ "$cur" != "$total" ]; then
            err "${label}: size mismatch (${cur} != ${total}). Will retry on next boot."
            return 1
        fi
    fi
    log "${label}: done."
    return 0
}

# ---- 3. Download the base game -----------------------------------------------
if [ "$DLC_ONLY" -eq 0 ]; then
    IMG_DEST="${INSTALLER_DIR}/${IMG_URL##*/}"
    download "$IMG_URL" "$IMG_DEST" "Base game" || exit 1
fi

# ---- 4. Download DLCs (optional, on by default) ------------------------------
case "${DOWNLOAD_DLC:-true}" in
    0|false|no|off) log "DLC download disabled (DOWNLOAD_DLC=${DOWNLOAD_DLC})." ;;
    *)
        # Windows DLC installers are the *.exe links (skip *.dmg = macOS).
        mapfile -t DLC_URLS < <(grep -ioE 'https://cdn[0-9]*\.giants-software\.com/[^"]+\.exe' "$PORTAL_HTML" | sort -u)
        if [ "${#DLC_URLS[@]}" -gt 0 ]; then
            log "Found ${#DLC_URLS[@]} DLC download(s)."
            for url in "${DLC_URLS[@]}"; do
                dest="${DLC_DIR}/${url##*/}"
                download "$url" "$dest" "DLC ${url##*/}" || warn "DLC ${url##*/} failed (continuing)."
            done
        fi
        ;;
esac

log "Download step complete."
