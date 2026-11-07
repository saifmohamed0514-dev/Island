#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-snapping-test.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Snapping.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Island/WindowSnapping.swift').read_text();s=s[s.index('enum IslandSnapRules'):s.index('struct IslandWindowSettings:')]
# Exercise the production event/lifecycle code. Replace only OS boundaries:
# the XPC client, screen inventory, preview rendering and private visibility.
a=s.index('    private func showPreview(');b=s.index('    private func cancel()',a)
s=s[:a]+'    var previewed:[CGRect]=[]\n    private func showPreview(_ rect:CGRect,title:String) { previewed.append(rect) }\n'+s[b:]
s=s.replace('private func handle(', 'func handle(').replace('NSScreen.screens','SnapFixtureScreens.screens')
w=Path('Island/DevicesAndWindows.swift').read_text();w=w[w.index('enum IslandWindowLayout:'):w.index('struct IslandWindowSnapView:')]
Path(sys.argv[1]).write_text('import Foundation\nimport AppKit\nimport Combine\n'+w+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Snapping.swift" Tests/SnappingSmoke.swift -o "$STAGE/test"
"$STAGE/test"
