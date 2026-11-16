#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-tray-drag-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 - "$STAGE/Store.swift" <<'PY'
from pathlib import Path
import sys
source=Path('IslandCore/components/Shelf/ViewModels/ShelfStateViewModel.swift').read_text()
method=source[source.index('    func removeAfterDrag('):source.index('    func updateBookmark(')]
Path(sys.argv[1]).write_text('''import Foundation
struct ShelfItem {
    static var cleanupCount=0
    let id:UUID
    let url:URL
    func cleanupStoredData() { Self.cleanupCount+=1;try? FileManager.default.removeItem(at:url) }
}
@MainActor final class ShelfStateViewModel {
    var items:[ShelfItem]
    init(items:[ShelfItem]) { self.items=items }
'''+method+'}\n')
PY
xcrun swiftc -module-cache-path "$STAGE/cache" Island/TrayDrag.swift "$STAGE/Store.swift" Tests/TrayDragSmoke.swift -o "$STAGE/check"
"$STAGE/check"
