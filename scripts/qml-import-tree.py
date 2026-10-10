#!/usr/bin/env python3
"""Generate a shadow import tree so qmllint can resolve DMS's `qs.*` modules.

DMS maps its shell root to the `qs` module namespace through Quickshell's own
loader, not through qmldir files, so qmllint cannot follow `import qs.Common` on
its own and reports every DMS type as unresolved. This mirrors the DMS QML tree
with symlinks and writes the qmldir files qmllint needs, which turns the linter
from noise into a real type check — it is what caught a `property var state`
shadowing QQuickItem.state in this plugin.

Usage: qml-import-tree.py <dms-qml-root> <output-dir>
"""
import os
import shutil
import sys


def main(src: str, out: str) -> int:
    if not os.path.isdir(src):
        print(f"not a directory: {src}", file=sys.stderr)
        return 1

    shutil.rmtree(out, ignore_errors=True)
    written = 0

    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        rel = os.path.relpath(dirpath, src)
        dest = os.path.join(out, "qs") if rel == "." else os.path.join(out, "qs", rel)
        os.makedirs(dest, exist_ok=True)

        # Symlink every file, not just QML, so relative .js and asset imports
        # inside DMS still resolve.
        for name in filenames:
            link = os.path.join(dest, name)
            if not os.path.lexists(link):
                os.symlink(os.path.join(dirpath, name), link)

        qmls = sorted(f for f in filenames if f.endswith(".qml"))
        if not qmls:
            continue

        module = "qs" if rel == "." else "qs." + rel.replace(os.sep, ".")
        # No `depends` entries: adding them makes qmllint fail to resolve the
        # module's own types entirely, which is worse than the one gap it would
        # close (basic value types such as `color` on DMS singletons).
        lines = [f"module {module}"]
        for name in qmls:
            typename = name[:-4]
            # Only capitalised files are importable QML types.
            if not typename[:1].isupper():
                continue
            with open(os.path.join(dirpath, name), encoding="utf-8", errors="ignore") as fh:
                head = fh.read(400)
            prefix = "singleton " if "pragma Singleton" in head else ""
            lines.append(f"{prefix}{typename} 1.0 {name}")

        with open(os.path.join(dest, "qmldir"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        written += 1

    print(f"generated {written} qmldir files under {out}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
