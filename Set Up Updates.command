#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
printf 'Island update setup\nYour private signing key stays in Keychain. Nothing will be published.\n\n'
read -r -p 'Paste your GitHub repository URL (or owner/repository): ' repository
packages="${ISLAND_PACKAGES_DIR:-$HOME/Library/Developer/Xcode/DerivedData}"
generate="$(find "$packages" -type f -name generate_keys -path '*/sparkle/*' -print -quit)"
if [[ -z "$generate" ]]; then printf 'Build Island once with scripts/build.sh, then run this setup again.\n';exit 1;fi
"$generate" --account Island-org.islandapp.Island
public_key="$("$generate" --account Island-org.islandapp.Island -p)"
python3 scripts/configure-updates.py "$repository" "$public_key"
printf '\nThe release channel is configured in your source. Rebuild Island and publish signed releases using START-HERE.md.\n'
read -r -p 'Press Return to close. ' unused
