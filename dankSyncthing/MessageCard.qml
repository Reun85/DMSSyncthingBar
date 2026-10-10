import QtQuick
import qs.Common
import qs.Widgets

// A tinted card for something the user needs to read and act on: a system
// error, or "Syncthing isn't running". Replaces two near-identical hand-rolled
// Rectangles that each open-coded their own Qt.rgba tint.
//
// The tone colour carries the severity on the icon and the border; the body text
// stays at surfaceText. Painting the message itself in the tone is what made
// errors invisible in light mode, where the fallback error colour is a pale
// pink.
StyledRect {
    id: root

    property color tone: Theme.error
    property string iconName: "error"
    property string message: ""
    property int maxLines: 0

    implicitHeight: body.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(root.tone, 0.12)
    border.color: Theme.withAlpha(root.tone, 0.3)
    border.width: 1

    Row {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingS

        DankIcon {
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.tone
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            width: parent.width - Theme.iconSizeSmall - Theme.spacingS
            text: root.message
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
            maximumLineCount: root.maxLines > 0 ? root.maxLines : Number.MAX_VALUE
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
