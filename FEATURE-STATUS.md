# Island 2.10 development status

Updated November 13, 2026. This is an implementation inventory, not a claim of full MacNotch parity or zero bugs.

## Island interface

Island now has its own black surface, camera-safe compact activities, navigation, player, tray, dashboard, settings, welcome flow and custom icon. Inherited face/hello animations, promotional screens, team logos, branded artwork and welcome audio have been removed. Project, main target, executable and helper product use Island names. GPL copyright notices, attribution and a few internal compatibility identifiers remain intentionally preserved.

A running timer appears in two bounded wings beside the physical camera. Completion says **Done** for four seconds, then clears. A finished saved timer cannot restore a persistent completion banner on launch. Compact width is independent of the expanded panel's width. Opening/closing clips a fixed expanded canvas inside a single animated surface; outgoing content fades before a cancellable default-tab reset.

## Available features

- 21 selectable modules: Dashboard, Now Playing, File Tray, Focus, Notes, Calendar, Tasks, Day Progress, Weather, Wellbeing, System Monitor, Screen Time, Launcher, Code Hosting, Translation, Bluetooth, Window Layouts, File Actions, Mirror, AI Activity and Inbox.
- Settings → Modules is a four-position module canvas. Drop cards into the body of the notch preview, drag existing blocks to swap positions, or replace a block with a new card. The first placement applies the arrangement to the real Island’s Dashboard. Click preview blocks for settings; click real blocks for full controls, with a grid button to return. Layout removal and module enablement are separate. Existing classic Dashboard widgets and module navigation settings are retained. Includes undo, templates, search, position buttons, visible instructions and up to 12 named saved arrangements with rename/update and persistent removal Undo. Preview content is illustrative.
- Modules can be enabled, ordered and selected as the default. Five appear in the strip; the rest use More. Minimal/Work/Everything layouts and four configurable dashboard widgets. Optional daily Work/Minimal scheduling, including overnight periods and local time-zone changes; a shared system Focus state can take priority when macOS makes it available and permission is granted.
- Own player with real artwork and metadata, transport, seeking, supported player-volume controls, and one Not Playing idle label. The licensed media-controller backends support Now Playing, Apple Music, Spotify and YouTube Music subject to source requirements.
- Own file tray, drag/drop, file picker, Quick Look, context actions and AirDrop. Existing bookmark/persistence backend is retained.
- Focus duration ring with top-seam clamping, typed durations, up to 12 saved presets, pause/resume/reset, persisted wall-clock deadline, configurable work/break/long-break cycles and one shared audio player across displays. Selectable system tones, imported ringtone, volume, silent mode and repeating ring with Stop.
- Multiple automatically saved local notes, migration of previous scratchpad, and 30-day recoverable note trash.
- Calendar search and upcoming events; Reminders task creation/completion, recoverable trash and restore. Explicit permission connection.
- Manual-city Open-Meteo current conditions, next-24-hour temperature/rain forecast and chart, and seven-day forecast. Optional user-selected photographic background or Island sky gradient. Celsius/Fahrenheit converts immediately and cached results survive module navigation.
- Water/break/mindfulness goals, paced breathing, timed movement and eye-break workflows; optional water/movement/wind-down notifications while Island is running, with quiet overnight hours. Headphone-volume reminders are prompts, not hearing-exposure measurements. Actual CPU/memory/storage readings; opt-in frontmost-app counters with seven-day chart/history, user-assigned categories, idle/sleep exclusion, and undo for clearing today.
- Security-scoped launcher bookmarks for user-selected apps/folders.
- GitHub/GitLab/Bitbucket open-review lists and Jira JQL issue lists. Explicit refresh and pagination, requested-reviewer filtering on the current page, and credentials in Keychain. Jira supports user-confirmed status transitions; workflows needing additional fields open Jira. Account/issue changes invalidate cached transition choices.
- Local Ollama translation or optional OpenAI translation with a user-selected model and Keychain API key. OpenAI is opt-in and separately billed; requests set store:false. No cloud key or text is bundled or used in verification.
- Connected Bluetooth/HID devices, separately reported earbud/case levels where exposed, configurable low-battery threshold and rate-limited alerts. Coverage depends on device support.
- Manual window-layout buttons and opt-in drag-to-edge/corner snap previews using the narrow Accessibility helper. The drag monitor checks for actual title-bar movement before offering a snap. Geometry handles displays left of and above the primary screen.
- File drops directly onto File Actions, tray-to-action handoff, explicit removable-volume ejection, and picker actions for copy/move, ZIP creation/extraction, PNG/JPEG conversion, open-with, Music and AirDrop. Archive extraction rejects traversal paths, symlinks and large archives.
- Mirror with explicit camera start/stop. Keyboard shortcut recorders, display selection, optional volume/brightness HUD replacement and system-linked native glass battery pop-up on supported macOS versions. Battery percentage is inside its icon.
- Local ChatGPT Work/Codex/Claude Code/Cursor hook bridge: session events, expiring single-request approval/denial, explicit review, compact pending count. Setup exports a helper and example configs to a chosen folder; it does not alter existing client settings. Inbox displays explicitly forwarded alerts. See Integrations/README.md.
- ChatGPT draft handoff and connected chat links, an English/Arabic language picker with core Arabic labels, in-app help and a diagnostic summary containing no note text, tokens or user paths. Some detailed messages retain English.
- Dedicated, source-included Low Power Mode service and one-time GUI setup helper; narrow fixed-command interface, immediate yellow switch state and macOS reconciliation. Live setup/authorization remains a separate verification step. Ad-hoc updates may require setup again; normal toggles do not. See Power/README.md.
- Central Permissions page for shared Window and media controls, Bluetooth, camera, calendar, reminders, notifications, Music/Spotify automation, shared Focus and Low Power Mode. Select features, request one at a time, skip or finish later, and resume after manual System Settings approval. Checks do not request grants. Existing media polling checks automation permission before scripting; setup owns the consent prompt. No Touch ID shortcut bypasses macOS or client hook review.
- GPL source, local Git repository, signed Sparkle release tooling, build/release workflows and beginner publishing guide. Update consent, hourly/daily/weekly checks and quit/idle/night installation choices are implemented. A signing key is stored in the owner’s Keychain; only its public key is bundled. Checks/downloads start off. The GitHub release feed remains unconnected and nothing has been uploaded.

