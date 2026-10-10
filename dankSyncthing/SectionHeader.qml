import QtQuick
import qs.Common
import qs.Widgets

// Section label for the detail panel: "Devices", "Folders (6)".
StyledText {
    id: root

    property string label: ""
    // Negative means "no count", which is different from a count of zero.
    property int count: -1

    text: root.count >= 0 ? root.label + " (" + root.count + ")" : root.label
    font.pixelSize: Theme.fontSizeSmall
    font.weight: Font.Bold
    // Deliberately the dimmer of the two text tokens: headers are scaffolding,
    // and competing with the rows for attention is what made the old panel read
    // as an undifferentiated wall of text.
    color: Theme.surfaceVariantText
}
