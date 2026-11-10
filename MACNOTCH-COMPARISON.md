# Reference feature audit — November 10, 2026

Checked against the current public [MacNotch feature catalogue](https://macnotch.io). “Implemented” describes Island source, not a promise that every app, account or device has been tested. This preview does **not** have complete feature parity.

| Reference area | Island 2.9 implementation and limits |
| --- | --- |
| Modules and modular Settings | 21 modules, enable/order/default selection, four-position interactive real layout, templates, undo, search and per-module settings. |
| Dashboard and profiles | Eleven classic widget types; up to 12 saved named module/layout arrangements with rename/update and persistent removal Undo; Work/Minimal schedules and shared Focus. Automatic scheduling of arbitrary named layouts and automatic app-folder scanning remain absent. |
| Media | Real artwork, supported transports, seeking and supported player volume. Compatibility depends on the selected backend and player. Audio spectrum and collapsed hover transport controls remain absent. |
| Files and drop actions | Tray, drag-out, Quick Look, AirDrop, open-with, ZIP/extract, image conversion, copy/move and removable-volume ejection. Direct iCloud-target drops remain absent; a user-chosen destination can be used. |
| Calendar and tasks | Search, upcoming events, writable Reminders, completion and recoverable task trash. Full event-detail/meeting-awareness UI and all reminder filters remain incomplete. |
| Notes | Multiple local notes, autosave and recoverable trash. |
| Focus and sounds | Ring durations, custom presets, work/break cycles, persistence, system/imported sounds, repeat and Stop. |
| Day timeline | Events, due/overdue tasks, completion, progress and an optional wind-down marker. |
| Usage | Local active-time and switch counters, seven-day history, categories, excluded apps, custom day boundary and undo clearing. Custom category colours and an insights sidebar remain absent. |
| Wellbeing | Daily water/break/mindful goals, breathing, movement, eye breaks and optional reminders. Eye breaks are in-Island, not a full-screen takeover; hearing exposure is not measured. |
| Weather | City-based current/hourly/seven-day forecasts, units, humidity/wind/pressure/UV, sunrise/sunset and chosen-photo/gradient backgrounds. Location-based lookup and an automatic photographic sky library remain absent. |
| Launcher and actions | Grid/list app/folder bookmarks, named Shortcuts, Keep Awake and optional restoration. App-folder scanning/pagination remains absent. |
| Keyboard controls | Open/peek/microphone, next/previous module, optional open-only navigation, configurable snooze/resume. |
| Notifications | Island-owned and explicitly forwarded Inbox alerts; no universal Notification Center history or replies to arbitrary apps. |
| Coding agents | Local Claude/Cursor and ChatGPT Work/Codex bridge, bounded session events and one-request decisions. Client setup/trust and actual sessions are required. |
| Code services and translation | GitHub/GitLab/Bitbucket/Jira and Ollama/OpenAI integrations exist; private account/API workflows still require credentials and live validation. |
| Live activities | Opt-in rotation of media, timer, upcoming event, device and Island Inbox activity; source filtering; priority HUD/power/approval notices. No arbitrary third-party update events. |
| Devices | macOS-reported connected Bluetooth/HID levels and optional low-battery alerts; accessory coverage is limited by available reports. |
| System and windows | CPU/memory/storage, fixed-layout buttons, edge/corner snapping, native glass battery and optional HUD replacement. Real AX/permission and external-monitor checks remain important. |
| Help, language and updates | Guided startup, practice tutorial, contextual page/module instructions, searchable Help & Tips, permission guidance, settings search, English/core Arabic labels and signed Sparkle scheduling. Full translations, production release hosting and Apple notarization remain outstanding. |

The current Mac only has its built-in display attached. Source/fixture checks do not establish physical external-display, real notification, private service, audio or accessory parity. See VERIFICATION.md for actual evidence.
