import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Config.js" as Config
import "Status.js" as Status

// Desktop widget: an always-visible card on the wallpaper. Position and size are
// persisted by DesktopPluginWrapper, so nothing here does that.
DesktopPluginComponent {
    id: root

    minWidth: 220
    minHeight: 120

    readonly property var cfg: Config.resolve(pluginData)
    readonly property var st: SyncthingService.syncState
    readonly property var look: Status.presentation(st.kind)

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

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        opacity: root.cfg.desktopOpacity / 100
    }

    Column {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        // ------------------------------------------------------------ headline
        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankIcon {
                id: statusIcon
                name: root.look.icon
                size: Theme.iconSize
                color: root.statusColor
                anchors.verticalCenter: parent.verticalCenter

                RotationAnimator {
                    target: statusIcon
                    from: 0
                    to: 360
                    duration: 1600
                    loops: Animation.Infinite
                    running: root.st.kind === "syncing"
                    onRunningChanged: if (!running)
                        statusIcon.rotation = 0
                }
            }

            Column {
                width: parent.width - Theme.iconSize - Theme.spacingS
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: root.st.label
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    width: parent.width
                }

                StyledText {
                    text: root.st.detail
                    visible: text.length > 0
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
            visible: foldersCol.visible || devicesCol.visible
        }

        // ------------------------------------------------------------- folders
        Column {
            id: foldersCol

            width: parent.width
            spacing: 1
            visible: root.cfg.desktopShowFolders && root.st.folders.length > 0

            // Only as many rows as actually fit, so the card never overflows its
            // user-chosen size. Problem folders sort first in Status.js, so a
            // truncated list still shows what is wrong.
            readonly property int rowHeight: Theme.fontSizeSmall + 4
            readonly property int maxRows: {
                const avail = root.height - (Theme.spacingM * 2) - statusIcon.height - Theme.spacingS * 2 - (devicesCol.visible ? foldersCol.rowHeight : 0);
                return Math.max(0, Math.floor(avail / rowHeight));
            }

            Repeater {
                model: root.st.folders.slice(0, foldersCol.maxRows)

                Row {
                    required property var modelData
                    width: foldersCol.width
                    height: foldersCol.rowHeight

                    StyledText {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.errorCount > 0 ? Theme.error : Theme.surfaceText
                        width: parent.width * 0.6
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: modelData.errorCount > 0 ? Status.plural(modelData.errorCount, qsTr("error")) : (modelData.paused ? qsTr("paused") : (modelData.needBytes > 0 ? Status.formatBytes(modelData.needBytes) : Math.floor(modelData.percent) + "%"))
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.errorCount > 0 ? Theme.error : Theme.onSurfaceVariant
                        width: parent.width * 0.4
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                text: qsTr("+%1 more").arg(root.st.folders.length - foldersCol.maxRows)
                visible: root.st.folders.length > foldersCol.maxRows && foldersCol.maxRows > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
            }
        }

        // ------------------------------------------------------------- devices
        Column {
            id: devicesCol

            width: parent.width
            spacing: 1
            visible: root.cfg.desktopShowDevices && root.st.devices.length > 0

            Repeater {
                model: root.st.devices

                Row {
                    required property var modelData
                    width: devicesCol.width
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: modelData.connected ? "cloud_done" : "cloud_off"
                        size: Theme.iconSizeSmall
                        color: modelData.connected ? Theme.success : Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: modelData.name
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        elide: Text.ElideRight
                        width: parent.width - Theme.iconSizeSmall - Theme.spacingXS * 2 - lagText.width
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        id: lagText
                        text: modelData.connected ? (modelData.percent >= 0 && modelData.percent < 100 ? Math.floor(modelData.percent) + "%" : "") : (modelData.lastSeen ? Status.formatAge(modelData.lastSeen) : qsTr("never"))
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.connected ? Theme.onSurfaceVariant : Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // Click opens the local web UI. Suppressed while the user is positioning the
    // widget, or a drag would fire a navigation.
    MouseArea {
        anchors.fill: parent
        enabled: !root.editMode
        cursorShape: root.editMode ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: SyncthingService.openLocalUi()
    }

    // Injected by DesktopPluginWrapper while the user drags or resizes.
    property bool editMode: false
}
