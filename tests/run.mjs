// Fixture tests for the pure logic modules.
//
// Status.js and Config.js are QML JS libraries: plain JavaScript apart from the
// leading `.pragma library` line, which node cannot parse. Strip it and import
// the rest as an ES module.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

async function load(file, exports) {
    const src = readFileSync(join(root, "dankSyncthing", file), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    const mod = src + "\nexport { " + exports.join(", ") + " };";
    const url = "data:text/javascript;base64," + Buffer.from(mod).toString("base64");
    return import(url);
}

const Status = await load("Status.js", [
    "derive", "presentation", "kindForReason", "formatBytes", "formatAge", "pillText", "plural"
]);
const Config = await load("Config.js", [
    "DEFAULTS", "resolve", "hasServer", "serverUrl", "serverHost", "pollArgs"
]);
const Palette = await load("Palette.js", [
    "luminance", "distance", "blend", "withAlpha", "readableOn", "separate", "on",
    "statusColor", "MIN_DELTA"
]);

let passed = 0;
const failures = [];

function check(name, actual, expected) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    if (a === e) passed++;
    else failures.push(`${name}\n    expected ${e}\n    actual   ${a}`);
}

function ok(name, cond) {
    check(name, !!cond, true);
}

// --- envelope builders ------------------------------------------------------
const SELF = "SELF111-AAAAAAA";
const PEER = "PEER222-BBBBBBB";

function folder(id, over = {}) {
    return {
        id, label: id, paused: false, type: "sendreceive",
        status: {
            state: "idle", stateChanged: "2026-10-10T12:00:00+02:00",
            needBytes: 0, needFiles: 0, errors: 0, pullErrors: 0,
            globalBytes: 1000, localBytes: 1000, ...over
        }
    };
}

function envelope(over = {}) {
    return {
        ok: true, instance: "local", mode: "full", base: "http://127.0.0.1:8384",
        selfId: SELF,
        version: { version: "v2.1.3" },
        connections: { connections: { [PEER]: { connected: true, address: "10.0.0.2:22000" } } },
        systemError: { errors: null },
        completion: { completion: 100, needBytes: 0, globalBytes: 1000 },
        deviceStats: { [PEER]: { lastSeen: "2026-10-10T13:00:00+02:00" } },
        folders: [folder("notes"), folder("projects")],
        devices: [{ deviceID: PEER, completion: { completion: 100, needBytes: 0 } }],
        configDevices: [
            { deviceID: SELF, name: "This PC" },
            { deviceID: PEER, name: "syncthing-server" }
        ],
        ...over
    };
}

// --- kind precedence --------------------------------------------------------
check("healthy -> uptodate", Status.derive(envelope()).kind, "uptodate");

check("folder pullErrors -> error",
    Status.derive(envelope({ folders: [folder("notes", { pullErrors: 2 })] })).kind, "error");

check("folder state error -> error",
    Status.derive(envelope({ folders: [folder("notes", { state: "error", errors: 1 })] })).kind, "error");

check("system error -> error",
    Status.derive(envelope({ systemError: { errors: [{ message: "disk full", when: "x" }] } })).kind, "error");

check("peer down -> disconnected",
    Status.derive(envelope({ connections: { connections: {} } })).kind, "disconnected");

check("busy folder -> syncing",
    Status.derive(envelope({ folders: [folder("notes", { state: "syncing", needBytes: 500 })] })).kind, "syncing");

check("aggregate needBytes -> syncing",
    Status.derive(envelope({ completion: { completion: 42, needBytes: 500, globalBytes: 1000 } })).kind, "syncing");

check("peer behind -> syncing",
    Status.derive(envelope({ devices: [{ deviceID: PEER, completion: { completion: 42, needBytes: 99 } }] })).kind,
    "syncing");

check("all folders paused -> paused",
    Status.derive(envelope({
        folders: [{ ...folder("notes"), paused: true }, { ...folder("projects"), paused: true }]
    })).kind, "paused");

// The precedence case that matters most: a peer being gone outranks pending work.
check("disconnected outranks syncing",
    Status.derive(envelope({
        connections: { connections: {} },
        folders: [folder("notes", { state: "syncing", needBytes: 500 })],
        completion: { completion: 10, needBytes: 500, globalBytes: 1000 }
    })).kind, "disconnected");

