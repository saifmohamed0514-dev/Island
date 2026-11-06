# Island 2.1 development status

Updated November 6, 2026. These are implementation and verification states, not a claim of complete MacNotch parity.

## Implemented

- Draggable duration ring, seamless top-of-dial clamping, typed custom durations in the preset pop-up, up to 12 saved presets, removal and persistence.
- Timer pause/resume/reset, persisted deadlines and paused time, selectable/imported ringtone, preview, volume, silent mode, repeat-until-stopped, configurable work/break cycles and every-fourth-session long breaks.
- Collapsed timer activity and completion indicator, with a shared timer/audio player across displays.
- Top-aligned layout with hosting safe-area insets removed, keyboard-capable text inputs, text-editing/modal protection, and per-display pinning.
- Settings module enablement, ordering, default module, Minimal/Work/Everything layouts, overflow navigation, and hiding of disabled modules.
- 18 selectable modules: Dashboard, Now Playing, File Tray, Focus, Notes, Calendar, Tasks, Day Progress, Weather, Wellbeing, System Monitor, Screen Time, Launcher, Code Hosting, Translation, Bluetooth and Window Layouts and File Actions.
- Multiple local notes, migration of the previous scratchpad, recoverable note trash and automatic saves.
- Calendar search and upcoming events; Reminders task creation/completion, recoverable trash and restore, with explicit permission connection.
- Manual-city Open-Meteo current conditions and seven-day forecast, Celsius/Fahrenheit.
- Local wellbeing counters, breathing pacing and eye-break prompt; CPU/memory/storage sampling; opt-in frontmost-app usage and app-switch counters.
- Security-scoped launcher bookmarks for user-chosen apps/folders.
- GitHub/GitLab/Bitbucket open-review lists and Jira JQL issue lists, with credentials in Keychain and explicit refresh. Current provider views are read-only and show up to 30 items.
- Local Ollama translation with an explicitly selected model.
- Paired/connected Bluetooth devices and available HID battery readings. Battery data is not available for every device.
- User-selected window layouts through the limited Accessibility XPC helper. This version exposes manual layout buttons rather than drag-to-edge zones.
- File-picker actions for copy/move, ZIP creation/extraction, PNG/JPEG conversion, open-with, Music and AirDrop. Archive extraction rejects traversal paths, symlink entries and very large archives. Originals are retained unless Move or Trash is chosen.
- Inherited media controls, shelf drag/drop, calendar/mirror, optional HUD replacement, per-screen windows and hot-plug handling.
- GPL source, local Git repository, signed Sparkle release tools, build/release workflows and beginner publishing guide. Updates remain unconfigured and off.

## Still outstanding from the full reference scope

Native cross-app notification aggregation/replies; Claude/Cursor session and approval integration; OpenAI translation; Jira status transitions; provider review-request filters/pagination; automatic drag-to-edge snap overlays; automatic Bluetooth low-battery notifications and all audio-device battery formats; eject and richer notch-drop action tiles; time/Focus-driven dashboard profiles and configurable widget slots; hourly/weather photographic presentation; advanced health goals/stretch/wind-down/hearing workflows; expanded screen-time categories/history; completing localization of new modules; the earlier customized privileged Low Power Mode helper. The complete appearance and behavior of MacNotch has not been reproduced.

## Verification boundaries

Read VERIFICATION.md. Public service integrations, device permissions and physical external-display operation require their own end-to-end validation. A successful build is not proof that all integrations work on every Mac. This build is locally signed, not notarized.
