import QtQuick
import qs.Common
import qs.Widgets
import "Config.js" as Config
import "Status.js" as Status

// The body of the detail view: verdict, errors, devices, folders, actions.
// Shared by the bar popout and the Control Center detail panel so the two can
// never drift apart. `compact` trims it for the smaller Control Center panel.
//
// Colour rule for this file, and the reason the panel was unreadable before:
// a severity colour goes on an icon, a meter or a border. Label text stays at
// Theme.surfaceText / Theme.surfaceVariantText. Where a value must read as an
// error, it goes through `pal.text()`, which guarantees contrast against the
// surface on every theme. Nothing here sets a background without also setting
// its foreground.
Column {
    id: root

    property bool compact: false
    // Set by the popout so the action buttons can dismiss it; null in the
    // Control Center, where there is nothing to close.
    property var onNavigate: null

    // Restart is disruptive, so it takes two clicks rather than opening a modal.
    property bool confirmingRestart: false

    readonly property var cfg: SyncthingService.cfg
    readonly property var st: SyncthingService.syncState
    readonly property var look: Status.presentation(st.kind)
    readonly property bool hasServer: SyncthingService.hasServer

    readonly property SyncthingPalette pal: SyncthingPalette {}

    spacing: Theme.spacingM

    readonly property color statusColor: root.pal.tone(root.look.color)
    readonly property int totalErrors: {
        let n = st.errors.length;
        for (let i = 0; i < st.folders.length; i++)
            n += st.folders[i].errorCount;
        return n;
    }

    component Divider: Rectangle {
        height: Theme.layerOutlineWidth
        color: Theme.outlineMedium
    }

    // ---------------------------------------------------------------- verdict
    Row {
        width: parent.width
        spacing: Theme.spacingM

        // DankSpinner is DMS's own M3 progress indicator. The previous version
        // rotated the status glyph with a RotationAnimator, which needs
        // DankIcon.smoothTransform or it renders with NativeRendering artefacts
        // — and still would not have looked like the rest of the shell.
        Item {
            width: root.compact ? Theme.iconSize : Theme.iconSizeLarge
            height: width
            anchors.verticalCenter: parent.verticalCenter

            DankSpinner {
                anchors.fill: parent
                visible: root.st.kind === "syncing"
                running: visible
                size: parent.width
                color: root.statusColor
            }

            DankIcon {
                anchors.centerIn: parent
                visible: root.st.kind !== "syncing"
                name: root.look.icon
                size: parent.width
                color: root.statusColor
            }
        }

        Column {
            width: parent.width - (root.compact ? Theme.iconSize : Theme.iconSizeLarge) - Theme.spacingM
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                width: parent.width
                text: root.st.label
                font.pixelSize: root.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.st.detail
                visible: text.length > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    // ----------------------------------------------------------- not set up
    // The one state the user can only fix outside this panel.
    MessageCard {
        width: parent.width
        visible: root.st.kind === "unconfigured" || root.st.kind === "unreachable"
        tone: root.pal.warn
        iconName: "help"
        message: root.st.kind === "unreachable" ? qsTr("Could not reach %1.\nIs the Syncthing service running?").arg(SyncthingService.localUrl) : (root.st.detail || qsTr("No Syncthing API key found. Set one in the plugin settings."))
    }

    // ----------------------------------------------------------------- errors
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: root.totalErrors > 0

        SectionHeader {
            label: qsTr("Errors")
            count: root.totalErrors
        }

        // System-wide errors first — these are usually the root cause.
        Repeater {
            model: root.st.errors

            MessageCard {
                required property var modelData
                width: root.width
                tone: root.pal.danger
                iconName: "error"
                message: modelData.message
                maxLines: 3
            }
        }

        // Then per-folder failures, naming the folder so it is actionable.
        Repeater {
            model: root.st.folders.filter(f => f.errorCount > 0)

            StatusCard {
                required property var modelData
                width: root.width
                iconName: "folder_off"
                accent: root.pal.danger
                title: modelData.label
                subtitle: modelData.error && modelData.error.length > 0 ? modelData.error : Status.plural(modelData.errorCount, qsTr("error"))
                trailingText: Status.plural(modelData.errorCount, qsTr("error"))
                // The one place a value is tinted rather than neutral: an error
                // count should read as an error. pal.text keeps it legible when
                // the theme's error colour is a pale fallback.
                trailingColor: root.pal.text(root.pal.danger)
            }
        }

        DankButton {
            text: qsTr("Dismiss errors")
            iconName: "clear_all"
            visible: root.st.errors.length > 0
            onClicked: SyncthingService.clearErrors()
        }
    }

    Divider {
        width: parent.width
        visible: root.st.devices.length > 0 && root.totalErrors > 0
    }

    // ---------------------------------------------------------------- devices
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: root.st.devices.length > 0

        SectionHeader {
            label: qsTr("Devices")
            count: root.st.devices.length
        }

        Repeater {
            model: root.st.devices

            StatusCard {
                required property var modelData

                // Mark which peer is the remote instance the user configured,
                // so the "Server UI" button has an obvious referent. Only shown
                // when a remote is actually configured.
                readonly property bool isRemote: root.hasServer && SyncthingService.serverHost.length > 0 && modelData.address.indexOf(SyncthingService.serverHost) === 0

                width: root.width
                compact: root.compact
                iconName: modelData.connected ? "cloud_done" : "cloud_off"
                accent: modelData.connected ? root.pal.ok : root.pal.warn
                title: isRemote ? modelData.name + " (" + root.cfg.serverLabel + ")" : modelData.name
                // Second line only when it carries information. "idle" under a
                // folder already showing 100%, or an address under a device
                // already showing "in sync", is ink spent saying nothing — and
                // six of those were what pushed the body past the scroll cap.
                subtitle: (modelData.connected && modelData.needBytes > 0) ? qsTr("%1 behind").arg(Status.formatBytes(modelData.needBytes)) : ""
                trailingText: {
                    if (!modelData.connected)
                        return modelData.lastSeen ? qsTr("last seen %1").arg(Status.formatAge(modelData.lastSeen)) : qsTr("never seen");
                    if (modelData.percent >= 0 && modelData.percent < 100)
                        return Math.floor(modelData.percent) + "%";
                    return qsTr("in sync");
                }
                trailingColor: modelData.connected ? Theme.surfaceVariantText : root.pal.text(root.pal.warn)
                // Only worth a meter when the peer is actually behind; a full
                // bar on every in-sync device is noise.
                showMeter: modelData.connected && modelData.percent >= 0 && modelData.percent < 100
                meterValue: modelData.percent / 100
            }
        }
    }

    Divider {
        width: parent.width
        visible: root.st.folders.length > 0
    }

    // ---------------------------------------------------------------- folders
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: root.st.folders.length > 0

        SectionHeader {
            label: qsTr("Folders")
            count: root.st.folders.length
        }

        Repeater {
            // Problem folders sort first (see Status.js), so a compact view that
            // truncates still shows what is wrong.
            model: root.compact ? root.st.folders.slice(0, 4) : root.st.folders

            StatusCard {
                required property var modelData

                width: root.width
                compact: root.compact
                iconName: modelData.paused ? "pause_circle" : (modelData.errorCount > 0 ? "folder_off" : "folder")
                accent: {
                    if (modelData.errorCount > 0)
                        return root.pal.danger;
                    if (modelData.paused)
                        return root.pal.muted;
                    return modelData.needBytes > 0 ? root.pal.busy : root.pal.ok;
                }
                title: modelData.label
                subtitle: modelData.paused ? qsTr("paused") : (modelData.state === "idle" ? "" : modelData.state)
                trailingText: modelData.needBytes > 0 ? qsTr("%1 behind").arg(Status.formatBytes(modelData.needBytes)) : Math.floor(modelData.percent) + "%"
                trailingColor: modelData.errorCount > 0 ? root.pal.text(root.pal.danger) : Theme.surfaceVariantText
                showMeter: !modelData.paused && modelData.percent < 100
                meterValue: modelData.percent / 100
            }
        }

        StyledText {
            text: qsTr("+%1 more").arg(root.st.folders.length - 4)
            visible: root.compact && root.st.folders.length > 4
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Divider {
        width: parent.width
    }

    // ---------------------------------------------------------------- actions
    Flow {
        width: parent.width
        spacing: Theme.spacingS

        DankButton {
            text: qsTr("Rescan all")
            iconName: "refresh"
            // DankButton has no disabled styling of its own, so dim it too.
            enabled: root.st.ok
            opacity: enabled ? 1.0 : 0.45
            onClicked: SyncthingService.rescanAll()
        }

        DankButton {
            id: restartButton

            text: root.confirmingRestart ? qsTr("Confirm restart") : qsTr("Restart")
            iconName: root.confirmingRestart ? "warning" : "restart_alt"
            enabled: root.st.ok
            opacity: enabled ? 1.0 : 0.45

            // This pairing is the bug that made the panel unreadable. DankButton
            // defaults textColor to Theme.buttonText, which is only ever
            // correct against Theme.buttonBg — on stock Amber dark that is
            // #000000, so overriding the background alone painted black text on
            // #2e2921. Resting state therefore keeps DMS's own matched pair by
            // not touching either property; the armed state sets both.
            backgroundColor: root.confirmingRestart ? Theme.withAlpha(root.pal.danger, 0.22) : Theme.buttonBg
            textColor: root.confirmingRestart ? root.pal.text(root.pal.danger) : Theme.buttonText

            onClicked: {
                if (root.confirmingRestart) {
                    root.confirmingRestart = false;
                    SyncthingService.restartSyncthing();
                } else {
                    root.confirmingRestart = true;
                    restartConfirmTimeout.restart();
                }
            }
        }

        DankButton {
            text: qsTr("Local Web UI")
            iconName: "open_in_new"
            onClicked: {
                SyncthingService.openLocalUi();
                if (root.onNavigate)
                    root.onNavigate();
            }
        }

        // Only present when the user has configured a remote instance. With it
        // unset there is simply one fewer button, not a gap.
        DankButton {
            text: qsTr("%1 UI").arg(root.cfg.serverLabel)
            iconName: "dns"
            visible: root.hasServer
            onClicked: {
                SyncthingService.openServerUi();
                if (root.onNavigate)
                    root.onNavigate();
            }
        }
    }

    // Don't leave the button armed indefinitely.
    Timer {
        id: restartConfirmTimeout
        interval: 4000
        onTriggered: root.confirmingRestart = false
    }
}
