import QtQuick
import qs.Common
import qs.Widgets

// One row of the detail panel, as a card: leading status icon, title with an
// optional subtitle, a trailing value, and an optional completion meter. Shared
// by the device and folder lists so the two cannot drift apart, and matched to
// how DMS styles its own Control Center lists (see
// Modules/ControlCenter/Details/DiskUsageDetail.qml).
//
// Purely presentational — everything arrives through properties, so this file
// never touches SyncthingService and needs no qmldir entry.
StyledRect {
    id: root

    property string iconName: ""
    // The severity accent. It lands on the icon and the meter, never on the
    // label text, which is what keeps rows legible on every theme.
    property color accent: Theme.surfaceVariantText

    property string title: ""
    property string subtitle: ""

    property string trailingText: ""
    property color trailingColor: Theme.surfaceVariantText

    property bool showMeter: false
    property real meterValue: 0

    // Rows are informational by default. Set a tooltip or connect `clicked` and
    // the hover affordance appears with it.
    property var tooltipText: null
    property bool interactive: false

    // `compact` drops the meter and the subtitle gap for the desktop widget,
    // where vertical space is the binding constraint.
    property bool compact: false

    signal clicked

    readonly property real _pad: root.compact ? Theme.spacingXS : Theme.spacingS

    implicitHeight: content.implicitHeight + root._pad * 2
    radius: Theme.cornerRadius
    // Both alpha-based tokens: they tint with the panel behind them rather than
    // painting an opaque block over a translucent or blurred surface.
    color: Theme.surfaceLight
    border.color: Theme.outlineLight
    border.width: Theme.layerOutlineWidth

    Column {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root._pad
        anchors.rightMargin: root._pad
        spacing: Theme.spacingXS

        Item {
            id: headline

            width: parent.width
            implicitHeight: Math.max(leadingIcon.visible ? leadingIcon.height : 0, labels.implicitHeight)

            DankIcon {
                id: leadingIcon

                name: root.iconName
                visible: root.iconName.length > 0
                size: Theme.iconSizeSmall
                color: root.accent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            // Anchored to the right edge so the value genuinely right-aligns.
            // The old layout used an `Item { width: 1; height: 1 }` as a Row
            // spacer, which does not expand — the values only looked aligned
            // when every label happened to be the same length.
            StyledText {
                id: trailing

                text: root.trailingText
                visible: text.length > 0
                font.pixelSize: Theme.fontSizeSmall
                color: root.trailingColor
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                id: labels

                anchors.left: leadingIcon.visible ? leadingIcon.right : parent.left
                anchors.leftMargin: leadingIcon.visible ? Theme.spacingS : 0
                anchors.right: trailing.visible ? trailing.left : parent.right
                anchors.rightMargin: trailing.visible ? Theme.spacingS : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                StyledText {
                    width: parent.width
                    text: root.title
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.subtitle
                    visible: text.length > 0 && !root.compact
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }
        }

        MeterBar {
            width: parent.width
            visible: root.showMeter && !root.compact
            value: root.meterValue
            fillColor: root.accent
        }
    }

    // Strictly opt-in. A StateLayer is a MouseArea, and an always-present one
    // would accept presses inside the popout's DankFlickable and fight the
    // flick gesture. Informational rows get no MouseArea at all.
    Loader {
        anchors.fill: parent
        active: root.interactive
        sourceComponent: Component {
            StateLayer {
                cornerRadius: root.radius
                tooltipText: root.tooltipText
                onClicked: root.clicked()
            }
        }
    }
}
