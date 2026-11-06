#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-completion-test.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys
folder=Path(sys.argv[1]);s=Path('IslandCore/components/Notch/IslandFocus.swift').read_text();a=s.index('struct IslandTimerState:');b=s.index('struct IslandFocusView:')
m=Path('Island/Modules.swift').read_text();a2=m.index('enum IslandPresetRules');b2=m.index('extension NotchViews')
(folder/'Timer.swift').write_text('import Foundation\nimport AppKit\nimport AVFoundation\nimport Combine\nimport UniformTypeIdentifiers\n'+m[a2:b2]+s[a:b])
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Timer.swift" Tests/CompletionSmoke.swift -o "$STAGE/test"
"$STAGE/test"
