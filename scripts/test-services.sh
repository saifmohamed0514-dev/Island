#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-services.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Services.swift" <<'PY'
from pathlib import Path
import sys
c=Path('Island/Connections.swift').read_text();c=c[c.index('@MainActor final class IslandCodeHosting:'):c.index('struct IslandCodeHostingView:')]
w=Path('Island/Weather.swift').read_text();w=w[w.index('@MainActor final class IslandWeather:'):w.index('struct IslandWeatherView:')]
Path(sys.argv[1]).write_text('import Foundation\nimport Combine\nstruct IslandSecrets { static func read(account:String)->String? { fatalError("Fixture must never read Keychain") } }\n'+Path('Island/ReviewRules.swift').read_text()+c+w)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Services.swift" Tests/ServiceSmoke.swift -o "$STAGE/services"
"$STAGE/services"
