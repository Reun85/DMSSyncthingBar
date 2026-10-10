#!/usr/bin/env bash
# Symlink the plugin into the DMS plugin directory for development, then make
# the running shell pick it up. Idempotent.
set -euo pipefail

PLUGIN_ID=dankSyncthing
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO_ROOT/$PLUGIN_ID"
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins"
DEST="$DEST_DIR/$PLUGIN_ID"

[ -f "$SRC/plugin.json" ] || { echo "no plugin.json in $SRC" >&2; exit 1; }
mkdir -p "$DEST_DIR"

if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
    # Never clobber a real directory — that could be a home-manager-managed or
    # hand-installed copy holding state.
    echo "refusing to replace $DEST: it exists and is not a symlink" >&2
    exit 1
fi

current=$(readlink "$DEST" 2>/dev/null || true)
if [ "$current" = "$SRC" ]; then
    echo "already linked: $DEST -> $SRC"
else
    ln -sfn "$SRC" "$DEST"
    echo "linked: $DEST -> $SRC"
fi

if ! command -v dms >/dev/null 2>&1; then
    echo "dms not on PATH; enable the plugin from Settings -> Plugins" >&2
    exit 0
fi

dms ipc call plugin-scan scan >/dev/null 2>&1 || true
sleep 1
dms ipc call plugins enable "$PLUGIN_ID" || true
dms ipc call plugins status "$PLUGIN_ID" || true
