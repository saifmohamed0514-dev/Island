# Island 2.2 development status

Updated November 6, 2026. This is an implementation inventory, not a claim of full MacNotch parity or zero bugs.

## Island interface

Island now has its own black surface, camera-safe compact activities, navigation, player, tray, dashboard, settings, welcome flow and custom icon. Inherited face/hello animations, promotional screens, team logos, branded artwork and welcome audio have been removed. Project, main target, executable and helper product use Island names. GPL copyright notices, attribution and a few internal compatibility identifiers remain intentionally preserved.

A running timer appears in two bounded wings beside the physical camera. Completion says **Done** for four seconds, then clears. A finished saved timer cannot restore a persistent completion banner on launch. Compact width is independent of the expanded panel's width.

## Available features

- 21 selectable modules: Dashboard, Now Playing, File Tray, Focus, Notes, Calendar, Tasks, Day Progress, Weather, Wellbeing, System Monitor, Screen Time, Launcher, Code Hosting, Translation, Bluetooth, Window Layouts, File Actions, Mirror, AI Coding and Inbox.
- Modules can be enabled, ordered and selected as the default. Five appear in the strip; the rest use More. Minimal/Work/Everything layouts and four configurable dashboard widgets. Optional daily Work/Minimal scheduling, including overnight periods and local time-zone changes.
- Own player with real artwork and metadata, transport, seeking, supported player-volume controls, and one Not Playing idle label. The licensed media-controller backends support Now Playing, Apple Music, Spotify and YouTube Music subject to source requirements.
- Own file tray, drag/drop, file picker, Quick Look, context actions and AirDrop. Existing bookmark/persistence backend is retained.
- Focus duration ring with top-seam clamping, typed durations, up to 12 saved presets, pause/resume/reset, persisted wall-clock deadline, configurable work/break/long-break cycles and one shared audio player across displays. Selectable system tones, imported ringtone, volume, silent mode and repeating ring with Stop.
- Multiple automatically saved local notes, migration of previous scratchpad, and 30-day recoverable note trash.
- Calendar search and upcoming events; Reminders task creation/completion, recoverable trash and restore. Explicit permission connection.
- Manual-city Open-Meteo current conditions and seven-day forecast. Celsius/Fahrenheit converts immediately and cached results survive module navigation.
- Water/break/mindfulness counters, breathing pacing and eye-break prompt; actual CPU/memory/storage readings; opt-in frontmost-app usage counters with idle-time exclusion.
- Security-scoped launcher bookmarks for user-selected apps/folders.
- GitHub/GitLab/Bitbucket open-review lists and Jira JQL issue lists. Read-only, explicit refresh, up to 30 items; credentials in Keychain.
- Local Ollama translation or optional OpenAI translation with a user-selected model and Keychain API key. OpenAI is opt-in and separately billed; requests set store:false. No cloud key or text is bundled or used in verification.
- Paired/connected Bluetooth devices and available HID battery readings. Coverage depends on device support.
- Manual window-layout buttons using the narrow Accessibility XPC helper; geometry handles displays left of and above the primary screen.
- File-picker actions for copy/move, ZIP creation/extraction, PNG/JPEG conversion, open-with, Music and AirDrop. Archive extraction rejects traversal paths, symlinks and large archives.
- Mirror with explicit camera start/stop. Keyboard shortcut recorders, display selection, optional volume/brightness HUD replacement and system-linked native glass battery pop-up on supported macOS versions. Battery percentage is inside its icon.
- Local Claude Code/Cursor hook bridge: session events, expiring single-request approval/denial, explicit review, compact pending count. Setup exports a helper and example configs to a chosen folder; it does not alter existing client settings. Inbox displays explicitly forwarded alerts. See Integrations/README.md.
- GPL source, local Git repository, signed Sparkle release tooling, build/release workflows and beginner publishing guide. Automatic updates remain unconfigured and off; nothing has been uploaded.

## Remaining reference scope

Native cross-app notification aggregation/replies; Jira status transitions; provider review-request filters/pagination; automatic drag-to-edge window overlays; Bluetooth automatic low-battery alerts and broader audio-device battery coverage; eject and richer file-drop action tiles; system-Focus-driven profiles; hourly/weather photographic presentation; advanced health/stretch/wind-down/hearing workflows; expanded screen-time categories/history; localization of new modules; the earlier customized privileged Low Power Mode toggle/helper. The current battery pop-up links to system Battery settings rather than exposing a nonfunctional toggle.

## Verification boundaries

Read VERIFICATION.md for actual checks. Only the built-in display is attached; physical external-display behavior is unverified. Private service access, real client hooks and optional permissions need end-to-end checks with the intended accounts/devices. This release is locally signed, not Apple-notarized.
