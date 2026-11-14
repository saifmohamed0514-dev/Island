# Island 2.11.0

An independent, open-source macOS notch utility, based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch). GPL-3.0; original copyright notices and third-party licenses are retained.

**Development preview.** This is a newly reconstructed fork, not a complete recovery of the earlier customized app, and not yet full MacNotch feature parity. Read [FEATURE-STATUS.md](FEATURE-STATUS.md) before distributing it.

## In this preview

- Top-center notch UI, including notchless/external displays, with display settings.
- Own player, tray, dashboard, settings and onboarding with licensed media/file backends. Camera-safe compact activities and transient timer completion.
- Optional system volume/brightness HUD replacement with macOS Accessibility permission.
- Persistent focus timer with a draggable ring, saved custom presets, work/break cycles, selectable sounds, audio import, volume and repeat-until-stopped.
- Shared timer across displays; multiple local notes and four configurable dashboard widgets.
- A four-position module canvas: drag blocks into the notch preview, swap positions inside it, click for settings, and use the same arrangement on the real Island. Live blocks open full module controls; a grid button returns to the layout. Includes typed drag/drop, undo, search and a visible interaction guide. Settings can be resized.
- Module toggles, ordering, daily scheduled layouts and keyboard shortcut settings. Optional weather, tasks, day progress, wellbeing, system/usage monitoring, launcher, code hosting, local/optional cloud translation, device readings, window layouts, file actions and a local AI activity plugin/inbox. See FEATURE-STATUS.md for exact scope.
- Hook-free ChatGPT/Codex and Claude plugins for task progress and clarification questions answered in Island. Older local hook connections remain optional under Advanced. See [Integrations/README.md](Integrations/README.md).
- Narrow Low Power Mode service with one-time macOS setup; later toggles need no password. Local ad-hoc updates can require setup again. See [Power/README.md](Power/README.md).
- Hourly weather, optional device/wellbeing alerts, seven-day usage categories, provider pagination/Jira transitions and opt-in window snapping.
- One Permissions page with feature explanations, actual status checks and a sequential setup guide. Optional selections, skip/retry, and resume after System Settings. macOS privacy approvals remain separate from administrator authentication.
- Island-specific signed Sparkle updates from this repository’s latest release. Checks/downloads are opt-in; the signed release assets must be published first.

Apple silicon, macOS 15+. Build with Xcode 26 or later. The supplied preview is locally signed and **not notarized**. A physical external monitor and all optional integrations still require live testing.

## New in 2.11

Saved layouts include both tray modes, and your daily schedule can switch between named arrangements. Drag compact activities into the black preview and reorder them there. Hover over music for quick playback controls. Overview and Help & Tips include the first-launch Open Anyway guide.

## Download and open Island

Get the DMG from [the latest release](https://github.com/saifmohamed0514-dev/Island/releases/latest), then drag Island into Applications.

This preview is not Apple-notarized or Developer ID-signed. If macOS blocks a download you trust, first try opening Island once, then open **System Settings → Privacy & Security → Security → Open Anyway** and complete the Mac’s confirmation. Some macOS versions show **Open** first. See [the step-by-step install guide](INSTALL.md) and [Apple’s instructions](https://support.apple.com/102445).

## Build

```sh
scripts/build.sh
```

After committing the corresponding source, `scripts/package-source.sh` creates a complete app + source ZIP. `scripts/package-dmg.sh` creates a drag-to-Applications DMG containing the app, installation guide and matching source.

`xcrun swift scripts/make-icon.swift` regenerates all ten custom icon resolutions and the ICNS from the included vector drawing.

The app ZIP is created at `dist/Island.zip`. Dependencies are pinned in the Xcode project's `Package.resolved`. First build needs internet. No paid Apple account is required for a local preview. For public distribution, review Developer ID signing and notarization.

## Open-source setup and updates

Start with [START-HERE.md](START-HERE.md), then follow [docs/RELEASING.md](docs/RELEASING.md). Nothing in this project publishes automatically. The release workflow prepares downloadable artifacts for review and has read-only repository permissions.

## License and attribution

See [LICENSE](LICENSE), [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES), and [UPSTREAM.md](UPSTREAM.md). Island is not an Apple product and is not affiliated with MacNotch. MacNotch screenshots were inspected as reference only; none of its images or proprietary code are distributed here.

### Settings help and saved layouts

Use the question-mark button for the current page, Help & Tips for searchable instructions, or How to use in a module inspector. The introductory help tip can be dismissed permanently. Modules → Layouts saves up to 12 named arrangements, with rename, explicit update, apply and persistent removal Undo. Applying a layout preserves module content and approvals; schedules still use Work/Minimal.

### Hook-free AI plugins and trays

Settings → Agents & Inbox creates a ChatGPT/Codex local plugin and Claude desktop-extension installer/Code plugin. They expose local progress and clarification-question tools, use the account already signed in to the client, and contain no hooks. They work for tasks using the plugin, not every existing chat. Installation/tool review in the client and a real connection test remain required. See Integrations/README.md.

Settings → Trays separately customizes the tools inside Island and the activities while it is closed. Hide the timer without stopping it, add Wellbeing’s water counter, reorder priorities, choose rotation and undo changes.