// ...but a real error outranks even a disconnect.
check("error outranks disconnected",
    Status.derive(envelope({
        connections: { connections: {} },
        folders: [folder("notes", { pullErrors: 1 })]
    })).kind, "error");

// --- failure envelopes ------------------------------------------------------
for (const [reason, kind] of [
    ["no-config", "unconfigured"], ["no-apikey", "unconfigured"], ["bad-apikey", "unconfigured"],
    ["no-curl", "unconfigured"], ["no-jq", "unconfigured"],
    ["unreachable", "unreachable"], ["http-error", "unreachable"]
]) {
    check(`reason ${reason} -> ${kind}`, Status.derive({ ok: false, reason }).kind, kind);
}
check("null envelope -> unreachable", Status.derive(null).kind, "unreachable");
ok("failed derive has empty folders", Status.derive({ ok: false, reason: "unreachable" }).folders.length === 0);

// --- no devices configured --------------------------------------------------
check("no peers configured is not disconnected",
    Status.derive(envelope({ configDevices: [{ deviceID: SELF, name: "This PC" }], devices: [] })).kind,
    "uptodate");

// --- self device excluded ---------------------------------------------------
check("self excluded from devices", Status.derive(envelope()).devices.map(d => d.name), ["syncthing-server"]);

// --- summary poll carries prior detail forward ------------------------------
const full = Status.derive(envelope());
const summary = Status.derive({
    ok: true, instance: "local", mode: "summary", base: "http://127.0.0.1:8384",
    version: { version: "v2.1.3" },
    connections: { connections: { [PEER]: { connected: true, address: "10.0.0.2:22000" } } },
    systemError: { errors: null },
    completion: { completion: 100, needBytes: 0, globalBytes: 1000 }
}, full);
check("summary keeps folders", summary.folders.length, 2);
check("summary keeps devices", summary.devices.map(d => d.name), ["syncthing-server"]);
check("summary applies live disconnect",
    Status.derive({
        ok: true, mode: "summary", base: "x", version: { version: "v2.1.3" },
        connections: { connections: {} }, systemError: { errors: null },
        completion: { completion: 100, needBytes: 0 }
    }, full).kind, "disconnected");

// --- ordering: problems first -----------------------------------------------
check("error folder sorts first",
    Status.derive(envelope({
        folders: [folder("alpha"), folder("zeta", { pullErrors: 1 })]
    })).folders.map(f => f.id), ["zeta", "alpha"]);

check("disconnected device sorts first",
    Status.derive(envelope({
        connections: { connections: { [PEER]: { connected: false } } },
        configDevices: [
            { deviceID: SELF, name: "This PC" },
            { deviceID: PEER, name: "bbb" },
            { deviceID: "PEER333-CCC", name: "aaa" }
        ],
        devices: []
    })).devices.map(d => d.name), ["aaa", "bbb"]);

// --- percent + epoch handling -----------------------------------------------
check("empty folder is 100%", Status.derive(envelope({
    folders: [folder("empty", { globalBytes: 0, needBytes: 0 })]
})).folders[0].percent, 100);

check("half-synced folder percent", Status.derive(envelope({
    folders: [folder("half", { globalBytes: 1000, needBytes: 500, state: "syncing" })]
})).folders[0].percent, 50);

check("epoch lastSeen becomes null", Status.derive(envelope({
    deviceStats: { [PEER]: { lastSeen: "1970-01-01T01:00:00+01:00" } }
})).devices[0].lastSeen, null);

// --- presentation -----------------------------------------------------------
for (const kind of ["uptodate", "syncing", "disconnected", "error", "paused", "unreachable", "unconfigured"]) {
    ok(`presentation(${kind}) has icon+color`,
        Status.presentation(kind).icon && Status.presentation(kind).color);
}
check("unknown kind falls back", Status.presentation("nonsense").icon, "cloud_queue");

