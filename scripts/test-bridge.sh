#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-bridge-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
xcrun swiftc -module-cache-path "$STAGE/cache" Integrations/IslandBridge.swift -o "$STAGE/IslandBridge"
ISLAND_BRIDGE_TEST_BINARY="$STAGE/IslandBridge" python3 -m unittest discover -s Tests -p test_bridge.py
python3 - "$STAGE/Translation.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Island/Connections.swift').read_text();s=s[s.index('struct IslandTranslationResponse:'):s.index('@MainActor final class IslandTranslation:')]
Path(sys.argv[1]).write_text('import Foundation\n'+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Translation.swift" Tests/TranslationSmoke.swift -o "$STAGE/translation"
"$STAGE/translation"
