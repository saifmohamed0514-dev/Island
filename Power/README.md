# Island power controls

Island itself remains a sandboxed, normal-user application. The optional root service exposes only `ping` and one Boolean Low Power Mode operation for the selected power source. It cannot execute arbitrary commands or receive paths from clients.

Open **Settings → Permissions**, select **Low Power Mode**, and choose **Set up selected**. Battery and System Controls link to the same Permissions page. A short-lived, unsandboxed **Island Power Setup** app opens the normal macOS administrator dialog. Its installer validates the containing Island signature, copies the already-signed power payload into a root-private staging folder, verifies its SHA-256, then installs root-owned files:

- `/Library/PrivilegedHelperTools/org.islandapp.Island.Power`
- `/Library/LaunchDaemons/org.islandapp.Island.Power.plist`

The old customized `local.saif.island.power` service is not changed by this installer.

Developer ID builds bind the service to Island’s bundle identifier and Apple-validated Team ID, allowing updates from that signing identity. Ad-hoc local previews bind to that specific main application’s code-directory hash. An ad-hoc update can therefore require setup again; ordinary toggle operations do not authenticate again.

The daemon runs `/usr/bin/pmset` with a fixed argument array: `-b` or `-c`, `lowpowermode`, and `0` or `1`. The switch responds optimistically and then reconciles the operating-system state. Failed/unsupported requests are reported, not treated as successful toggles. A power-source change during a request can change which profile is active; review macOS Battery Settings if needed.

The tests validate the actual script builder against a signed staged application, parse the shell and AppleScript, and test the daemon’s argument/hash rules. They do not perform an administrator operation or replace live authorization/testing.

## Remove the optional service

After quitting Island, an administrator can unload `system/org.islandapp.Island.Power` with `launchctl bootout`, then remove the two exact files above. This removes the persistent helper without changing other launch services. The setup helper app does not register itself as a login item; its bundled location is only a standard signed-code location.
