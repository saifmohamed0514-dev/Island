#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-calendar.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Models.swift" <<'PY'
from pathlib import Path
import sys
m=Path('Island/IslandCalendarRules.swift').read_text()
s=Path('Island/CalendarExperience.swift').read_text();s=s[:s.index('struct IslandCalendarSettings:')]
a=Path('Island/CalendarAlerts.swift').read_text().replace('import UserNotifications','').replace('private var task:','var task:')
Path(sys.argv[1]).write_text(m+s+a)
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Models.swift" Tests/CalendarNotificationFixture.swift Tests/CalendarSmoke.swift -o "$STAGE/test"
python3 - "$STAGE/test" <<'RUN_CALENDAR'
import subprocess,sys
subprocess.run([sys.argv[1]],check=True,timeout=30)
RUN_CALENDAR
