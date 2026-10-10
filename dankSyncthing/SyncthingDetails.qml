import QtQuick
import qs.Common
import qs.Widgets
import "Config.js" as Config
import "Status.js" as Status

// The body of the detail view: verdict, errors, devices, folders, actions.
// Shared by the bar popout and the Control Center detail panel so the two can
// never drift apart. `compact` trims it for the smaller Control Center panel.
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

    spacing: Theme.spacingM

    function tone(token) {
        switch (token) {
        case "success":
            return Theme.success;
        case "primary":
            return Theme.primary;
        case "warning":
            return Theme.warning;
        case "error":
            return Theme.error;
        case "onSurfaceVariant":
            return Theme.onSurfaceVariant;
        default:
            return Theme.surfaceText;
        }
    }

    readonly property color statusColor: tone(look.color)
    readonly property int totalErrors: {
        let n = st.errors.length;
        for (let i = 0; i < st.folders.length; i++)
            n += st.folders[i].errorCount;
        return n;
    }

    // Reusable section heading.
    component SectionLabel: StyledText {
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.onSurfaceVariant
    }

    component Divider: Rectangle {
        height: 1
        color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
    }

    // ---------------------------------------------------------------- verdict
    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: root.look.icon
            size: root.compact ? Theme.iconSize : Theme.iconSizeLarge
            color: root.statusColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            width: parent.width - Theme.iconSizeLarge - Theme.spacingM
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.st.label
                font.pixelSize: root.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: root.st.detail
                visible: text.length > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    // ----------------------------------------------------------- not set up
    // The one state the user can only fix outside this panel.
    Rectangle {
        width: parent.width
        visible: root.st.kind === "unconfigured" || root.st.kind === "unreachable"
        implicitHeight: hintText.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.10)
        border.width: 0

        StyledText {
            id: hintText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.spacingM
            text: root.st.kind === "unreachable" ? qsTr("Could not reach %1.\nIs the Syncthing service running?").arg(SyncthingService.localUrl) : (root.st.detail || qsTr("No Syncthing API key found. Set one in the plugin settings."))
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
        }
    }

    // ----------------------------------------------------------------- errors
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: root.totalErrors > 0

        SectionLabel {
            text: qsTr("Errors (%1)").arg(root.totalErrors)
        }

        // System-wide errors first — these are usually the root cause.
        Repeater {
            model: root.st.errors

            Rectangle {
                required property var modelData
                width: root.width
                implicitHeight: sysErrText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                border.width: 0

                StyledText {
                    id: sysErrText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingS
                    text: modelData.message
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // Then per-folder failures, naming the folder so it is actionable.
        Repeater {
            model: root.st.folders.filter(f => f.errorCount > 0)

            StyledText {
                required property var modelData
                width: root.width
                text: "• " + modelData.label + " — " + (modelData.error && modelData.error.length > 0 ? modelData.error : Status.plural(modelData.errorCount, qsTr("error")))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
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

        SectionLabel {
            text: qsTr("Devices")
        }

        Repeater {
            model: root.st.devices

            Row {
                required property var modelData
                width: root.width
                spacing: Theme.spacingS

                DankIcon {
                    name: modelData.connected ? "cloud_done" : "cloud_off"
                    size: Theme.iconSizeSmall
                    color: modelData.connected ? Theme.success : Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: modelData.name
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Mark which peer is the remote instance the user configured,
                // so the "Server UI" button has an obvious referent. Only shown
                // when a remote is actually configured.
                StyledText {
                    text: qsTr("(%1)").arg(root.cfg.serverLabel)
                    visible: root.hasServer && SyncthingService.serverHost.length > 0 && modelData.address.indexOf(SyncthingService.serverHost) === 0
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: 1
                    height: 1
                }

                StyledText {
                    text: {
                        if (!modelData.connected)
                            return modelData.lastSeen ? qsTr("last seen %1").arg(Status.formatAge(modelData.lastSeen)) : qsTr("never seen");
                        if (modelData.percent >= 0 && modelData.percent < 100)
                            return Math.floor(modelData.percent) + "% synced";
                        return qsTr("in sync");
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: modelData.connected ? Theme.onSurfaceVariant : Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }
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
        spacing: 2
        visible: root.st.folders.length > 0

        SectionLabel {
            text: qsTr("Folders")
        }

        Repeater {
            // Problem folders sort first (see Status.js), so a compact view that
            // truncates still shows what is wrong.
            model: root.compact ? root.st.folders.slice(0, 4) : root.st.folders

            Row {
                required property var modelData
                width: root.width
                spacing: Theme.spacingS

                StyledText {
                    text: modelData.label
                    font.pixelSize: Theme.fontSizeSmall
                    color: modelData.errorCount > 0 ? Theme.error : Theme.surfaceText
                    elide: Text.ElideRight
                    width: Math.max(60, root.width * 0.4)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: modelData.paused ? qsTr("paused") : modelData.state
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: 1
                    height: 1
                }

                StyledText {
                    text: modelData.needBytes > 0 ? Status.formatBytes(modelData.needBytes) + " behind" : Math.floor(modelData.percent) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: modelData.needBytes > 0 ? Theme.primary : Theme.onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        StyledText {
            text: qsTr("+%1 more").arg(root.st.folders.length - 4)
            visible: root.compact && root.st.folders.length > 4
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.onSurfaceVariant
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
            text: root.confirmingRestart ? qsTr("Confirm restart") : qsTr("Restart")
            iconName: root.confirmingRestart ? "warning" : "restart_alt"
            enabled: root.st.ok
            opacity: enabled ? 1.0 : 0.45
            backgroundColor: root.confirmingRestart ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.22) : Theme.surfaceContainerHigh
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
