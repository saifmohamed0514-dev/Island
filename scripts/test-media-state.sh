#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d /private/tmp/island-media-state.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
xcrun swiftc -module-cache-path "$STAGE/cache" IslandCore/models/PlaybackState.swift Island/MediaState.swift Tests/MediaStateSmoke.swift -o "$STAGE/test"
"$STAGE/test"
