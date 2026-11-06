#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-file-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys,zipfile,stat
folder=Path(sys.argv[1]);s=Path('Island/FileActions.swift').read_text();a=s.index('enum IslandFileCommands');b=s.index('struct IslandFileActionsView')
(folder/'Commands.swift').write_text('import Foundation\nimport ImageIO\nimport UniformTypeIdentifiers\n'+s[a:b])
with zipfile.ZipFile(folder/'safe.zip','w') as z:z.writestr('folder/hello.txt','Hello Island')
with zipfile.ZipFile(folder/'traversal.zip','w') as z:z.writestr('../escape.txt','No')
with zipfile.ZipFile(folder/'symlink.zip','w') as z:
 i=zipfile.ZipInfo('link');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(i,'/tmp')
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Commands.swift" Tests/FileSmoke.swift -o "$STAGE/test"
"$STAGE/test" "$STAGE"
