import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

// Daemon surface: instantiated exactly once for as long as the plugin is
// enabled, unlike the view surfaces which exist per bar and per screen.
//
// Its only jobs are to wake the polling singleton and to own the IPC handler.
PluginComponent {
    id: root

    // No bar pill and no popout: this surface is intentionally invisible.

    IpcHandler {
        target: "dankSyncthing"

        // Explicit return-type annotations are required, or the function is
        // invisible to `dms ipc`.
        function refresh(): string {
            SyncthingService.refresh("full");
            return "refreshing";
        }

        function status(): string {
            const s = SyncthingService.syncState;
            return s.kind + "\t" + s.label + (s.detail ? "\t" + s.detail : "");
        }

        function openWeb(): string {
            SyncthingService.openLocalUi();
            return SyncthingService.localUrl;
        }

        function openServer(): string {
            if (!SyncthingService.hasServer)
                return "no server configured";
            SyncthingService.openServerUi();
            return SyncthingService.serverUrl;
        }

        function rescan(): string {
            SyncthingService.rescanAll();
            return "rescan requested";
        }
    }

    Component.onCompleted: {
        // QML singletons are lazy: without touching SyncthingService here it
        // would never be constructed, and nothing would poll until a bar widget
        // happened to be placed. Reading a property is enough to instantiate it.
        console.info("dankSyncthing: daemon started, poll script at", SyncthingService.scriptPath);
    }

    Component.onDestruction: {
        console.info("dankSyncthing: daemon stopped");
    }
}
