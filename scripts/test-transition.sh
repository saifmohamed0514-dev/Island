#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-transition-test.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Model.swift" <<'PY'
from pathlib import Path
import sys
source=Path('IslandCore/models/IslandViewModel.swift').read_text()
def method(signature):
    start=source.index(signature);opening=source.index('{',start);depth=1;end=opening+1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]
stubs=Path('Tests/TransitionFixtures.swift').read_text()
Path(sys.argv[1]).write_text(stubs+'\n@MainActor final class TransitionModel {\n'+'''
    var notchState:NotchState = .closed
    var notchSize = getClosedNotchSize()
    var closedNotchSize = getClosedNotchSize()
    var screenUUID:String?
    var isEditingText=false, isPinned=false, isBatteryPopoverActive=false, edgeAutoOpenActive=false
    let coordinator=IslandCoordinator.shared
    private var closedContentTask:Task<Void,Never>?
    var cancellables:Set<AnyCancellable> = []
    func pendingClose()->Task<Void,Never>? { closedContentTask }
'''+method('func open()')+'\n'+method('func close()')+'\n'+method('func destroy()')+'\n}\n')
PY
xcrun swiftc -module-cache-path "$STAGE/cache" "$STAGE/Model.swift" Tests/TransitionSmoke.swift -o "$STAGE/test"
"$STAGE/test"
