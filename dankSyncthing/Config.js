.pragma library

// Single source of truth for plugin settings.
//
// Every surface (bar widget, Control Center card, desktop widget, daemon) is a
// separate QML object with its own `pluginData`, so defaults written inline as
// `pluginData.foo || "x"` in four files inevitably drift apart. They live here
// instead, and SyncthingSettings.qml reads its `defaultValue`s from this table
// rather than restating them.
var DEFAULTS = {
    // --- Local instance (the one that is actually polled) -------------------
    localUrl: "",            // "" = auto-detect from config.xml
    localConfigPath: "",     // "" = $XDG_CONFIG_HOME/syncthing/config.xml
    localApiKey: "",         // "" = read <apikey> from config.xml
    localLabel: "This machine",

    // --- Remote/"global" instance (optional, link-only) --------------------
    // No default on purpose: unset means disabled, and nothing about a remote
    // instance appears in any surface. Machine-specific values belong in
    // home-manager, not in the plugin.
    serverUrl: "",
    serverApiKey: "",
    serverLabel: "Server",

    // --- Polling ----------------------------------------------------------
    peerDeviceId: "",        // "" = every configured peer
    pollIdleMs: 10000,
    pollActiveMs: 2000,
    requestTimeoutS: 5,

    // --- Bar pill ---------------------------------------------------------
    showPercentInBar: true,
    showLabelInBar: false,
    hideWhenUpToDate: false,

    // --- Desktop widget ---------------------------------------------------
    desktopShowFolders: true,
    desktopShowDevices: true,
    desktopOpacity: 50,

    // --- Notifications ----------------------------------------------------
    notifyOnError: true
};

// Merge stored settings over the defaults.
//
// An empty string counts as "unset" so that clearing a field in the settings UI
// restores the default instead of producing, say, a base URL of "".
function resolve(pluginData) {
    var cfg = {};
    for (var key in DEFAULTS)
        cfg[key] = DEFAULTS[key];

    if (!pluginData)
        return cfg;

    for (var k in DEFAULTS) {
        var v = pluginData[k];
        if (v === undefined || v === null)
            continue;
        if (typeof v === "string" && v.trim() === "")
            continue;
        cfg[k] = v;
    }
    return cfg;
}

// True when the user has configured a remote instance. Gates every piece of
// remote UI; when false no button, row or label for it is rendered.
function hasServer(cfg) {
    return !!(cfg && typeof cfg.serverUrl === "string" && cfg.serverUrl.trim() !== "");
}

// Normalised remote URL, or "" when disabled.
function serverUrl(cfg) {
    if (!hasServer(cfg))
        return "";
    var url = cfg.serverUrl.trim();
    if (!/^https?:\/\//.test(url))
        url = "http://" + url;
    return url.replace(/\/+$/, "");
}

// Hostname of the configured remote, used to mark which peer device is "the
// server" in the device list. "" when disabled or unparseable.
function serverHost(cfg) {
    var url = serverUrl(cfg);
    if (!url)
        return "";
    var m = url.match(/^https?:\/\/([^/:]+)/);
    return m ? m[1] : "";
}

// Argument vector for scripts/st-poll.sh. Blank settings are omitted so the
// script's own auto-detection applies. Passed as argv, never interpolated into
// `sh -c`, so a URL or key containing shell metacharacters cannot escape.
function pollArgs(scriptPath, cfg, mode) {
    var args = [scriptPath, "--mode", mode];
    if (cfg.localUrl)        args.push("--base", cfg.localUrl);
    if (cfg.localApiKey)     args.push("--key", cfg.localApiKey);
    if (cfg.localConfigPath) args.push("--config", cfg.localConfigPath);
    if (cfg.peerDeviceId)    args.push("--peer", cfg.peerDeviceId);
    if (cfg.requestTimeoutS) args.push("--timeout", String(cfg.requestTimeoutS));
    return args;
}
