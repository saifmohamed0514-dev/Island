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
probes=[]
for file,method,wrapper in [('Island/Permissions.swift','nonisolated static func mainAccessibilityAuthorized','MainAccessProbe'),('IslandControls/IslandControls.swift','private func accessibilityAllowed','HelperAccessProbe')]:
    source=Path(file).read_text();start=source.index('    '+method);end=source.index('\n    }',start)+6
    probe=source[start:end].replace('nonisolated static func mainAccessibilityAuthorized','static func check').replace('private func accessibilityAllowed','static func check')
    for actual,fake in [('AXUIElementCreateSystemWide','PermissionProbeFixture.makeSystem'),('AXUIElementSetMessagingTimeout','PermissionProbeFixture.setTimeout'),('AXUIElementCopyAttributeValue','PermissionProbeFixture.read'),('AXIsProcessTrusted','PermissionProbeFixture.trustedValue'),('CGPreflightPostEventAccess','PermissionProbeFixture.trustedValue')]: probe=probe.replace(actual,fake)
    probes.append('enum '+wrapper+' {\n'+probe+'\n}')
Path(sys.argv[1]).write_text('import Foundation\nimport Combine\nimport ApplicationServices\n'+e+s+'\n'+'\n'.join(probes))
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Permissions.swift" Tests/PermissionSmoke.swift Tests/PermissionProbeFixtures.swift -o "$STAGE/test"
"$STAGE/test"
