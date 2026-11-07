#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-advanced.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Rules.swift" <<'PY'
from pathlib import Path
import sys
p=Path('Power/IslandPower.swift').read_text();p=p[p.index('enum IslandPowerRules'):p.index('final class IslandPowerService')]
c=Path('Island/ChatGPT.swift').read_text();c=c[c.index('enum IslandChatGPTLinks'):c.index('struct IslandChatGPTDraft')]
s=Path('Island/WindowSnapping.swift').read_text();s=s[s.index('enum IslandSnapRules'):s.index('@MainActor final class')]
w=Path('Island/DevicesAndWindows.swift').read_text();w=w[w.index('enum IslandWindowLayout:'):w.index('struct IslandWindowSnapView:')]
n=Path('Island/Notices.swift').read_text();n=n[n.index('enum IslandDeviceAlertRules'):]
r=Path('Island/ReviewRules.swift').read_text()
Path(sys.argv[1]).write_text('import Foundation\nimport CoreGraphics\n'+p+c+w+s+n+r)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Rules.swift" Tests/AdvancedSmoke.swift -o "$STAGE/rules"
"$STAGE/rules"
