# Island 2.8.1

An independent, open-source macOS notch utility, based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch). GPL-3.0; original copyright notices and third-party licenses are retained.

**Development preview.** This is a newly reconstructed fork, not a complete recovery of the earlier customized app, and not yet full MacNotch feature parity. Read [FEATURE-STATUS.md](FEATURE-STATUS.md) before distributing it.

## In this preview

- Top-center notch UI, including notchless/external displays, with display settings.
- Own player, tray, dashboard, settings and onboarding with licensed media/file backends. Camera-safe compact activities and transient timer completion.
- Optional system volume/brightness HUD replacement with macOS Accessibility permission.
- Persistent focus timer with a draggable ring, saved custom presets, work/break cycles, selectable sounds, audio import, volume and repeat-until-stopped.
- Shared timer across displays; multiple local notes and four configurable dashboard widgets.
- A four-position module canvas: drag blocks into the notch preview, swap positions inside it, click for settings, and use the same arrangement on the real Island. Live blocks open full module controls; a grid button returns to the layout. Includes typed drag/drop, undo, search and a visible interaction guide. Settings can be resized.
- Module toggles, ordering, daily scheduled layouts and keyboard shortcut settings. Optional weather, tasks, day progress, wellbeing, system/usage monitoring, launcher, code hosting, local/optional cloud translation, device readings, window layouts, file actions and a local agent hook bridge/inbox. See FEATURE-STATUS.md for exact scope.
- ChatGPT Work/Codex, Claude Code and Cursor local hooks, one-request decisions and ChatGPT draft handoff. See [Integrations/README.md](Integrations/README.md).
- Narrow Low Power Mode service with one-time macOS setup; later toggles need no password. Local ad-hoc updates can require setup again. See [Power/README.md](Power/README.md).
- Hourly weather, optional device/wellbeing alerts, seven-day usage categories, provider pagination/Jira transitions and opt-in window snapping.
- One Permissions page with feature explanations, actual status checks and a sequential setup guide. Optional selections, skip/retry, and resume after System Settings. macOS privacy approvals remain separate from administrator authentication.
- Island-specific, signed Sparkle update configuration. Updates are off until configured.

Apple silicon, macOS 15+. Build with Xcode 26 or later. The supplied preview is locally signed and **not notarized**. A physical external monitor and all optional integrations still require live testing.

## Build

```sh
scripts/build.sh
```

After committing the corresponding source, `scripts/package-source.sh` creates a complete app + source ZIP.

`xcrun swift scripts/make-icon.swift` regenerates all ten custom icon resolutions and the ICNS from the included vector drawing.

The app ZIP is created at `dist/Island.zip`. Dependencies are pinned in the Xcode project's `Package.resolved`. First build needs internet. No paid Apple account is required for a local preview. For public distribution, review Developer ID signing and notarization.

## Open-source setup and updates

Start with [START-HERE.md](START-HERE.md), then follow [docs/RELEASING.md](docs/RELEASING.md). Nothing in this project publishes automatically. The release workflow prepares downloadable artifacts for review and has read-only repository permissions.

## License and attribution

See [LICENSE](LICENSE), [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES), and [UPSTREAM.md](UPSTREAM.md). Island is not an Apple product and is not affiliated with MacNotch. MacNotch screenshots were inspected as reference only; none of its images or proprietary code are distributed here.
