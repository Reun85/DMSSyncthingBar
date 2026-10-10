import QtQuick
import qs.Common
import "Palette.js" as P

// Binds the pure colour logic in Palette.js to the live Theme singleton.
//
// Deliberately not a `pragma Singleton`: QML registers a singleton once per
// engine, so editing one needs a full shell restart (see README, "Reload
// rules"). A presentation helper is the last thing that should drag that in, and
// three instances of a QtObject holding a handful of bindings costs nothing.
//
// Surfaces instantiate one as
// `readonly property SyncthingPalette pal: SyncthingPalette {}` and set
// `surface` if they draw on something other than the popout background.
//
// The name is not `Palette`: QtQuick already exports a Palette type
// (QQuickPalette), and a file-based type of the same name loses the collision
// silently — `Palette {}` resolves to Qt's, every lookup returns undefined, and
// the colours break with no error. qmllint catches it; the runtime does not.
QtObject {
    id: palette

    // The background the text colours are guaranteed to read against. Popouts
    // and the Control Center both sit on surfaceContainer; the desktop widget
    // overrides this because it composites over the wallpaper.
    property color surface: Theme.surfaceContainer

    // Palette.js works in plain {r,g,b,a} objects so it can run under node.
    // QML will not coerce those to `color`, so every result comes back through
    // here.
    function _c(o) {
        if (!o || o.r === undefined)
            return Qt.rgba(0, 0, 0, 0);
        return Qt.rgba(o.r, o.g, o.b, o.a === undefined ? 1 : o.a);
    }

    // --- accents: for icons, meters and borders ---------------------------
    readonly property color ok: Theme.success
    readonly property color busy: Theme.primary
    // Pulled off the theme's primary when the two would be indistinguishable.
    readonly property color warn: _c(P.separate(Theme.warning, Theme.primary, Theme.error))
    readonly property color danger: Theme.error
    readonly property color muted: Theme.surfaceVariantText

    // --- text ------------------------------------------------------------
    // Push a colour to something readable on `surface`, keeping its hue.
    function text(c) {
        return _c(P.readableOn(c, palette.surface));
    }

    // A foreground that reads on an arbitrary background, staying in-palette.
    function on(bg) {
        return _c(P.on(bg, Theme.surface, Theme.surfaceText));
    }

    // --- status tokens ---------------------------------------------------
    // `token` is one of the colour names declared in Status.js's PRESENTATION
    // table, which stays the single source of truth for status presentation.
    function tone(token) {
        return _c(P.statusColor(token, Theme, palette.surface, false));
    }

    function toneText(token) {
        return _c(P.statusColor(token, Theme, palette.surface, true));
    }

    // Theme.withAlpha, exposed here so surfaces have one place to reach for
    // colour instead of open-coding Qt.rgba(c.r, c.g, c.b, a).
    function tint(c, a) {
        return Theme.withAlpha(c, a);
    }
}
