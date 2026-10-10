import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Config.js" as Config
import "Status.js" as Status

// Bar pill + popout + Control Center card. All state comes from the
// SyncthingService singleton, so this file holds no polling of its own.
PluginComponent {
    id: root

    layerNamespacePlugin: "dank-syncthing"

    readonly property var cfg: Config.resolve(pluginData)
    readonly property var st: SyncthingService.syncState
    readonly property var look: Status.presentation(st.kind)

    // Theme colour token name -> actual colour. Every token here was checked
    // against Common/Theme.qml; THEME_REFERENCE.md also lists some that do not
    // exist (errorText, onError, popupBackground, cornerRadiusSmall).
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
    readonly property bool quiet: cfg.hideWhenUpToDate && st.kind === "uptodate"

    // ---------------------------------------------------------------------
    // Bar pill
    // ---------------------------------------------------------------------
    // BasePill sizes the pill from the content root's implicitWidth/Height, so
    // a Row/Column root is what we want — and it already draws the background,
    // outline, hover tint and ripple, so we must not add our own.
    component PillIcon: DankIcon {
        id: pillIcon

        // DankIcon has no `font` property; the glyph size is set with `size`.
        name: root.look.icon
        size: root.iconSize
        color: root.statusColor

        RotationAnimator {
            target: pillIcon
            from: 0
            to: 360
            duration: 1600
            loops: Animation.Infinite
            running: root.st.kind === "syncing"
            // Leave the glyph upright once it stops spinning.
            onRunningChanged: if (!running)
                pillIcon.rotation = 0
        }
    }

    component PillText: StyledText {
        text: Status.pillText(root.st, root.cfg)
        visible: text.length > 0
        color: root.st.kind === "error" ? Theme.error : (Theme.widgetTextColor || Theme.surfaceText)
        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            visible: !root.quiet

            PillIcon {
                anchors.verticalCenter: parent.verticalCenter
            }

            PillText {
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            visible: !root.quiet

            PillIcon {
                anchors.horizontalCenter: parent.horizontalCenter
            }

            PillText {
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ---------------------------------------------------------------------
    // Popout
    // ---------------------------------------------------------------------
    popoutWidth: 440
    popoutHeight: 560

    popoutContent: Component {
        SyncthingPopout {}
    }

    // ---------------------------------------------------------------------
    // Control Center card
    // ---------------------------------------------------------------------
    // DMS decides whether to offer this card by instantiating the component
    // headlessly with createObject(null) and reading ccWidgetIcon, then
    // destroying it. In that probe the singleton may not be ready, so this
    // expression must never dereference state unguarded — a throw here means
    // the card silently never appears.
    ccWidgetIcon: {
        const s = SyncthingService.syncState;
        return (s && s.kind) ? Status.presentation(s.kind).icon : "cloud_sync";
    }
    ccWidgetPrimaryText: "Syncthing"
    ccWidgetSecondaryText: {
        const s = SyncthingService.syncState;
        if (!s || !s.kind)
            return "";
        return s.detail ? s.label + " · " + s.detail : s.label;
    }
    ccWidgetIsActive: st.kind === "uptodate" || st.kind === "syncing"
    ccWidgetIsToggle: false

    ccDetailHeight: 320
    ccDetailContent: Component {
        Rectangle {
            implicitHeight: ccBody.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 0

            SyncthingDetails {
                id: ccBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                compact: true
            }
        }
    }

    onCcWidgetExpanded: SyncthingService.refresh("full")
}
