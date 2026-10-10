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

    // Status colours are derived in Palette.js rather than switched on inline,
    // because two of the tokens need correcting before use: a theme may leave
    // warning/error/success undefined, and the Material fallbacks then collide
    // with some themes' primary. See Palette.js for the detail.
    readonly property SyncthingPalette pal: SyncthingPalette {}

    readonly property color statusColor: root.pal.tone(root.look.color)
    readonly property bool quiet: cfg.hideWhenUpToDate && st.kind === "uptodate"

    // ---------------------------------------------------------------------
    // Bar pill
    // ---------------------------------------------------------------------
    // BasePill sizes the pill from the content root's implicitWidth/Height, so
    // a Row/Column root is what we want — and it already draws the background,
    // outline, hover tint and ripple, so we must not add our own.
    //
    // Hiding is driven through setVisibilityOverride rather than `visible` on
    // the content: an invisible Row still reports an implicitWidth, so the old
    // approach left an empty but still hoverable pill sitting in the bar.
    // PluginComponent's override animates the pill width to zero.
    onQuietChanged: root._applyQuiet()
    Component.onCompleted: root._applyQuiet()

    function _applyQuiet() {
        if (quiet)
            setVisibilityOverride(false);
        else
            clearVisibilityOverride();
    }

    component PillIcon: DankIcon {
        name: root.look.icon
        size: root.iconSize
        color: root.statusColor
    }

    component PillSpinner: DankSpinner {
        size: root.iconSize
        color: root.statusColor
        running: visible
    }

    component PillText: StyledText {
        text: Status.pillText(root.st, root.cfg)
        visible: text.length > 0
        // Theme.widgetTextColor honours the user's bar "colorful" setting; the
        // error case overrides it because an unreadable-but-colourful pill is
        // not a trade worth making. pal.text guarantees the contrast.
        color: root.st.kind === "error" ? root.pal.text(root.pal.danger) : (Theme.widgetTextColor || Theme.surfaceText)
        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
    }

    // DMS's own M3 spinner, used in place of rotating the glyph: DankIcon needs
    // smoothTransform to rotate without NativeRendering artefacts, and even
    // then a spinning cloud does not match how the rest of the shell indicates
    // progress.
    component PillGlyph: Item {
        implicitWidth: root.iconSize
        implicitHeight: root.iconSize

        PillSpinner {
            anchors.centerIn: parent
            visible: root.st.kind === "syncing"
        }

        PillIcon {
            anchors.centerIn: parent
            visible: root.st.kind !== "syncing"
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            PillGlyph {
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

            PillGlyph {
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
            // The popout surface is already withAlpha(surfaceContainer,
            // popupTransparency), so an opaque surfaceContainerHigh card both
            // sat invisibly close to it and ignored the user's blur and
            // transparency settings. nestedSurface is the transparency-aware
            // token DMS uses for exactly this, e.g. in
            // Modules/ControlCenter/Details/DiskUsageDetail.qml.
            color: Theme.nestedSurface
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth

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
