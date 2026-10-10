#!/bin/sh
# st-poll.sh — collect Syncthing REST state as a single JSON envelope on stdout.
#
# Depends on `sh`, `curl` and `jq`. (An earlier jq-free version concatenated raw
# endpoint responses, but Syncthing pretty-prints its JSON, so extracting folder
# IDs without a real parser was not robust.)
#
# Always exits 0 for *expected* conditions — no API key, instance down, bad key,
# HTTP error — and reports them as {"ok":false,"reason":...}. A non-zero exit
# means the script itself is broken, which the caller treats differently.
#
# Usage:
#   st-poll.sh [--mode summary|full] [--base URL] [--key KEY]
#              [--config PATH] [--peer DEVICE_ID] [--timeout SECONDS]
#   st-poll.sh --post /rest/db/scan [same connection flags]
#
# --post issues a POST to one endpoint and prints {"ok":true,"code":"200"}. It
# exists so that write actions reuse exactly the same base-URL and API-key
# resolution as the polls; nothing else needs to know how to authenticate.

set -u

MODE=summary
BASE=
KEY=
CONFIG=
PEER=
TIMEOUT=5
POST=

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)    MODE=${2:-summary}; shift 2 ;;
        --base)    BASE=${2:-}; shift 2 ;;
        --key)     KEY=${2:-}; shift 2 ;;
        --config)  CONFIG=${2:-}; shift 2 ;;
        --peer)    PEER=${2:-}; shift 2 ;;
        --timeout) TIMEOUT=${2:-5}; shift 2 ;;
        --post)    POST=${2:-}; shift 2 ;;
        *)         shift ;;
    esac
done

case "$MODE" in summary|full) ;; *) MODE=summary ;; esac

fail() {
    jq -cn --arg reason "$1" --arg detail "${2:-}" \
        '{ok:false, reason:$reason, detail:$detail}'
    exit 0
}

command -v curl >/dev/null 2>&1 || { printf '{"ok":false,"reason":"no-curl"}\n'; exit 0; }
command -v jq   >/dev/null 2>&1 || { printf '{"ok":false,"reason":"no-jq"}\n';   exit 0; }

# --- Resolve config path ----------------------------------------------------
[ -n "$CONFIG" ] || CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/syncthing/config.xml"

# --- Read a field from inside the <gui> element ------------------------------
# Scoped to <gui>…</gui> on purpose: <address> also appears in every <device>
# block (usually "dynamic"), and those come first in the document.
gui_field() {
    [ -r "$CONFIG" ] || return 1
    sed -n '/<gui[ >]/,/<\/gui>/p' "$CONFIG" \
        | sed -n "s|.*<$1>\\([^<]*\\)</$1>.*|\\1|p" \
        | head -n 1
}

# --- Resolve API key --------------------------------------------------------
if [ -z "$KEY" ]; then
    [ -r "$CONFIG" ] || fail "no-config" "cannot read $CONFIG"
    KEY=$(gui_field apikey)
    [ -n "$KEY" ] || fail "no-apikey" "no <apikey> found in $CONFIG"
fi

# --- Resolve base URL -------------------------------------------------------
if [ -z "$BASE" ]; then
    ADDR=$(gui_field address) || ADDR=
    [ -n "$ADDR" ] || ADDR=127.0.0.1:8384
    # A wildcard bind address is not usable as a client address.
    case "$ADDR" in
        0.0.0.0:*)   ADDR="127.0.0.1:${ADDR##*:}" ;;
        '[::]':*)    ADDR="127.0.0.1:${ADDR##*:}" ;;
        :[0-9]*)     ADDR="127.0.0.1$ADDR" ;;
    esac
    case "$ADDR" in
        http://*|https://*) BASE=$ADDR ;;
        *)                  BASE="http://$ADDR" ;;
    esac
fi
BASE=${BASE%/}

# --- HTTP helper ------------------------------------------------------------
# `fetch` must be called directly (never inside command substitution): it
# reports the status code through FETCH_CODE, and a subshell would discard that.
# curl's -w output lands after the body, so the code is always the last line.
FETCH_CODE=000
FETCH_BODY=
fetch() {
    FETCH_CODE=000
    FETCH_BODY=
    _raw=$(curl -sS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
        -H "X-API-Key: $KEY" -w '\n%{http_code}' "$BASE$1" 2>/dev/null) || return 0
    FETCH_CODE=$(printf '%s\n' "$_raw" | tail -n 1)
    FETCH_BODY=$(printf '%s\n' "$_raw" | sed '$d')
}

# Fetch and echo the body, falling back to JSON null so the envelope stays
# valid. Safe to use in command substitution — it needs no status code.
get_or_null() {
    fetch "$1"
    if [ "$FETCH_CODE" = "200" ] && [ -n "$FETCH_BODY" ]; then
        printf '%s' "$FETCH_BODY"
    else
        printf 'null'
    fi
}

