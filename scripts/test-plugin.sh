#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-plugin-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
xcrun swiftc -O -target arm64-apple-macos15.0 -module-cache-path "$STAGE/cache" Integrations/IslandPlugin.swift -o "$STAGE/IslandPlugin"
ISLAND_PLUGIN_BINARY="$STAGE/IslandPlugin" python3 -m unittest discover -s Tests -p test_plugin.py
xcrun swiftc -module-cache-path "$STAGE/cache" Island/PluginPackage.swift Tests/PluginPackageSmoke.swift -o "$STAGE/package-check"
"$STAGE/package-check"

python3 - "$STAGE/Native.swift" <<'PYMODEL'
from pathlib import Path
import sys
s=Path('Island/AgentBridge.swift').read_text()
e=s[s.index('    struct Event:'):s.index('    @Published var events:')]
a=s[s.index('    @discardableResult func answer('):s.index('    func choose()')]
Path(sys.argv[1]).write_text('import Foundation\n@MainActor final class IslandAgentBridge {\n'+e+'var events:[Event]=[];var root:URL?;var error:String?\n'+a+'}\n')
PYMODEL
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Native.swift" Tests/PluginNativeSmoke.swift -o "$STAGE/native-check"
"$STAGE/native-check"