// --- formatting -------------------------------------------------------------
check("formatBytes 0", Status.formatBytes(0), "0 B");
check("formatBytes 512", Status.formatBytes(512), "512 B");
check("formatBytes 1536", Status.formatBytes(1536), "1.5 KB");
check("formatBytes 328000207", Status.formatBytes(328000207), "313 MB");
check("plural singular", Status.plural(1, "error"), "1 error");
check("plural plural", Status.plural(3, "error"), "3 errors");

const NOW = Date.parse("2026-10-10T13:00:00+02:00");
check("formatAge seconds", Status.formatAge("2026-10-10T12:59:30+02:00", NOW), "30s ago");
check("formatAge minutes", Status.formatAge("2026-10-10T12:57:00+02:00", NOW), "3m ago");
check("formatAge hours", Status.formatAge("2026-10-10T09:00:00+02:00", NOW), "4h ago");
check("formatAge days", Status.formatAge("2026-10-08T13:00:00+02:00", NOW), "2d ago");
check("formatAge empty", Status.formatAge(null, NOW), "");

// --- pill text --------------------------------------------------------------
const cfgDefault = Config.resolve({});
check("pill shows percent while syncing",
    Status.pillText(Status.derive(envelope({
        folders: [folder("n", { state: "syncing", needBytes: 500 })],
        completion: { completion: 42, needBytes: 500, globalBytes: 1000 }
    })), cfgDefault), "42%");
check("pill empty when up to date", Status.pillText(Status.derive(envelope()), cfgDefault), "");
check("pill shows error count",
    Status.pillText(Status.derive(envelope({ folders: [folder("n", { pullErrors: 2 })] })), cfgDefault), "2");
check("pill respects showPercentInBar=false",
    Status.pillText(Status.derive(envelope({
        folders: [folder("n", { state: "syncing", needBytes: 500 })],
        completion: { completion: 42, needBytes: 500, globalBytes: 1000 }
    })), Config.resolve({ showPercentInBar: false })), "");

// --- detail lines -----------------------------------------------------------
check("detail names erroring folder",
    Status.derive(envelope({ folders: [folder("school", { pullErrors: 2 })] })).detail,
    "school: 2 errors");
check("detail surfaces system error message",
    Status.derive(envelope({ systemError: { errors: [{ message: "disk full" }] } })).detail,
    "disk full");
ok("detail for disconnect names the peer",
    Status.derive(envelope({ connections: { connections: {} } })).detail.startsWith("syncthing-server not connected"));
check("detail when healthy", Status.derive(envelope()).detail, "2 folders · 1/1 devices");

// --- Config -----------------------------------------------------------------
check("remote disabled by default", Config.hasServer(Config.resolve({})), false);
check("remote enabled when set", Config.hasServer(Config.resolve({ serverUrl: "http://docker:8384" })), true);
check("blank remote stays disabled", Config.hasServer(Config.resolve({ serverUrl: "   " })), false);
check("default serverUrl is empty", Config.DEFAULTS.serverUrl, "");
check("serverUrl normalises scheme", Config.serverUrl(Config.resolve({ serverUrl: "docker:8384" })), "http://docker:8384");
check("serverUrl strips trailing slash", Config.serverUrl(Config.resolve({ serverUrl: "http://docker:8384/" })), "http://docker:8384");
check("serverUrl empty when unset", Config.serverUrl(Config.resolve({})), "");
check("serverHost extracted", Config.serverHost(Config.resolve({ serverUrl: "http://docker:8384" })), "docker");
check("https preserved", Config.serverUrl(Config.resolve({ serverUrl: "https://s.example:8443" })), "https://s.example:8443");

check("empty string falls back to default", Config.resolve({ localLabel: "" }).localLabel, "This machine");
check("null falls back to default", Config.resolve({ pollIdleMs: null }).pollIdleMs, 10000);
check("value overrides default", Config.resolve({ pollIdleMs: 3000 }).pollIdleMs, 3000);
check("false is respected, not treated as unset", Config.resolve({ showPercentInBar: false }).showPercentInBar, false);
check("zero is respected", Config.resolve({ desktopOpacity: 0 }).desktopOpacity, 0);
check("unknown keys ignored", Config.resolve({ bogus: 1 }).bogus, undefined);
check("resolve(undefined) is all defaults", Config.resolve(undefined).localLabel, "This machine");

