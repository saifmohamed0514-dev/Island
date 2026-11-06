# Feature status

New development preview, November 6, 2026. A successful build is not full feature parity or end-to-end verification.

## Implemented in this source

- Existing upstream media controls, artwork, calendar/reminders display, camera mirror, file shelf and AirDrop interfaces.
- Existing upstream volume/brightness HUD replacement and Accessibility authorization UI.
- Existing upstream per-screen windows, hot-plug handling and centered frame calculation; enabled on all displays by default.
- Island focus timer, persistence across launch, deadline-based timing, pause/reset/presets and editable duration.
- Ringtone selection/import, decoder validation, copied app-owned audio, preview, volume, silence and looping with Stop.
- One shared timer/audio player across screen windows.
- Local notes scratchpad and clock/media/timer dashboard.
- In-battery percentage, system-linked native glass battery pop-up, music process cleanup and duplicate-instance guard.
- Separate Island identity, custom icon, update-feed configuration gate, build script, CI artifact workflow, signed appcast preparation and open-source documentation.

## Pending from the requested MacNotch scope

Full reference appearance; detachable navigation strip; configurable dashboard slots/profiles; work/break cycle automation; advanced reminder task CRUD/trash; multiple notes; day timeline; screen-time tracking; wellbeing modules; weather; notification aggregation/replies; AI coding agents; GitHub/GitLab/Bitbucket/Jira integrations; translation providers; extended file actions; window snapping; Bluetooth battery monitoring; system monitor; module ordering/localization completion. Earlier Island's privileged Low Power Mode helper is not reconstructed in this preview.

## Verification limits

Timer state/persistence and update configuration have automated checks. Build/signature/archive results are recorded in the deliverable's verification report. Physical external-monitor operation, HUD suppression on all keyboards and displays, real sleep/wake, fresh permission flows, live music providers, custom ringtone UI/audio, AirDrop and real signed updates need end-to-end checks. This preview is not the complete replacement requested in the feature specification.
