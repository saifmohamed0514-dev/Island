#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-timer-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Timer.swift" <<'PY'
from pathlib import Path
import sys
s=Path('boringNotch/components/Notch/NotchHomeView.swift').read_text()
a=s.index('struct IslandTimerState:');b=s.index('@MainActor final class IslandFocusTimer',a)
Path(sys.argv[1]).write_text('import Foundation\n'+s[a:b])
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Timer.swift" Tests/TimerSmoke.swift -o "$STAGE/test"
"$STAGE/test"