## Refinement in 2.8

Settings has grouped sections, keyboard focus, page/module search and direct File Tray options. First launch asks about login and update choices, then other preferences, permissions, a hands-on practice tutorial and real module customization. Native approval requests no longer jump to System Settings automatically; explicit manual steps explain the correct switch and resume only after returning to Island. Trackpad haptics mark useful interactions with a global rate limit and an off switch.

New options include Live Activities rotation/source filters, module and snooze shortcuts, due-task day timelines, usage exclusions/day boundaries, weather pressure/UV/sun times, launcher grid/list and named Shortcuts, Keep Awake, extra Dashboard widgets and an editable quote. A skipped eye break no longer credits a completed break. Read [the complete comparison](MACNOTCH-COMPARISON.md) for remaining subfeature gaps.

## Refinement in 2.9

Each Settings page has contextual help, and every module inspector has How to use. Help & Tips searches instructions and terms; ordinary Settings search also matches these explanations and multiple words. The one-time help tip can be dismissed permanently. Named layouts save module enablement, opening module and the four-position arrangement while preserving module content and account settings. Automatic scheduling still uses Work/Minimal. Diagnostics copy reports last-known permission and feature state without private content. macOS Screen Time enforcement/settings are unchanged as requested.

## Remaining reference scope

Universal cross-app Notification Center history and inline replies are not implemented; inbox content is Island-owned or explicitly forwarded. Full accessory battery coverage is limited to what macOS exposes. Detailed translations beyond the included Arabic labels, measured headphone hearing exposure, Apple Developer ID/notarization and physical external-display validation remain outstanding. Shared Focus status can be unavailable to this app/build; the daily schedule remains available. Private service and real client-hook connections still require their accounts/permissions and live validation.

## Verification boundaries

Read VERIFICATION.md for actual checks. Only the built-in display is attached; physical external-display behavior is unverified. Private service access, real client hooks and optional permissions need end-to-end checks with the intended accounts/devices. This release is locally signed, not Apple-notarized.


## Plugin connections and trays in 2.10

Agents & Inbox now offers hook-free plugins first. It exports a local OpenAI marketplace/plugin and a Claude MCPB installer plus Claude Code plugin folder, using the client’s existing account. MCP progress updates and clarification questions are local and bounded; questions support options/free text, expiry, cancellation and explicit Send answer. The native approval bridge remains under an optional legacy disclosure. No hooks or trust records are installed/changed by creating the new packages. Actual client installation and end-to-end use remain separate checks.

Settings → Trays controls both opened-Island tools and closed-Island activities. Choose, search, reorder, set the opening module and undo changes. Closed activity order/enablement persists; the timer can be hidden while it continues running. Wellbeing can show the day’s water count and goal, and plugin work/questions can appear compactly. Modules and their saved content are retained. Trays respect module enablement; transient media HUD/battery notices retain their existing controls.
