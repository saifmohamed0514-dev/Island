#!/bin/bash
# Parse the actual installer without executing its privileged operation.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
STAGE="$(mktemp -d /private/tmp/island-power-installer.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Harness.swift" <<'PYCODE'
from pathlib import Path
import sys
s=Path('Power/PowerInstaller.swift').read_text()
Path(sys.argv[1]).write_text(s+'''
let prepared=try IslandPowerInstaller.prepare(app:URL(fileURLWithPath:CommandLine.arguments[1]))
let shell=Process();shell.executableURL=URL(fileURLWithPath:"/bin/sh");shell.arguments=["-n"]
let input=Pipe();shell.standardInput=input
try shell.run();input.fileHandleForWriting.write(Data(prepared.shell.utf8));try input.fileHandleForWriting.close();shell.waitUntilExit();precondition(shell.terminationStatus == 0)
var error:NSDictionary?;let script=NSAppleScript(source:prepared.appleScript)
precondition(script?.compileAndReturnError(&error) == true && error == nil)
print("PASS: actual installer validates its signed app/payload, shell syntax and AppleScript syntax; no admin operation executed")
''')
PYCODE
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Harness.swift" -o "$STAGE/check"
"$STAGE/check" "$APP"
