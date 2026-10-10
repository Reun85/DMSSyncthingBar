#!/usr/bin/env bash
# Reload the plugin in the running DMS shell.
#
# Plugins are NOT covered by Quickshell's file watching, and the manifest is
# cached by mtime, so the right command depends on what changed:
#   *.qml / *.js            -> plugins reload
#   plugin.json             -> plugin-scan rescan (a reload will not re-read it)
#   files added/removed     -> plugin-scan scan
#   SyncthingService.qml    -> full shell restart (see below)
#
# The singleton is the exception. QML registers a `pragma Singleton` once per
# engine, and a plugin reload neither re-registers nor re-instantiates it, so
# after editing SyncthingService.qml the old object is still live — surfaces that
# expect a renamed or added property then silently get `undefined`. Only
# restarting the shell picks it up.
#
# This script picks for you based on git status, and can be forced.
set -euo pipefail

PLUGIN_ID=dankSyncthing
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:-auto}

command -v dms >/dev/null 2>&1 || { echo "dms not on PATH" >&2; exit 1; }

if [ "$MODE" = auto ]; then
    changed=$(git -C "$REPO_ROOT" status --porcelain -- "$PLUGIN_ID" 2>/dev/null || true)
    if grep -q 'SyncthingService.qml' <<<"$changed"; then
        MODE=restart
    elif grep -q 'plugin.json' <<<"$changed"; then
        MODE=rescan
    elif grep -qE '^\?\?|^ ?D' <<<"$changed"; then
        MODE=scan
    else
        MODE=reload
    fi
    echo "auto-selected: $MODE"
fi

case "$MODE" in
    reload) dms ipc call plugins reload "$PLUGIN_ID" ;;
    rescan) dms ipc call plugin-scan rescan "$PLUGIN_ID"; sleep 1
            dms ipc call plugins reload "$PLUGIN_ID" ;;
    scan)   dms ipc call plugin-scan scan; sleep 1
            dms ipc call plugins reload "$PLUGIN_ID" ;;
    restart)
            echo "SyncthingService.qml changed: restarting the shell so the singleton is re-registered"
            systemctl --user restart dms
            # Wait until the plugin actually appears in the registry. A bare
            # `plugins list` starts answering before PluginService has finished
            # scanning, and enabling at that point silently does nothing.
            ready=0
            for _ in $(seq 1 40); do
                if dms ipc call plugins list 2>/dev/null | grep -q "^$PLUGIN_ID "; then
                    ready=1
                    break
                fi
                sleep 1
            done
            [ "$ready" = 1 ] || { echo "$PLUGIN_ID did not appear in the registry" >&2; exit 1; }
            # The enabled flag cannot persist when home-manager manages
            # plugin_settings.json (read-only store symlink), so re-enable here.
            dms ipc call plugins enable "$PLUGIN_ID" || true
            sleep 2 ;;
    *)      echo "usage: reload.sh [auto|reload|rescan|scan|restart]" >&2; exit 1 ;;
esac

dms ipc call plugins status "$PLUGIN_ID" || true
