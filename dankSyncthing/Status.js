.pragma library

// Pure state derivation and formatting. No QML imports, so this file can also be
// exercised by the node fixtures in tests/ (which strip the .pragma line).

// Folder states Syncthing reports while it is actively doing work.
var BUSY_STATES = ["syncing", "scanning", "sync-preparing", "cleaning", "sync-waiting", "scan-waiting"];

// Icon + Theme colour token per status kind. The token name is resolved against
// the Theme singleton by the QML side; every one listed here was verified to
// exist in Common/Theme.qml (1.6.2).
var PRESENTATION = {
    uptodate:     { icon: "cloud_done",    color: "success",          label: "Up to date" },
    syncing:      { icon: "sync",          color: "primary",          label: "Syncing" },
    disconnected: { icon: "cloud_off",     color: "warning",          label: "Disconnected" },
    error:        { icon: "sync_problem",  color: "error",            label: "Error" },
    paused:       { icon: "pause_circle",  color: "onSurfaceVariant", label: "Paused" },
    unreachable:  { icon: "cloud_off",     color: "onSurfaceVariant", label: "Syncthing not running" },
    unconfigured: { icon: "help",          color: "onSurfaceVariant", label: "Not configured" },
    unknown:      { icon: "cloud_queue",   color: "onSurfaceVariant", label: "Checking…" }
};

function presentation(kind) {
    return PRESENTATION[kind] || PRESENTATION.unknown;
}

// Map a failed poll to a status kind. `reason` comes from st-poll.sh.
function kindForReason(reason) {
    switch (reason) {
    case "no-config":
    case "no-apikey":
    case "bad-apikey":
    case "no-curl":
    case "no-jq":
        return "unconfigured";
    case "unreachable":
    case "http-error":
    default:
        return "unreachable";
    }
}

function _num(v, fallback) {
    return (typeof v === "number" && isFinite(v)) ? v : fallback;
}

// Build the view model from a poll envelope.
//
// `raw` is the parsed output of st-poll.sh. `prev` is the previous derived state,
// used so that a cheap "summary" poll keeps the folder/device detail gathered by
// the last "full" poll instead of blanking the UI every other tick.
function derive(raw, prev) {
    prev = prev || {};

    if (!raw || raw.ok !== true) {
        var reason = raw ? raw.reason : "unreachable";
        var kind = kindForReason(reason);
        return {
            kind: kind,
            label: presentation(kind).label,
            detail: (raw && raw.detail) ? raw.detail : "",
            reason: reason || "unreachable",
            percent: -1,
            ok: false,
            base: prev.base || "",
            folders: [],
            devices: [],
            errors: [],
            needBytes: 0,
            changedAt: null
        };
    }

    var folders = _folders(raw, prev);
    var devices = _devices(raw, prev);
    var errors = _systemErrors(raw);

    var completion = raw.completion || {};
    var percent = _num(completion.completion, -1);
    var needBytes = _num(completion.needBytes, 0);

    // Folder-level problems count as errors even when /rest/system/error is clean.
    var folderErrors = 0;
    for (var i = 0; i < folders.length; i++)
        folderErrors += folders[i].errorCount;

    var configuredPeers = devices.length;
    var connectedPeers = 0;
    for (var d = 0; d < devices.length; d++)
        if (devices[d].connected)
            connectedPeers++;

    var busy = false;
    var allPaused = folders.length > 0;
    for (var f = 0; f < folders.length; f++) {
        if (folders[f].busy)
            busy = true;
        if (!folders[f].paused)
            allPaused = false;
    }
    if (needBytes > 0)
        busy = true;
    for (var p = 0; p < devices.length; p++)
        if (devices[p].connected && devices[p].percent >= 0 && devices[p].percent < 100)
            busy = true;

    // Precedence, highest first. `disconnected` deliberately outranks `syncing`:
    // if the peer is gone, that is the actionable fact, not the pending bytes.
    var kind;
    if (errors.length > 0 || folderErrors > 0)
        kind = "error";
    else if (configuredPeers > 0 && connectedPeers === 0)
        kind = "disconnected";
    else if (busy)
        kind = "syncing";
    else if (allPaused)
        kind = "paused";
    else
        kind = "uptodate";

    return {
        kind: kind,
        label: presentation(kind).label,
        detail: _detail(kind, folders, devices, errors, folderErrors, needBytes, percent),
        reason: "",
        percent: percent,
        ok: true,
        base: raw.base || prev.base || "",
        version: (raw.version && raw.version.version) || prev.version || "",
        folders: folders,
        devices: devices,
        errors: errors,
        needBytes: needBytes,
        changedAt: _latestChange(folders)
    };
}

