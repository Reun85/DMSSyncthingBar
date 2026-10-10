import QtQuick
import qs.Common
import qs.Widgets

// A thin completion meter. Used for per-folder and per-device sync progress,
// where the number alone ("87%", "1.4 GB behind") does not convey how far off
// the target is at a glance.
StyledRect {
    id: root

    // 0..1, clamped. Values outside the range are common in the Syncthing API
    // (-1 means "not known yet"), so clamp rather than trusting the caller.
    property real value: 0
    property color fillColor: Theme.primary

    readonly property real _v: Math.max(0, Math.min(1, isNaN(root.value) ? 0 : root.value))

    implicitHeight: 4
    height: implicitHeight
    radius: height / 2
    // Alpha-based, so the track tints with whatever it is drawn on instead of
    // punching an opaque bar through a translucent panel.
    color: Theme.surfaceTextLight

    StyledRect {
        width: parent.width * root._v
        height: parent.height
        radius: parent.radius
        color: root.fillColor

        Behavior on width {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    }
}
