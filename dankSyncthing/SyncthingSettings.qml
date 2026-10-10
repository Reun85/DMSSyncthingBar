import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Config.js" as Config

// Settings page, shown inline in Settings -> Plugins.
//
// Every defaultValue is read from Config.DEFAULTS rather than restated, so the
// page and the runtime can never disagree about a default.
//
// Note for Nix users: when home-manager manages plugin settings,
// plugin_settings.json is a read-only symlink into the store and nothing typed
// here persists. Set values via
// programs.dank-material-shell.plugins.dankSyncthing.settings instead.
PluginSettings {
    id: root

    pluginId: "dankSyncthing"

    readonly property var defaults: Config.DEFAULTS

    component Heading: StyledText {
        width: root.width
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    component Note: StyledText {
        width: root.width
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.onSurfaceVariant
        wrapMode: Text.WordWrap
    }

    // ------------------------------------------------------------------ local
    Heading {
        text: qsTr("This machine")
    }

    Note {
        text: qsTr("Leave these blank to detect everything from Syncthing's own config.xml. Current status: %1").arg(SyncthingService.syncState.label + (SyncthingService.syncState.detail ? " — " + SyncthingService.syncState.detail : ""))
    }

    StringSetting {
        settingKey: "localUrl"
        label: qsTr("Base URL")
        description: qsTr("Blank: read the GUI address from config.xml, falling back to http://127.0.0.1:8384.")
        placeholder: "http://127.0.0.1:8384"
        defaultValue: root.defaults.localUrl
    }

    StringSetting {
        settingKey: "localApiKey"
        label: qsTr("API key")
        description: qsTr("Blank: read <apikey> from config.xml, so a regenerated key is picked up automatically.")
        placeholder: qsTr("auto-detected")
        defaultValue: root.defaults.localApiKey
    }

    StringSetting {
        settingKey: "localConfigPath"
        label: qsTr("config.xml path")
        description: qsTr("Blank: $XDG_CONFIG_HOME/syncthing/config.xml.")
        placeholder: "~/.config/syncthing/config.xml"
        defaultValue: root.defaults.localConfigPath
    }

    StringSetting {
        settingKey: "localLabel"
        label: qsTr("Label")
        description: qsTr("Name for this machine in the detail panel.")
        placeholder: root.defaults.localLabel
        defaultValue: root.defaults.localLabel
    }

    // ----------------------------------------------------------------- remote
    Heading {
        text: qsTr("Remote instance (optional)")
    }

    Note {
        text: qsTr("A second Syncthing you want quick access to — typically a server or NAS. Leave the URL blank and nothing about it appears anywhere: no button, no rows, no labels. It is opened in the browser, not polled; this machine's own Syncthing already reports whether the peer is connected and how far behind it is.")
    }

    StringSetting {
        settingKey: "serverUrl"
        label: qsTr("Remote web UI URL")
        description: qsTr("For example http://nas.local:8384. Blank disables all remote UI.")
        placeholder: qsTr("none — remote UI hidden")
        defaultValue: root.defaults.serverUrl
    }

    StringSetting {
        settingKey: "serverLabel"
        label: qsTr("Remote label")
        description: qsTr("Used on the button and to mark which peer device is the remote.")
        placeholder: root.defaults.serverLabel
        defaultValue: root.defaults.serverLabel
    }

    StringSetting {
        settingKey: "serverApiKey"
        label: qsTr("Remote API key")
        description: qsTr("Not currently used — reserved for polling the remote directly in a future version.")
        placeholder: qsTr("unused")
        defaultValue: root.defaults.serverApiKey
    }

    // ---------------------------------------------------------------- polling
    Heading {
        text: qsTr("Polling")
    }

    SliderSetting {
        settingKey: "pollActiveMs"
        label: qsTr("Interval while syncing or in error")
        description: qsTr("Faster updates while something is actually happening.")
        defaultValue: root.defaults.pollActiveMs
        minimum: 1000
        maximum: 10000
        unit: "ms"
        leftIcon: "sync"
    }

    SliderSetting {
        settingKey: "pollIdleMs"
        label: qsTr("Interval while idle")
        description: qsTr("Used when everything is up to date. The full folder scan runs at twice this interval.")
        defaultValue: root.defaults.pollIdleMs
        minimum: 5000
        maximum: 60000
        unit: "ms"
        leftIcon: "schedule"
    }

    SliderSetting {
        settingKey: "requestTimeoutS"
        label: qsTr("Request timeout")
        defaultValue: root.defaults.requestTimeoutS
        minimum: 1
        maximum: 30
        unit: "s"
        leftIcon: "timer"
    }

    StringSetting {
        settingKey: "peerDeviceId"
        label: qsTr("Limit to one peer device")
        description: qsTr("Device ID to track. Blank: every configured peer.")
        placeholder: qsTr("all peers")
        defaultValue: root.defaults.peerDeviceId
    }

    // -------------------------------------------------------------------- bar
    Heading {
        text: qsTr("Bar widget")
    }

    ToggleSetting {
        settingKey: "showPercentInBar"
        label: qsTr("Show percentage while syncing")
        defaultValue: root.defaults.showPercentInBar
    }

    ToggleSetting {
        settingKey: "showLabelInBar"
        label: qsTr("Show \"Syncthing\" label")
        description: qsTr("Off by default: the icon already carries the state.")
        defaultValue: root.defaults.showLabelInBar
    }

    ToggleSetting {
        settingKey: "hideWhenUpToDate"
        label: qsTr("Hide the pill when up to date")
        description: qsTr("Turns the widget into a pure exception indicator.")
        defaultValue: root.defaults.hideWhenUpToDate
    }

    // ---------------------------------------------------------------- desktop
    Heading {
        text: qsTr("Desktop widget")
    }

    ToggleSetting {
        settingKey: "desktopShowFolders"
        label: qsTr("List folders")
        defaultValue: root.defaults.desktopShowFolders
    }

    ToggleSetting {
        settingKey: "desktopShowDevices"
        label: qsTr("List devices")
        defaultValue: root.defaults.desktopShowDevices
    }

    SliderSetting {
        settingKey: "desktopOpacity"
        label: qsTr("Background opacity")
        defaultValue: root.defaults.desktopOpacity
        minimum: 0
        maximum: 100
        unit: "%"
    }

    // ---------------------------------------------------------- notifications
    Heading {
        text: qsTr("Notifications")
    }

    ToggleSetting {
        settingKey: "notifyOnError"
        label: qsTr("Toast when an error appears")
        description: qsTr("Fires once when the state turns to error, not on every poll.")
        defaultValue: root.defaults.notifyOnError
    }
}
