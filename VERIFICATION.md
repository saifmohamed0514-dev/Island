# Island 2.2 verification — November 6, 2026

## Passed

- Release build for Apple silicon with Xcode 27.2, minimum macOS 15; version 2.2.0 build 220.
- 12 deterministic timer state, persistence, duration-boundary and single-completion checks.
- 32 dial/preset/cycle/module/widget/schedule/display-geometry checks, including crossing the dial seam, limits, preset filtering, module fallback/order, four-session long breaks, negative/above-screen coordinates, bounded compact widths, dashboard-slot normalization and overnight schedule boundaries.
- Seven checks of the actual production timer class: transient completion expiry, no repeated completion, no banner restored from saved finished state, preset persistence, reset and work/break transition. Tests use an isolated in-memory store and Silent tone.
- Six typed translation-response fixture checks, including incomplete/refused/empty output rejection. No cloud request.
- Eight Python protocol tests of the real compiled bridge helper: Claude allow-once/deny/timeout, Cursor allow/timeout, wrong nonce, numeric boolean, notice and oversized-request handling. No agent command is executed.
- 10 archive checks using the production extraction code, including actual successful extraction, traversal rejection and symlink rejection.
- Six Python release/configuration tests, including actual Sparkle signing with an ephemeral test key, tamper rejection and mismatched-public-key rejection. No production update key was created or retained.
- Strict recursive local code-signature verification before packaging and after extraction.
- Live UI: no top gap on the built-in display; ring drag changed the duration to 60 minutes; a 45-minute preset was added, selected and restored after relaunch.
- Live UI: module controls, reorder, enablement and overflow navigation. System Monitor displayed actual CPU/memory/storage readings.
- Live UI: keyboard entry in the notch, weather retrieval, note creation/editing/switching, automatic save and recoverable trash. The temporary verification note was moved to recoverable trash.
- Earlier live checks: timer start/pause/reset, ringtone preview/stop with no error, single idle label, percentage contrast and system-linked glass battery pop-up.
- Live 2.2 UI: own player/tray/settings/dashboard, four widget cards, camera-safe timer countdown after normal relaunch, then complete clearing of the activity after the real timer expired. No full-width Timer finished banner was present.
- Live 2.2 UI: native app-menu Open Island and Settings entries, widget/schedule settings, and optional agent setup page. The app runs normally without --inspect-island; the verification timer was restored to its previous five-minute duration.
- Clean build verified to contain only IslandControls.xpc and no inherited welcome audio. The separately compiled local bridge is signed and sealed into the app.
- New preview installed as ~/Applications/Island Preview.app and relaunched normally. The original /Applications/Island.app is preserved. User preferences were not reset.
- Update feed and public key remain absent; updater startup stays disabled until configured.
- ZIP integrity, source repository integrity and extracted application checks.

## Limits and remaining work

Only the built-in display is connected; physical external-display behavior remains unverified. Geometry tests do not replace that check. New Bluetooth/window-control permissions were not granted during this audit. Actual window resizing, Bluetooth coverage, private GitHub/GitLab/Bitbucket/Jira access, real Claude/Cursor hooks, OpenAI translation, Ollama with an installed model, live Reminders modifications, custom ringtone import and audible timer completion, real sleep/wake, file-picker workflows, AirDrop and real app updates require end-to-end checks. The file tests exercise the production command layer rather than claiming every UI action was tested.

The GitHub workflows have not run remotely. Nothing was published. This preview is locally ad-hoc signed, not Apple-notarized. Upstream concurrency/deprecation warnings remain. FEATURE-STATUS.md lists the outstanding MacNotch scope; this is not a claim that full parity or zero bugs has been achieved.