check("pollArgs omits blanks", Config.pollArgs("/p/st.sh", Config.resolve({}), "summary"),
    ["/p/st.sh", "--mode", "summary", "--timeout", "5"]);
check("pollArgs includes overrides",
    Config.pollArgs("/p/st.sh", Config.resolve({ localUrl: "http://h:1", localApiKey: "k", peerDeviceId: "D" }), "full"),
    ["/p/st.sh", "--mode", "full", "--base", "http://h:1", "--key", "k", "--peer", "D", "--timeout", "5"]);

// A key containing shell metacharacters stays a single argv element.
const nasty = Config.pollArgs("/p/st.sh", Config.resolve({ localApiKey: "a'; rm -rf /; #" }), "summary");
check("hostile key stays one argv element", nasty[nasty.indexOf("--key") + 1], "a'; rm -rf /; #");

// --- regressions -------------------------------------------------------------
// The summary tier deliberately omits `version` (it never changes between
// polls), so derive must not choke on its absence and should keep the last
// known value.
const summaryNoVersion = {
    ok: true, instance: "local", mode: "summary", base: "http://127.0.0.1:8384",
    connections: { connections: { [PEER]: { connected: true, address: "10.0.0.2:22000" } } },
    systemError: { errors: null },
    completion: { completion: 100, needBytes: 0, globalBytes: 1000 }
};
check("summary without version does not throw", Status.derive(summaryNoVersion).kind, "uptodate");
check("summary carries version forward", Status.derive(summaryNoVersion, full).version, "v2.1.3");

// selfId must exclude this machine from the device list, or the shell's own
// device is reported as an unreachable peer. Regression: an empty selfId.
check("empty selfId leaves self in the list (documents the failure mode)",
    Status.derive(envelope({ selfId: "" })).devices.length, 2);
check("correct selfId excludes self",
    Status.derive(envelope()).devices.length, 1);

// QQuickItem already defines `state`; the service exposes `syncState` instead.
// Nothing to assert in JS, but derive must return a plain object either way.
ok("derive returns an object with a kind", typeof Status.derive(envelope()).kind === "string");

// --- contrast across every stock theme --------------------------------------
//
// The bug this guards against: a colour token is only ever correct against the
// background it was designed for. DankButton's textColor defaults to
// Theme.buttonText, which pairs with Theme.buttonBg — override the background
// alone and on stock Amber dark you get #000000 text on #2e2921.
//
// The 81 fixtures above could not have caught that, because contrast was never
// expressed as data. These checks read DMS's own theme table and assert every
// foreground the plugin emits against the background it is actually drawn on.

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";

function dmsRoot() {
    if (process.env.DMS_SHELL_DIR && existsSync(process.env.DMS_SHELL_DIR))
        return process.env.DMS_SHELL_DIR;
    // st-dms-root is devenv.nix's single source of truth for this lookup.
    try {
        const out = execFileSync("st-dms-root", { encoding: "utf8" }).trim();
        if (out && existsSync(out)) return out;
    } catch {
        // not in the dev shell, or DMS not installed
    }
    return null;
}

function hex(c) {
    const h = c.replace("#", "");
    const n = h.length === 3 ? h.split("").map(x => x + x).join("") : h;
    return {
        r: parseInt(n.slice(0, 2), 16) / 255,
        g: parseInt(n.slice(2, 4), 16) / 255,
        b: parseInt(n.slice(4, 6), 16) / 255,
        a: 1
    };
}

// Theme.qml:432-437 — the fallbacks applied when a theme omits these, which is
// all but one of the stock themes. They are the reason the plugin needs
// Palette.js at all.
const FALLBACK = { error: "#F2B8B5", warning: "#FF9800", success: "#4CAF50" };

function themeObject(raw) {
    const t = {};
    for (const k of ["primary", "primaryText", "surface", "surfaceText", "surfaceVariant",
                     "surfaceVariantText", "surfaceContainer", "surfaceContainerHigh", "outline"])
        t[k] = hex(raw[k]);
    for (const k of ["error", "warning", "success"])
        t[k] = hex(raw[k] || FALLBACK[k]);
    // Theme.qml:617-641, default buttonColorMode branch.
    t.buttonBg = t.primary;
    t.buttonText = t.primaryText;
    return t;
}

