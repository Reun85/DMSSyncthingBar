pragma Singleton

import QtQuick
import qs.Common
import qs.Services
import "Config.js" as Config
import "Status.js" as Status

// Single owner of all Syncthing state.
//
// Every *view* surface of this plugin (bar pill, Control Center card, desktop
// widget) is instantiated once per bar and per screen. Polling from a surface
// would therefore multiply the work by the number of monitors. A plugin-local
// singleton — registered in ./qmldir — is one instance per QML engine, and its
// properties are ordinary bindable QML properties, so every surface updates from
// one poll. This mirrors dockerManager's DockerService.
Item {
    id: root

    readonly property string pluginId: "dankSyncthing"

    // Resolved settings; see Config.js for the defaults table.
    property var cfg: Config.resolve({})

    // Derived view model; see Status.js. `kind` is the headline status.
    // Named syncState, not state: QQuickItem already defines a string `state`
    // property for QML state groups, and shadowing it with an object breaks.
    property var syncState: Status.derive(null)

    // Bumped on every successful poll so consumers can distinguish a refresh
    // from an unchanged re-evaluation.
    property int stamp: 0
    property bool busy: false

    // Absolute path to the bundled poll script, resolved relative to this file
    // so it works wherever the plugin is installed (symlink or Nix store).
    readonly property string scriptPath: {
        const url = Qt.resolvedUrl("scripts/st-poll.sh").toString().split("?")[0];
        return Paths.strip(url);
    }

    readonly property string localUrl: cfg.localUrl || syncState.base || "http://127.0.0.1:8384"
    readonly property string serverUrl: Config.serverUrl(cfg)
    readonly property bool hasServer: Config.hasServer(cfg)
    readonly property string serverHost: Config.serverHost(cfg)

    // --- settings ----------------------------------------------------------
    function loadSettings() {
        cfg = Config.resolve(SettingsData.getPluginSettingsForPlugin(pluginId));
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== root.pluginId)
                return;
            root.loadSettings();
            // Pick up a new URL/key immediately rather than at the next tick.
            root.refresh("full");
        }
    }

    // --- polling -----------------------------------------------------------
    // Two tiers: a cheap summary (3 requests) at a rate that depends on whether
    // anything is happening, and a full poll (one request per folder) much less
    // often. The folder/device detail from the last full poll is carried forward
    // by Status.derive so summary ticks never blank the UI.
    readonly property bool active: syncState.kind === "syncing" || syncState.kind === "error"

    Timer {
        id: summaryTimer
        interval: root.active ? root.cfg.pollActiveMs : root.cfg.pollIdleMs
        repeat: true
        running: true
        onTriggered: root.refresh("summary")
    }

    Timer {
        id: fullTimer
        interval: Math.max(root.cfg.pollIdleMs * 2, 10000)
        repeat: true
        running: true
        onTriggered: root.refresh("full")
    }

    // Debounce window per tier. Without distinct ids a full poll triggered by a
    // settings change would cancel the summary tier, and vice versa.
    function refresh(mode) {
        const useMode = (mode === "full") ? "full" : "summary";
        const args = Config.pollArgs(scriptPath, cfg, useMode);
        const timeoutMs = Math.max(cfg.requestTimeoutS * 1000 + 2000, 8000);

        busy = true;
        Proc.runCommand(pluginId + ".poll." + useMode, args, (stdout, exitCode) => {
            root.busy = false;
            root._apply(stdout, exitCode, useMode);
        }, 100, timeoutMs, root);
    }

    function _apply(stdout, exitCode, mode) {
        let raw = null;

        // exitCode 124 is Proc's timeout. The script itself always exits 0 and
        // reports expected failures in its JSON, so a non-zero exit means the
        // script is missing or broken — which is a different problem from
        // Syncthing being down, and worth saying so.
        if (exitCode === 124) {
            raw = {
                ok: false,
                reason: "unreachable",
                detail: "poll timed out after " + cfg.requestTimeoutS + "s"
            };
        } else if (exitCode !== 0) {
            raw = {
                ok: false,
                reason: "unconfigured",
                detail: "poll script failed (exit " + exitCode + "): " + scriptPath
            };
        } else {
            try {
                raw = JSON.parse(stdout);
            } catch (e) {
                raw = {
                    ok: false,
                    reason: "unconfigured",
                    detail: "unparseable poll output: " + String(e)
                };
            }
        }

        const previous = syncState;
        const next = Status.derive(raw, previous);
        syncState = next;
        stamp = stamp + 1;

        // Notify on the *transition* into an error, never on every poll.
        if (cfg.notifyOnError && next.kind === "error" && previous.kind !== "error")
            ToastService.showError("Syncthing", next.detail || "Sync error");

        // A summary tick that newly looks like trouble deserves the detail that
        // only a full poll can supply (which folder, which device).
        if (mode === "summary" && next.kind !== previous.kind && next.ok)
            Qt.callLater(() => root.refresh("full"));
    }

    // --- actions -----------------------------------------------------------
    // Write actions go through the poll script's --post mode so that base-URL
    // and API-key resolution live in exactly one place; nothing here needs to
    // know how the key was obtained.
    function _post(path, label) {
        const args = Config.pollArgs(scriptPath, cfg, "summary");
        // Replace "--mode summary" with "--post <path>", keeping the connection flags.
        const postArgs = [scriptPath, "--post", path].concat(args.slice(3));
        const timeoutMs = Math.max(cfg.requestTimeoutS * 1000 + 2000, 8000);

        Proc.runCommand(pluginId + ".post" + path, postArgs, (stdout, exitCode) => {
            let result = null;
            try {
                result = JSON.parse(stdout);
            } catch (e) {
                result = null;
            }

            if (exitCode !== 0 || !result || result.ok !== true) {
                const why = result && result.detail ? result.detail : ("exit " + exitCode);
                ToastService.showError("Syncthing", label + " failed: " + why);
                return;
            }

            ToastService.showInfo("Syncthing", label);
            root.refresh("full");
        }, 50, timeoutMs, root);
    }

    function rescanAll() {
        _post("/rest/db/scan", "Rescan started");
    }

    function clearErrors() {
        _post("/rest/system/error/clear", "Errors cleared");
    }

    function restartSyncthing() {
        _post("/rest/system/restart", "Restarting Syncthing");
    }

    function openLocalUi() {
        Qt.openUrlExternally(localUrl);
    }

    function openServerUi() {
        if (hasServer)
            Qt.openUrlExternally(serverUrl);
    }

    Component.onCompleted: {
        loadSettings();
        refresh("full");
    }
}