# --- Reachability + auth probe ----------------------------------------------
# Doubles as a real data fetch: /rest/system/connections is needed in both modes
# and requires the API key, so one call distinguishes "instance down" from "key
# rejected" without spending an extra request on /rest/system/version.
fetch /rest/system/connections
if [ "$FETCH_CODE" != "200" ] || [ -z "$FETCH_BODY" ]; then
    case "$FETCH_CODE" in
        401|403) fail "bad-apikey"  "$BASE rejected the API key (HTTP $FETCH_CODE)" ;;
        000)     fail "unreachable" "no response from $BASE" ;;
        *)       fail "http-error"  "$BASE returned HTTP $FETCH_CODE" ;;
    esac
fi
CONNECTIONS=$FETCH_BODY

# --- Write action -----------------------------------------------------------
if [ -n "$POST" ]; then
    case "$POST" in
        /rest/*) ;;
        *) fail "bad-post" "refusing to POST to $POST" ;;
    esac
    _raw=$(curl -sS -X POST --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
        -H "X-API-Key: $KEY" -w '\n%{http_code}' "$BASE$POST" 2>/dev/null) || \
        fail "post-failed" "no response from $BASE$POST"
    _code=$(printf '%s\n' "$_raw" | tail -n 1)
    case "$_code" in
        2*) jq -cn --arg code "$_code" --arg path "$POST" \
                '{ok:true, action:$path, code:$code}'; exit 0 ;;
        *)  fail "post-failed" "$BASE$POST returned HTTP $_code" ;;
    esac
fi

# --- Summary tier -----------------------------------------------------------
SYSERROR=$(get_or_null /rest/system/error)
COMPLETION=$(get_or_null /rest/db/completion)

if [ "$MODE" = "summary" ]; then
    # No version here: it never changes between polls, so the full tier carries
    # it and Status.derive keeps the last known value.
    jq -cn \
        --arg base "$BASE" \
        --argjson connections "$CONNECTIONS" \
        --argjson systemError "$SYSERROR" \
        --argjson completion "$COMPLETION" \
        '{ok:true, instance:"local", mode:"summary", base:$base,
          connections:$connections, systemError:$systemError,
          completion:$completion}'
    exit 0
fi

# --- Full tier --------------------------------------------------------------
# One /rest/config call carries folders, devices and gui together.
VERSION=$(get_or_null /rest/system/version)
CONFIGJSON=$(get_or_null /rest/config)
DEVSTATS=$(get_or_null /rest/stats/device)

# Per-folder sync state. /rest/db/status already carries needBytes, so no
# per-folder completion call is needed.
FOLDERS=$(
    printf '%s' "$CONFIGJSON" | jq -c '(.folders // [])[] | {id, label, paused, type}' 2>/dev/null \
    | while IFS= read -r meta; do
        fid=$(printf '%s' "$meta" | jq -r '.id')
        enc=$(printf '%s' "$fid" | jq -rR '@uri')
        fstatus=$(get_or_null "/rest/db/status?folder=$enc")
        printf '%s' "$meta" | jq -c --argjson status "$fstatus" '. + {status:$status}'
    done | jq -cs '.'
)
[ -n "$FOLDERS" ] || FOLDERS='[]'

# /rest/system/status is the only endpoint carrying myID; /rest/system/version
# does not. Without it, this machine's own device is listed as a peer, which
# then reads as "1/2 devices connected" and never goes green.
SYSSTATUS=$(get_or_null /rest/system/status)
SELF_ID=$(printf '%s' "$SYSSTATUS" | jq -r '.myID // empty' 2>/dev/null)

# Per-device lag, aggregated across folders by Syncthing itself — one request
# per remote device rather than one per folder-device pair.
if [ -n "$PEER" ]; then
    PEER_IDS=$PEER
else
    PEER_IDS=$(printf '%s' "$CONFIGJSON" \
        | jq -r --arg self "$SELF_ID" '(.devices // [])[] | select(.deviceID != $self) | .deviceID' 2>/dev/null)
fi

DEVICES=$(
    for did in $PEER_IDS; do
        enc=$(printf '%s' "$did" | jq -rR '@uri')
        dcomp=$(get_or_null "/rest/db/completion?device=$enc")
        jq -cn --arg id "$did" --argjson completion "$dcomp" \
            '{deviceID:$id, completion:$completion}'
    done | jq -cs '.'
)
[ -n "$DEVICES" ] || DEVICES='[]'

jq -cn \
    --arg base "$BASE" \
    --arg selfId "$SELF_ID" \
    --argjson version "$VERSION" \
    --argjson connections "$CONNECTIONS" \
    --argjson systemError "$SYSERROR" \
    --argjson completion "$COMPLETION" \
    --argjson config "$CONFIGJSON" \
    --argjson deviceStats "$DEVSTATS" \
    --argjson systemStatus "$SYSSTATUS" \
    --argjson folders "$FOLDERS" \
    --argjson devices "$DEVICES" \
    '{ok:true, instance:"local", mode:"full", base:$base, selfId:$selfId,
      version:$version, connections:$connections, systemError:$systemError,
      completion:$completion, deviceStats:$deviceStats,
      systemStatus:$systemStatus,
      folders:$folders, devices:$devices,
      configDevices:($config.devices // [])}'
