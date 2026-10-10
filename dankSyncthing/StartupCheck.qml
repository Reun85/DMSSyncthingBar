import QtQuick
import qs.Common

// Dependency gate. Runs before the plugin loads, both on manual enable and on
// auto-load at startup. done(null) allows activation; done({title, details})
// blocks it and shows an expandable toast in which http(s) URLs are clickable.
//
// Must stay non-visual (a QtObject): it is not placed in the scene graph.
QtObject {
    function check(done) {
        Proc.runCommand("dankSyncthing.depCheck", ["sh", "-c", "command -v curl >/dev/null && command -v jq >/dev/null"], (stdout, exitCode) => {
            if (exitCode !== 0) {
                done({
                    "title": I18n.tr("curl and jq are required"),
                    "details": I18n.tr("Syncthing Status shells out to curl and jq to read the Syncthing REST API.\n\nInstall both, then re-enable this plugin.")
                });
                return;
            }

            // Not finding a config file is not fatal: the URL and API key can be
            // set explicitly in the plugin settings. Load, and let the widget
            // show an actionable "not configured" state instead of blocking.
            done(null);
        });
    }
}
