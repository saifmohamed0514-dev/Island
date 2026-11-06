# Preview verification — November 6, 2026

- PASS: Apple silicon Release build with Xcode 27.2, minimum deployment target macOS 15.
- PASS: 12 timer state checks covering start/pause/reset, paused and running persistence, completion exactly once, long clock jumps and duration boundaries.
- PASS: six Python tests, including real Sparkle archive signing with an ephemeral test key, CryptoKit verification, tampered-archive rejection and mismatched-public-key rejection. No production signing key was created or retained.
- PASS: strict recursive ad-hoc code-signature verification before packaging and after extracting the delivered archive.
- PASS: live onboarding with optional permissions skipped; Focus & Sounds settings, ringtone preview/stop with no error, single idle label, dashboard navigation, timer start/pause/reset, notes editor, battery percentage contrast and system-native glass pop-up.
- PASS: fixed preview's music observer subprocess exits on normal quit. Earlier test-version orphans were removed.
- PASS: installed previous Island preserved and relaunched; new preview was not installed over it.
- PASS: update feed/public key absent in the supplied app; update startup and menu action disabled until configured.
- PASS: final ZIP extraction, executable architecture and source repository integrity checks.

## Unverified or incomplete

Only the built-in display is connected. External-screen placement is implemented through the inherited per-screen window code, but has not been physically verified. Accessibility permission was not granted to this new identity, so actual HUD suppression is not verified. Live provider playback, AirDrop, custom ringtone import and audible timer completion, real sleep/wake and an actual old-to-new app update still need checks. The GitHub workflows are prepared but have not run on GitHub. No public repository or production release exists yet.

This preview is locally signed, not Apple-notarized. Upstream Swift concurrency/deprecation warnings remain. See FEATURE-STATUS.md for the full outstanding MacNotch scope. This is not a claim that every bug is fixed or that every requested feature is implemented.
