# Island

An independent, open-source macOS notch utility, based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch). GPL-3.0; original copyright notices and third-party licenses are retained.

**Development preview.** This is a newly reconstructed fork, not a complete recovery of the earlier customized app, and not yet full MacNotch feature parity. Read [FEATURE-STATUS.md](FEATURE-STATUS.md) before distributing it.

## In this preview

- Top-center notch UI, including notchless/external displays, with display settings.
- Now Playing transport, media artwork, file shelf, AirDrop, calendar and mirror inherited from upstream.
- Optional system volume/brightness HUD replacement with macOS Accessibility permission.
- Persistent focus timer with presets, pause/resume/reset, custom duration, selectable sounds, audio import, preview, volume and repeat-until-stopped.
- Shared timer across displays; local scratchpad and a dashboard.
- Island-specific, signed Sparkle update configuration. Updates are off until configured.

Apple silicon, macOS 15+. Build with Xcode 26 or later. The supplied preview is locally signed and **not notarized**. A physical external monitor and all optional integrations still require live testing.

## Build

```sh
scripts/build.sh
```

The app ZIP is created at `dist/Island.zip`. Dependencies are pinned in the Xcode project's `Package.resolved`. First build needs internet. No paid Apple account is required for a local preview. For public distribution, review Developer ID signing and notarization.

## Open-source setup and updates

Start with [START-HERE.md](START-HERE.md), then follow [docs/RELEASING.md](docs/RELEASING.md). Nothing in this project publishes automatically. The release workflow prepares downloadable artifacts for review and has read-only repository permissions.

## License and attribution

See [LICENSE](LICENSE), [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES), and [UPSTREAM.md](UPSTREAM.md). Island is not an Apple product and is not affiliated with MacNotch. MacNotch screenshots were inspected as reference only; none of its images or proprietary code are distributed here.