function delta(a, b) {
    return Math.abs(Palette.luminance(a) - Palette.luminance(b));
}

const shellRoot = dmsRoot();
if (!shellRoot) {
    console.log("· contrast suite skipped: DMS shell not found (set DMS_SHELL_DIR to run it)");
} else {
    const stock = await (async () => {
        const src = readFileSync(join(shellRoot, "Common", "StockThemes.js"), "utf8");
        const mod = src + "\nexport { StockThemes };";
        const url = "data:text/javascript;base64," + Buffer.from(mod).toString("base64");
        return (await import(url)).StockThemes;
    })();

    // Every token Status.js can name, as it is used: the first four land on
    // icons and meters, and all of them can reach text via pal.text().
    const TOKENS = ["success", "primary", "warning", "error", "onSurfaceVariant"];

    let themeCount = 0;
    for (const mode of ["DARK", "LIGHT"]) {
        for (const [name, raw] of Object.entries(stock[mode])) {
            const t = themeObject(raw);
            const bg = t.surfaceContainer;
            const label = `${name} ${mode.toLowerCase()}`;
            themeCount++;

            // 1. Status text is readable on the panel it is drawn on.
            for (const token of TOKENS) {
                const fg = Palette.statusColor(token, t, bg, true);
                ok(`${label}: ${token} as text reads on surfaceContainer`,
                    delta(fg, bg) >= Palette.MIN_DELTA - 1e-9);
            }

            // 2. The neutral text tokens the cards use.
            ok(`${label}: surfaceText reads on surfaceContainer`,
                delta(t.surfaceText, bg) >= Palette.MIN_DELTA);
            ok(`${label}: surfaceVariantText reads on surfaceContainer`,
                delta(t.surfaceVariantText, bg) >= 0.20);

            // 3. The warning accent stays distinguishable from primary, so
            //    "disconnected" and "syncing" never render as the same colour.
            //    Amber is the theme that fails this without separate().
            const warn = Palette.statusColor("warning", t, bg, false);
            ok(`${label}: warning accent is distinct from primary`,
                Palette.distance(warn, t.primary) >= 0.20 - 1e-9);

            // 4. DMS's own button pair, as a canary: if this ever stops being
            //    self-consistent, leaving DankButton's defaults alone is no
            //    longer the safe choice.
            ok(`${label}: DMS buttonBg/buttonText are a readable pair`,
                delta(t.buttonText, t.buttonBg) >= Palette.MIN_DELTA);

            // 5. The regression itself. The armed Restart button tints the
            //    surface 22% toward the danger tone; its label must read
            //    against that composite, not against buttonBg.
            const armedBg = Palette.blend(bg, t.error, 0.22);
            const armedFg = Palette.readableOn(t.error, bg);
            ok(`${label}: armed Restart label reads on its tinted background`,
                delta(armedFg, armedBg) >= 0.20);

            // 6. And the shape of the original bug: buttonText on a surface
            //    background must be caught as unreadable somewhere. This
            //    asserts the failure is real, so the suite cannot pass by
            //    accident on a theme where the pairing happens to work.
            if (name === "amber" && mode === "DARK") {
                // #000000 on #2e2921 is a luminance delta of about 0.16,
                // roughly 1.5:1. Asserting it fails the plugin's own bar keeps
                // this suite honest: it cannot pass by accident on a theme
                // where the bad pairing happens to be readable anyway.
                ok("amber dark: the original pairing is genuinely unreadable",
                    delta(t.buttonText, t.surfaceContainerHigh) < Palette.MIN_DELTA);
            }
        }
    }
    ok("contrast suite covered both modes of every stock theme", themeCount === 20);
}

// --- report -----------------------------------------------------------------
if (failures.length) {
    console.error(`\n${failures.length} FAILED, ${passed} passed\n`);
    for (const f of failures) console.error("  ✗ " + f + "\n");
    process.exit(1);
}
console.log(`✓ ${passed} checks passed`);