function _folders(raw, prev) {
    // A summary poll carries no folder detail; keep what the last full poll found.
    if (!raw.folders || !raw.folders.length)
        return prev.folders || [];

    var out = [];
    for (var i = 0; i < raw.folders.length; i++) {
        var f = raw.folders[i];
        var st = f.status || {};
        var state = st.state || (f.paused ? "paused" : "unknown");
        var global = _num(st.globalBytes, 0);
        var need = _num(st.needBytes, 0);
        var errorCount = _num(st.errors, 0) + _num(st.pullErrors, 0);

        // Percent complete locally. Syncthing reports needBytes against the
        // global size, so an empty folder is complete rather than 0 %.
        var pct = global > 0 ? Math.max(0, Math.min(100, (1 - need / global) * 100)) : 100;

        out.push({
            id: f.id,
            label: f.label || f.id,
            paused: !!f.paused,
            state: state,
            busy: !f.paused && BUSY_STATES.indexOf(state) !== -1,
            errorCount: errorCount,
            error: st.error || "",
            needBytes: need,
            needFiles: _num(st.needFiles, 0),
            globalBytes: global,
            percent: pct,
            stateChanged: st.stateChanged || null
        });
    }
    out.sort(function (a, b) {
        // Problems first, then anything still working, then alphabetical.
        var rank = function (x) { return x.errorCount > 0 ? 0 : (x.busy ? 1 : 2); };
        if (rank(a) !== rank(b))
            return rank(a) - rank(b);
        return a.label.localeCompare(b.label);
    });
    return out;
}

function _devices(raw, prev) {
    var conns = (raw.connections && raw.connections.connections) || null;
    var cfgDevices = raw.configDevices || null;

    // Summary polls carry connections but not the device roster; merge the fresh
    // connection state onto the roster the last full poll established.
    if (!cfgDevices) {
        var carried = prev.devices || [];
        if (!conns)
            return carried;
        var merged = [];
        for (var c = 0; c < carried.length; c++) {
            var copy = {};
            for (var key in carried[c])
                copy[key] = carried[c][key];
            // Derive connectivity from the live map unconditionally: a device
            // missing from /rest/system/connections is not connected, so
            // keeping the carried flag would leave a stale "connected".
            var live = conns[copy.deviceID];
            copy.connected = !!(live && live.connected);
            copy.address = (live && live.address) || "";
            merged.push(copy);
        }
        return merged;
    }

    var stats = raw.deviceStats || {};
    var completions = {};
    for (var i = 0; i < (raw.devices || []).length; i++) {
        var entry = raw.devices[i];
        completions[entry.deviceID] = entry.completion || {};
    }

    var out = [];
    for (var d = 0; d < cfgDevices.length; d++) {
        var dev = cfgDevices[d];
        if (dev.deviceID === raw.selfId)
            continue;

        var conn = (conns && conns[dev.deviceID]) || {};
        var comp = completions[dev.deviceID] || {};
        var seen = stats[dev.deviceID] ? stats[dev.deviceID].lastSeen : null;

        out.push({
            deviceID: dev.deviceID,
            shortId: dev.deviceID ? dev.deviceID.split("-")[0] : "",
            name: dev.name || (dev.deviceID ? dev.deviceID.split("-")[0] : "unknown"),
            paused: !!dev.paused,
            connected: !!conn.connected,
            address: conn.address || "",
            percent: _num(comp.completion, -1),
            needBytes: _num(comp.needBytes, 0),
            lastSeen: _isEpochZero(seen) ? null : seen
        });
    }
    out.sort(function (a, b) {
        if (a.connected !== b.connected)
            return a.connected ? 1 : -1;   // problems first
        return a.name.localeCompare(b.name);
    });
    return out;
}

