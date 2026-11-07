#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-permissions-test.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Permissions.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Island/Permissions.swift').read_text()
s=s[s.index('enum IslandPermission:'):s.index('@MainActor final class IslandSystemPermissionClient:')]
Path(sys.argv[1]).write_text('import Foundation\nimport Combine\n'+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Permissions.swift" Tests/PermissionSmoke.swift -o "$STAGE/test"
"$STAGE/test"
