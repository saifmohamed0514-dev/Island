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
e=Path('IslandCore/enums/generic.swift').read_text();e=e[e.index('public enum NotchViews:'):e.index('enum SettingsEnum')]
Path(sys.argv[1]).write_text('import Foundation\nimport Combine\n'+e+s)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Permissions.swift" Tests/PermissionSmoke.swift -o "$STAGE/test"
"$STAGE/test"
