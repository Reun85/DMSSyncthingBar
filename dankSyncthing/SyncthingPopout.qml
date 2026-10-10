import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Status.js" as Status

// Bar popout. PopoutComponent supplies the header, the description line and the
// close button, and injects `closePopout` / `parentPopout` into this root.
PopoutComponent {
    id: popout

    headerText: qsTr("Syncthing")
    detailsText: SyncthingService.syncState.label
    showCloseButton: true

    // Refresh on open so the panel never shows a stale picture from the last
    // time it was looked at.
    Connections {
        target: popout.parentPopout
        enabled: popout.parentPopout !== null
        function onOpened() {
            SyncthingService.refresh("full");
        }
    }

    headerActions: Component {
        DankActionButton {
            iconName: "refresh"
            tooltipText: qsTr("Refresh now")
            onClicked: SyncthingService.refresh("full")
        }
    }

    // The body scrolls: a machine with many folders, or several errors, can
    // easily exceed a sensible popout height. Below that cap the popout simply
    // shrinks to fit, because PluginPopout sizes the window from this root's
    // implicitHeight.
    readonly property real maxBodyHeight: 520

    DankFlickable {
        id: bodyScroll

        width: parent.width
        implicitHeight: Math.min(body.implicitHeight, popout.maxBodyHeight)
        contentHeight: body.implicitHeight
        contentWidth: width
        clip: true

        SyncthingDetails {
            id: body
            // A Flickable's children are parented to its contentItem, whose
            // width is not bound to the Flickable — bind it explicitly or the
            // body collapses to zero width.
            width: bodyScroll.width
            onNavigate: () => {
                if (popout.closePopout)
                    popout.closePopout();
            }
        }
    }
}
