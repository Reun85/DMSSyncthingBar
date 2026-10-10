.pragma library

// Colour derivation for the status palette. Pure, dependency-free and free of
// QML imports, so tests/run.mjs can exercise it under node against DMS's own
// stock theme table.
//
// Colours are plain {r,g,b,a} objects in 0..1, which is what QML's `color` type
// decomposes to, so callers can pass Theme.* values straight in and assign the
// results straight back out.
//
// Why this file exists at all: every DMS theme is free to leave `error`,
// `warning` and `success` undefined, in which case Theme falls back to the
// Material defaults hardcoded in Common/Theme.qml. Those defaults are tuned for
// a dark neutral surface and are wrong in two ways that matter here:
//
//   1. As *text* on a light surface they are far too pale. `error` is #F2B8B5,
//      which on the Amber Light surface #fff8f2 is about 1.2:1 — invisible.
//   2. They can collide with the theme's own primary. Amber's primary is
//      #ffc107 and the fallback warning is #FF9800: 0.16 apart in RGB. The
//      "disconnected" and "syncing" states then render as the same colour,
//      which defeats the point of a status indicator.
//
// `readableOn` fixes the first, `separate` the second.

// Matches Theme.luminance (Common/Theme.qml) — deliberately the same cheap
// perceptual weighting rather than true WCAG relative luminance, so a colour
// judged readable here is judged the same way by the rest of the shell.
function luminance(c) {
    if (!c || c.r === undefined)
        return 0;
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
}

function rgba(r, g, b, a) {
    return {
        r: r,
        g: g,
        b: b,
        a: a === undefined ? 1 : a
    };
}

// Euclidean distance in RGB. Crude next to a real perceptual metric, but it is
// measuring "would these two read as the same colour in a 16px glyph", and at
// that size it agrees with the eye well enough. The 0.20 default threshold was
// picked by checking it against all 22 stock themes: it catches Amber's
// warning/primary collision and fires on nothing else.
function distance(a, b) {
    if (!a || !b || a.r === undefined || b.r === undefined)
        return 1;
    const dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
    return Math.sqrt(dr * dr + dg * dg + db * db);
}

// Matches Theme.blend.
function blend(c1, c2, r) {
    if (!c1 || c1.r === undefined)
        return c2;
    if (!c2 || c2.r === undefined)
        return c1;
    const a1 = c1.a === undefined ? 1 : c1.a;
    const a2 = c2.a === undefined ? 1 : c2.a;
    return rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, a1 * (1 - r) + a2 * r);
}

function withAlpha(c, a) {
    if (!c || c.r === undefined)
        return rgba(0, 0, 0, 0);
    return rgba(c.r, c.g, c.b, a);
}

var BLACK = rgba(0, 0, 0, 1);
var WHITE = rgba(1, 1, 1, 1);

// Default minimum luminance separation between a foreground and its background.
// Not a WCAG ratio: it is a delta on the same 0..1 scale `luminance` returns.
// 0.28 is about 3:1 for mid-tone pairs, i.e. the large-text threshold, which is
// the right bar for coloured status text that is never the only signal — the
// icon and the label always carry the state too.
var MIN_DELTA = 0.28;

// How far to push an unreadable foreground toward black or white. Enough to
// clear the threshold on every stock theme while keeping the hue recognisable:
// a pale pink error stays visibly red rather than going grey.
var CORRECTION = 0.45;

// Return `fg` if it reads against `bg`, else the nearest version of it that
// does. Pushing toward black on a light background and white on a dark one
// keeps the hue and moves only the lightness.
function readableOn(fg, bg, minDelta) {
    const need = minDelta === undefined ? MIN_DELTA : minDelta;
    if (!fg || fg.r === undefined)
        return fg;
    const bgLum = luminance(bg);
    if (Math.abs(luminance(fg) - bgLum) >= need)
        return fg;
    return blend(fg, bgLum > 0.5 ? BLACK : WHITE, CORRECTION);
}

// Pull `c` away from `from` when the two are too close to tell apart, by
// blending it toward `toward`. Used to keep the warning tone distinct from the
// theme's primary; `toward` is the error tone, so the result reads as "worse
// than syncing" rather than as an arbitrary third hue.
function separate(c, from, toward, minDist) {
    const need = minDist === undefined ? 0.20 : minDist;
    if (!c || c.r === undefined)
        return c;
    if (distance(c, from) >= need)
        return c;
    return blend(c, toward, 0.5);
}

// Pick a foreground for an arbitrary background. `onLight`/`onDark` are the
// theme's own text colours, so the result stays in-palette.
function on(bg, onLight, onDark) {
    return luminance(bg) > 0.5 ? onLight : onDark;
}

// Resolve one of Status.js's PRESENTATION colour tokens against a theme.
//
// `theme` is any object carrying the Theme properties this needs
// (primary, success, warning, error, surfaceVariantText, surfaceText), which in
// QML is the Theme singleton itself and in the fixtures is a plain object built
// from StockThemes.js. `bg` is the surface the result will be drawn on, used
// only when `asText` is set.
function statusColor(token, theme, bg, asText) {
    let c;
    switch (token) {
    case "success":
        c = theme.success;
        break;
    case "primary":
        c = theme.primary;
        break;
    case "warning":
        c = separate(theme.warning, theme.primary, theme.error);
        break;
    case "error":
        c = theme.error;
        break;
    case "onSurfaceVariant":
        c = theme.surfaceVariantText;
        break;
    default:
        c = theme.surfaceText;
        break;
    }
    // Accents sit on icons and meters, where a near-primary warning is still
    // distinguishable by shape and the pale-pink problem does not apply. Only
    // text needs the contrast guarantee.
    return asText ? readableOn(c, bg) : c;
}