// Syncthing reports "never seen" as the Unix epoch rather than null.
function _isEpochZero(ts) {
    if (!ts)
        return true;
    return String(ts).indexOf("1970-01-01") === 0;
}

function _systemErrors(raw) {
    var errs = (raw.systemError && raw.systemError.errors) || [];
    var out = [];
    for (var i = 0; i < errs.length; i++) {
        var e = errs[i];
        out.push({
            when: e.when || null,
            message: (typeof e === "string") ? e : (e.message || String(e))
        });
    }
    return out;
}

function _latestChange(folders) {
    var latest = null;
    for (var i = 0; i < folders.length; i++) {
        var ts = folders[i].stateChanged;
        if (!ts)
            continue;
        if (!latest || ts > latest)
            latest = ts;
    }
    return latest;
}

// One line of context under the headline status.
function _detail(kind, folders, devices, errors, folderErrors, needBytes, percent) {
    switch (kind) {
    case "error":
        if (errors.length > 0)
            return errors[0].message;
        for (var i = 0; i < folders.length; i++)
            if (folders[i].errorCount > 0)
                return folders[i].label + ": " + plural(folders[i].errorCount, "error");
        return plural(folderErrors, "error");
    case "disconnected":
        if (devices.length === 1)
            return devices[0].name + " not connected" +
                   (devices[0].lastSeen ? " · last seen " + formatAge(devices[0].lastSeen) : "");
        return "No peers connected";
    case "syncing":
        var parts = [];
        if (percent >= 0 && percent < 100)
            parts.push(Math.floor(percent) + "%");
        if (needBytes > 0)
            parts.push(formatBytes(needBytes) + " remaining");
        for (var f = 0; f < folders.length; f++) {
            if (folders[f].busy) {
                parts.push(folders[f].label);
                break;
            }
        }
        return parts.join(" · ");
    case "paused":
        return plural(folders.length, "folder") + " paused";
    case "uptodate":
        var conn = 0;
        for (var d = 0; d < devices.length; d++)
            if (devices[d].connected)
                conn++;
        var bits = [plural(folders.length, "folder")];
        if (devices.length > 0)
            bits.push(conn + "/" + devices.length + " devices");
        return bits.join(" · ");
    default:
        return "";
    }
}

function plural(n, word) {
    return n + " " + word + (n === 1 ? "" : "s");
}

function formatBytes(bytes) {
    if (!bytes || bytes <= 0)
        return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    var v = bytes;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    return (v >= 10 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
}

// Compact relative age, e.g. "3m", "2h", "4d". `now` is injectable for tests.
function formatAge(timestamp, now) {
    if (!timestamp)
        return "";
    var then = new Date(timestamp).getTime();
    if (!isFinite(then))
        return "";
    var secs = Math.floor(((now || Date.now()) - then) / 1000);
    if (secs < 0) secs = 0;
    if (secs < 60)    return secs + "s ago";
    if (secs < 3600)  return Math.floor(secs / 60) + "m ago";
    if (secs < 86400) return Math.floor(secs / 3600) + "h ago";
    return Math.floor(secs / 86400) + "d ago";
}

// Bar pill text: short by design, the popout carries the detail.
function pillText(state, cfg) {
    if (!state)
        return "";
    var bits = [];
    if (cfg.showLabelInBar)
        bits.push("Syncthing");
    if (cfg.showPercentInBar && state.kind === "syncing" && state.percent >= 0 && state.percent < 100)
        bits.push(Math.floor(state.percent) + "%");
    else if (state.kind === "error") {
        var n = state.errors.length;
        for (var i = 0; i < state.folders.length; i++)
            n += state.folders[i].errorCount;
        if (n > 0)
            bits.push(String(n));
    }
    return bits.join(" ");
}
