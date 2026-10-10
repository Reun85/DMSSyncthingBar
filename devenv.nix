{ pkgs, lib, ... }:

{
  # ---------------------------------------------------------------------------
  # Toolchain
  # ---------------------------------------------------------------------------
  # qt6.qtdeclarative provides qmlformat / qmllint / qmlls / qml in its main
  # output's bin/ (verified against qtdeclarative-6.11.2).
  packages = with pkgs; [
    qt6.qtdeclarative
    curl
    jq
    nodejs_22
    python3        # scripts/qml-import-tree.py, used by st-lint
    git
    shellcheck
  ];

  env.DMS_PLUGIN_ID = "dankSyncthing";
  env.DMS_PLUGIN_DIR = "dankSyncthing";

  # ---------------------------------------------------------------------------
  # Scripts
  # ---------------------------------------------------------------------------
  scripts.st-fmt.exec = ''
    exec qmlformat -i "$DEVENV_ROOT/$DMS_PLUGIN_DIR"/*.qml
  '';

  # Real type checking, not just syntax. qmllint cannot resolve DMS's `qs.*`
  # modules on its own (Quickshell maps the shell root to that namespace through
  # its own loader rather than qmldir files), so this builds a shadow import tree
  # first. Without it every DMS type reports as unresolved and the useful signal
  # is buried.
  scripts.st-lint.exec = ''
    set -u
    root="$DEVENV_ROOT"
    plug="$root/$DMS_PLUGIN_DIR"
    cache="''${XDG_CACHE_HOME:-$HOME/.cache}/dankSyncthing-lint"
    status=0

    dms_qml=$(st-dms-root)
    if [ -z "$dms_qml" ]; then
      echo "could not locate the DMS QML root; falling back to a syntax check only" >&2
      for f in "$plug"/*.qml; do
        qmlformat "$f" >/dev/null || status=1
      done
    else
      python3 "$root/scripts/qml-import-tree.py" "$dms_qml" "$cache/imports" >/dev/null

      # qmllint needs Qt's own QML modules and Quickshell's too, or QtQuick
      # fails to import and every DMS type cascades into "not resolved".
      qt_qml=$(dirname "$(dirname "$(readlink -f "$(command -v qmllint)")")")/lib/qt-6/qml
      [ -d "$qt_qml" ] || qt_qml=""
      qs_qml=$(dirname "$(dirname "$(readlink -f "$(command -v quickshell 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)/lib/qt-6/qml
      [ -d "$qs_qml" ] || qs_qml=$(ls -d /nix/store/*-quickshell-*/lib/qt-6/qml 2>/dev/null | tail -n 1)
      [ -n "$qs_qml" ] && [ -d "$qs_qml" ] || qs_qml=""

      # The plugin is linted from a staging copy so its own relative JS imports
      # and qmldir resolve the same way they do when installed.
      rm -rf "$cache/plug" && mkdir -p "$cache/plug"
      cp "$plug"/*.qml "$plug"/*.js "$plug/qmldir" "$cache/plug/"

      for f in "$cache/plug"/*.qml; do
        out=$(qmllint \
                -I "$cache/imports" \
                ''${qt_qml:+-I "$qt_qml"} \
                ''${qs_qml:+-I "$qs_qml"} \
                "$f" 2>&1 \
              | grep -E "^(Warning|Error):" \
              | grep -vE "\[unqualified\]|\[import\]|\[required\]" \
              | grep -vE 'Type "(color|font|list)" of property' || true)
        # Three categories are excluded on purpose:
        #  [unqualified] - referring to the file's own root id from inside an
        #                  inline component or a Component block is the idiom
        #                  every bundled DMS plugin uses.
        #  [import]      - the shadow tree covers qs.* but not every transitive
        #                  Quickshell module.
        #  [required]    - PluginSettings re-parents its children, so qmllint
        #                  treats each *Setting as a deferred component and
        #                  cannot see the settingKey/label that are set right
        #                  there. DMS's own CompositeSettings.qml trips this 18
        #                  times, so it is a linter limitation, not a defect.
        # Also dropped: `Type "color" of property ...` on DMS singletons, a gap
        # in the generated qmldir that cannot be closed with `depends` entries
        # without breaking module resolution outright.
        if [ -n "$out" ]; then
          printf '%s\n%s\n' "$(basename "$f")" "$out"
          status=1
        fi
      done
    fi

    shellcheck -s sh "$plug/scripts/st-poll.sh" || status=1
    shellcheck "$root/scripts"/*.sh || status=1

    [ $status -eq 0 ] && echo "lint clean"
    exit $status
  '';

  # Locate the DMS QML tree: the running shell's own package, else the newest in
  # the store. Printed on stdout so st-lint can consume it.
  scripts.st-dms-root.exec = ''
    set -u
    for candidate in \
      "''${DMS_SHELL_DIR:-}" \
      "$(dirname "$(dirname "$(readlink -f "$(command -v dms 2>/dev/null)" 2>/dev/null)")" 2>/dev/null)/share/quickshell/dms"
    do
      if [ -n "$candidate" ] && [ -d "$candidate/Common" ]; then
        echo "$candidate"
        exit 0
      fi
    done
    ls -d /nix/store/*-dms-shell-*/share/quickshell/dms 2>/dev/null | tail -n 1
  '';

  scripts.st-poll.exec = ''
    exec "$DEVENV_ROOT/$DMS_PLUGIN_DIR/scripts/st-poll.sh" "$@"
  '';

  scripts.st-test.exec = ''
    exec node "$DEVENV_ROOT/tests/run.mjs" "$@"
  '';

  scripts.st-link.exec = ''
    exec "$DEVENV_ROOT/scripts/dev-link.sh" "$@"
  '';

  scripts.st-reload.exec = ''
    exec "$DEVENV_ROOT/scripts/reload.sh" "$@"
  '';

  scripts.st-logs.exec = ''
    exec journalctl --user -u dms -f
  '';

  enterShell = ''
    echo "dankSyncthing dev shell"
    echo "  st-fmt     format QML"
    echo "  st-lint    qmllint + shellcheck"
    echo "  st-test    run Status.js / Config.js fixtures"
    echo "  st-poll    run the poll script against the live instance"
    echo "  st-link    symlink the plugin into ~/.config/DankMaterialShell/plugins"
    echo "  st-reload  reload the plugin in the running shell"
    echo "  st-logs    follow dms logs"
  '';

  enterTest = ''
    st-test
  '';
}
