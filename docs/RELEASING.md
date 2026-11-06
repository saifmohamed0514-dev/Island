# Island signed updates

The app uses Sparkle, already linked by the Xcode project. At present both the feed and public key are absent, and starting the updater is gated on valid configuration. It cannot update from Boring Notch's feed.

Official reference: https://sparkle-project.org/documentation/ and https://sparkle-project.org/documentation/publishing/

## One-time setup

1. Create your own public GitHub repository. Decide its URL before distributing an auto-updating app. The configured bundle ID is `org.islandapp.Island`; choose a permanent ID before a public release if you want a namespace you own. Changing it later affects preferences, permissions and update identity.
2. Build once. Find Sparkle's tools under `.build/SourcePackages/artifacts/sparkle/Sparkle/bin/`.
3. Run `generate_keys --account IslandUpdates`. It stores the private update key in your macOS Keychain and prints the public key. Follow any macOS Keychain prompt yourself. Do not commit an exported private key.
4. Configure the project with the public key:

   ```sh
   python3 scripts/configure-updates.py YOUR-ACCOUNT/Island YOUR-PUBLIC-KEY
   ```

   This sets an HTTPS feed at `https://github.com/YOUR-ACCOUNT/Island/releases/latest/download/appcast.xml`. No upload occurs.
5. Commit the public configuration and rebuild. The first distributed auto-updating app must already contain the correct public key and feed.
6. For public distribution, obtain an Apple Developer ID certificate and notarize your app. The supplied local build uses ad-hoc signatures and is not notarized. Sparkle archive signatures and Apple's code signing/notarization are separate protections. Never share your Apple private certificate in source.

## Prepare an update locally

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in both main-target build configurations in `Island.xcodeproj/project.pbxproj`. Example: version `2.0.1`, build `201`. Keep increasing the build number.
2. Run `scripts/build.sh` and extract `dist/Island.zip` to a temporary folder. Verify the extracted app with `codesign --verify --deep --strict`.
3. Export your Sparkle key to a protected file using `generate_keys --account IslandUpdates -x PRIVATE-PATH`. Keep it outside the repository. Set `SPARKLE_PRIVATE_KEY` from that file in your own shell; do not paste the value into chats, source or logs. The release script passes it to Sparkle using an owner-only temporary file, not a command-line argument.
4. Run:

   ```sh
   python3 scripts/prepare-release.py \
     --app /PATH/TO/EXTRACTED/Island.app \
     --archive dist/Island.zip \
     --output dist/appcast.xml \
     --sign-tool .build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
   ```

5. Create a GitHub Release tagged exactly `v` plus the app version (for example `v2.0.1`). Attach **Island.zip** and **appcast.xml** with those exact names. Include release notes and the source commit. Mark it as the latest release when you are ready for that update to reach users. The helper only prepares files; it never publishes.
6. Test a genuine upgrade from the previous distributed build on a separate test Mac/account before announcing release. Test a tampered ZIP and confirm rejection. Keep the last working release available.

## Optional GitHub Actions

The Build workflow runs tests and prepares an ad-hoc development ZIP. The manually started Prepare signed release workflow also produces the signed appcast when you supply `SPARKLE_PRIVATE_KEY` as an Actions secret and have committed the public feed configuration. It deliberately has no write/publish permission; download and review its artifacts, then create the Release yourself.

This is a local-development pipeline, not a complete Developer ID/notarization pipeline. Add a protected signing/notarization job with your own Apple credentials before treating it as a production release process. Never expose release secrets to pull-request builds.
