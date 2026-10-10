# dankSyncthing

A [DankMaterialShell](https://danklinux.com) plugin that answers *"is Syncthing OK?"*
at a glance, and when it isn't, shows what you need to fix it.

Three surfaces from one plugin:

| Surface | What it shows |
|---|---|
| **Bar pill** | A status icon (spinning while syncing), optionally a percentage or error count. Click for the detail popout. |
| **Control Center card** | The same verdict as a tile, with an expandable detail panel. |
| **Desktop widget** | An always-visible card on the wallpaper: status, folders, devices. |

The detail view leads with the problem: errors first (naming the folder and the
message), then device connectivity with last-seen times, then per-folder state,
then actions — *Rescan all*, *Restart*, and buttons to open the web UI.

## Status

| Icon | Meaning |
|---|---|
| `cloud_done` | Up to date |
| `sync` (spinning) | Syncing — a folder is busy, or a peer is behind |
| `cloud_off` | A configured peer is not connected |
| `sync_problem` | Errors — system errors, or folder pull/scan failures |
| `pause_circle` | Every folder is paused |
| `cloud_off` / `help` (grey) | Syncthing isn't running, or no API key was found |

Precedence runs highest-first: **error → disconnected → syncing → paused → up to
date.** Disconnected deliberately outranks syncing: if the peer is gone, that is
the actionable fact, not the pending bytes.

## What it monitors

Only the **local** Syncthing instance. That is not a limitation as much as it
sounds: your peers appear in the local API as devices, so "the server is
unreachable" and "the server is 4 GB behind" are both visible locally, via
`/rest/system/connections`, `/rest/db/completion?device=…` and
`/rest/stats/device`.

The blind spot is a fault that exists *only* on the far side — its disk full, a
folder paused only there, or a folder not shared with this machine. Those show up
indirectly, as the peer falling behind or dropping off. The optional remote
button is the escape hatch for when you need that instance's own view.

## Install

### Development

```bash
./scripts/dev-link.sh        # symlink into ~/.config/DankMaterialShell/plugins
./scripts/reload.sh          # picks reload / rescan / restart from git status
journalctl --user -u dms -f  # QML console output lands here
```

Then add the bar widget in *Settings → Appearance → DankBar Layout*, and place the
desktop widget in *Settings → Desktop Widgets*.

### home-manager

The DMS module maps `plugins.<name>.src` to
`xdg.configFile."DankMaterialShell/plugins/<name>".source`, so `src` must be the
directory that *contains* `plugin.json`:

```nix
{
  # flake inputs
  inputs.dms-syncthing = {
    url = "github:<you>/DMS";
    flake = false;
  };

  # programs.dank-material-shell.plugins
  # (on the stable flake / nixpkgs module this is programs.dankMaterialShell
  #  or programs.dms-shell — match whichever you already use)
  dankSyncthing = {
    enable = true;
    src = "${inputs.dms-syncthing}/dankSyncthing";

    # Optional, and machine-specific. Omit the whole `settings` block and the
    # plugin runs local-only with no remote UI anywhere.
    settings = {
      serverUrl = "http://docker:8384";
      serverLabel = "syncthing-server";
    };
  };
}
```

Requires `curl` and `jq` on `PATH`; the plugin's startup check blocks activation
with an explanatory toast if either is missing.

## Settings

Everything is configurable, with working defaults. The full table lives in
`dankSyncthing/Config.js` — that is the single source of truth, and the settings
page reads its defaults from it so the two cannot disagree.

| Setting | Default | Notes |
|---|---|---|
| `localUrl` | *auto* | Blank: read the GUI address from `config.xml`, else `http://127.0.0.1:8384` |
| `localApiKey` | *auto* | Blank: read `<apikey>` from `config.xml`, so a regenerated key is picked up |
| `localConfigPath` | *auto* | Blank: `$XDG_CONFIG_HOME/syncthing/config.xml` |
| `localLabel` | `This machine` | |
| `serverUrl` | **empty** | **Empty disables all remote UI.** No default on purpose — see below |
| `serverLabel` | `Server` | Used on the button and to mark which peer is the remote |
| `serverApiKey` | empty | Reserved; the remote is link-only today |
| `peerDeviceId` | *all* | Restrict tracking to one device ID |
| `pollActiveMs` | `2000` | Interval while syncing or in error |
| `pollIdleMs` | `10000` | Interval while idle; the full folder scan runs at 2× this |
| `requestTimeoutS` | `5` | |
| `showPercentInBar` | `true` | |
| `showLabelInBar` | `false` | |
| `hideWhenUpToDate` | `false` | Makes the pill a pure exception indicator |
| `desktopShowFolders` | `true` | |
| `desktopShowDevices` | `true` | |
| `desktopOpacity` | `50` | |
| `notifyOnError` | `true` | Toasts on the *transition* into error, not every poll |

### Why `serverUrl` has no default

So the same repo works unchanged on every machine. A hardcoded hostname would be
one person's setup baked into a plugin. Unset, nothing about a remote instance is
rendered — no button, no rows, no labels, and no gap where they would have been.

### If home-manager manages your plugin settings

`programs.*.managePluginSettings` turns on as soon as *any* plugin declares
`settings`, which makes `~/.config/DankMaterialShell/plugin_settings.json` a
read-only symlink into the Nix store. Two consequences:

- The in-shell settings page cannot persist anything. Set values through the
  `settings = { … }` attrset instead.
- The plugin's `enabled` flag cannot persist either, so after a shell restart it
  must be re-enabled (`dms ipc call plugins enable dankSyncthing`) unless
  home-manager declares `enable = true`.

Every default is chosen to be sane with no stored settings at all.

## IPC

```bash
dms ipc call dankSyncthing status       # "<kind>\t<label>\t<detail>", tab-separated
dms ipc call dankSyncthing refresh      # force a full poll
dms ipc call dankSyncthing rescan       # POST /rest/db/scan
dms ipc call dankSyncthing openWeb      # local web UI
dms ipc call dankSyncthing openServer   # remote web UI, if configured
```

`status` is machine-readable, so the state can drive a compositor binding or a
script without going through the UI.

## How it works

```
scripts/st-poll.sh          one JSON envelope per invocation (sh + curl + jq)
        ▲
SyncthingService.qml        pragma Singleton, registered in ./qmldir
                            owns the timers, parsing and all shared state
        ▲
SyncthingDaemon.qml         daemon surface: wakes the lazy singleton, hosts IPC
        │
        ├── SyncthingBarWidget.qml      bar pill + popout + Control Center card
        ├── SyncthingDesktopWidget.qml  wallpaper card
        └── SyncthingDetails.qml        the detail body, shared by popout and CC
                 │
        Config.js / Status.js           pure, dependency-free, unit-tested
```

Two decisions worth knowing:

**State lives in a singleton, not in the surfaces.** Every view surface is
instantiated once per bar *and per screen*, so polling from a surface would
multiply the work by the number of monitors. The singleton is one instance per
QML engine, and its properties are ordinary bindable properties, so one poll
updates every surface. Measured on a two-monitor setup, the idle rate is a single
summary poll every 10 s and one full poll every 20 s, regardless of how many
places the widget appears.

**Two polling tiers.** The summary tier is 3 requests (connections, system
errors, aggregate completion); the full tier adds the folder roster and one
`/rest/db/status` per folder, plus per-device completion aggregated by Syncthing
itself rather than per folder-device pair. `Status.derive` carries the last full
poll's folder and device detail forward, so summary ticks never blank the UI.

The poll script always exits 0 and reports expected failures — no API key, bad
key, instance down — as `{"ok":false,"reason":…}`, so a non-zero exit means the
script itself is broken, which is a different problem and shown differently.

### Known limitation: polling, not events

Short-lived states can be missed. A local scan of a few hundred megabytes can
start and finish inside the 10 s idle interval, so the pill may never leave
"up to date" for a change you just made. Syncthing's `/rest/events` long-poll
would make updates instant; that needs a persistent `Process` with reconnect and
`since` tracking, and is the natural next step.

## Development

`devenv.nix` provides the toolchain:

```bash
st-test     # Config.js / Status.js fixtures (node, 81 checks)
st-poll     # run the poll script against the live instance
st-fmt      # qmlformat -i
st-lint     # qmllint + shellcheck
st-link     # symlink into the DMS plugin dir
st-reload   # reload in the running shell
st-logs     # journalctl --user -u dms -f
```

`Status.js` and `Config.js` are deliberately free of QML imports so the fixtures
can run under node; `tests/run.mjs` strips the leading `.pragma library` line and
imports the rest as an ES module.

`qmllint` cannot resolve `qs.*` on its own, because DMS maps its shell root to a
`qs` module namespace through Quickshell's loader rather than real qmldir files.
`scripts/qml-import-tree.py` mirrors the DMS QML tree with symlinks and writes
the qmldir files qmllint needs; `st-lint` runs it first, so the lint is a real
type check rather than a syntax check.

That is worth the setup. It caught a `property var state` on the service
shadowing `QQuickItem.state`, and it catches cross-file member mismatches on the
singleton — the same class of failure the reload trap below produces at runtime.

Four warning categories are filtered, each for a documented reason (see
`devenv.nix`): `[unqualified]` is the idiom every bundled DMS plugin uses,
`[import]` covers transitive Quickshell modules the shadow tree does not mirror,
`[required]` is a qmllint limitation with `PluginSettings` re-parenting its
children — DMS's own `CompositeSettings.qml` trips it 18 times — and
`Type "color" of property …` is a gap in the generated qmldir that cannot be
closed with `depends` entries without breaking module resolution outright.

### Reload rules

| Changed | Needed |
|---|---|
| `*.qml`, `*.js` | `dms ipc call plugins reload dankSyncthing` |
| `plugin.json` | `dms ipc call plugin-scan rescan dankSyncthing` — manifests are mtime-cached |
| files added/removed | `dms ipc call plugin-scan scan` |
| `SyncthingService.qml` | **full shell restart** |

The last one is the trap: QML registers a `pragma Singleton` once per engine, and
a plugin reload neither re-registers nor re-instantiates it. After editing the
singleton the old object is still live, and surfaces expecting a renamed or added
property silently receive `undefined`. `scripts/reload.sh` detects this from
`git status` and restarts the shell for you.

## License

MIT — see [LICENSE](LICENSE).
