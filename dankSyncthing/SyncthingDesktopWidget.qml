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

    // The card composites over the wallpaper rather than over a panel, so the
    // palette's contrast reference is the card fill, not surfaceContainer.
    readonly property SyncthingPalette pal: SyncthingPalette {
        surface: Theme.surfaceContainer
    }

    readonly property color statusColor: root.pal.tone(root.look.color)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        // Alpha on the colour rather than `opacity` on the item: an opacity
        // layer forces the whole subtree into an offscreen render target, and
        // this is how DMS's own desktop widgets do it (see
        // Modules/BuiltinDesktopPlugins/SystemMonitorWidget.qml).
        color: Theme.withAlpha(Theme.surfaceContainer, root.cfg.desktopOpacity / 100)
        border.color: Theme.outlineMedium
        border.width: Theme.layerOutlineWidth
    }

    Column {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        // ------------------------------------------------------------ headline
        Row {
            id: headline

            width: parent.width
            spacing: Theme.spacingS

            Item {
                id: statusGlyph

                width: Theme.iconSize
                height: Theme.iconSize
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
                    size: Theme.iconSize
                    color: root.statusColor
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
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Theme.layerOutlineWidth
            color: Theme.outlineMedium
            visible: foldersCol.visible || devicesCol.visible
        }

        // ------------------------------------------------------------- folders
        Column {
            id: foldersCol

            width: parent.width
            spacing: Theme.spacingXS
            visible: root.cfg.desktopShowFolders && root.st.folders.length > 0

            // Only as many rows as actually fit, so the card never overflows its
            // user-chosen size. Problem folders sort first in Status.js, so a
            // truncated list still shows what is wrong.
            readonly property int rowHeight: Theme.fontSizeSmall + Theme.spacingXS * 2 + Theme.spacingXS
            readonly property int maxRows: {
                const avail = root.height - (Theme.spacingM * 2) - headline.height - Theme.spacingS * 2 - (devicesCol.visible ? foldersCol.rowHeight : 0);
                return Math.max(0, Math.floor(avail / rowHeight));
            }

            Repeater {
                model: root.st.folders.slice(0, foldersCol.maxRows)

                StatusCard {
                    required property var modelData

                    width: foldersCol.width
                    compact: true
                    iconName: modelData.paused ? "pause_circle" : (modelData.errorCount > 0 ? "folder_off" : "folder")
                    accent: {
                        if (modelData.errorCount > 0)
                            return root.pal.danger;
                        if (modelData.paused)
                            return root.pal.muted;
                        return modelData.needBytes > 0 ? root.pal.busy : root.pal.ok;
                    }
                    title: modelData.label
                    trailingText: {
                        if (modelData.errorCount > 0)
                            return Status.plural(modelData.errorCount, qsTr("error"));
                        if (modelData.paused)
                            return qsTr("paused");
                        return modelData.needBytes > 0 ? Status.formatBytes(modelData.needBytes) : Math.floor(modelData.percent) + "%";
                    }
                    trailingColor: modelData.errorCount > 0 ? root.pal.text(root.pal.danger) : Theme.surfaceVariantText
                }
            }

            StyledText {
                text: qsTr("+%1 more").arg(root.st.folders.length - foldersCol.maxRows)
                visible: root.st.folders.length > foldersCol.maxRows && foldersCol.maxRows > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        // ------------------------------------------------------------- devices
        Column {
            id: devicesCol

            width: parent.width
            spacing: Theme.spacingXS
            visible: root.cfg.desktopShowDevices && root.st.devices.length > 0

            Repeater {
                model: root.st.devices

                StatusCard {
                    required property var modelData

                    width: devicesCol.width
                    compact: true
                    iconName: modelData.connected ? "cloud_done" : "cloud_off"
                    accent: modelData.connected ? root.pal.ok : root.pal.warn
                    title: modelData.name
                    trailingText: modelData.connected ? (modelData.percent >= 0 && modelData.percent < 100 ? Math.floor(modelData.percent) + "%" : "") : (modelData.lastSeen ? Status.formatAge(modelData.lastSeen) : qsTr("never"))
                    trailingColor: modelData.connected ? Theme.surfaceVariantText : root.pal.text(root.pal.warn)
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
