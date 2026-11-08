# Start here — publishing Island for the first time

Everything is local right now. You do not need to create a website or pay for hosting to share the source.

1. Create a GitHub account if you do not have one.
2. In GitHub, choose **New repository**, name it **Island**, and choose **Public**. Do not add a second README or license: this project already contains them.
3. Use GitHub Desktop: **File → Add local repository**, choose this project folder (the `Source` folder if you extracted the complete ZIP), and publish it to the empty repository. If needed, use GitHub Desktop's existing-repository instructions. Keep the GPL license and third-party notices.
4. Read `App-Read-Me.txt` in the package and `FEATURE-STATUS.md`. Describe the app as a development preview until the missing features and verification are finished.
5. Keep one installed copy at Applications → Island. To share a manual download, build with `scripts/build.sh`, create a GitHub Release and attach `dist/Island.zip`. Users can download the ZIP. The local preview is not Apple-notarized, so macOS may block it on another Mac; explain that clearly.
6. Automatic in-app updates have consent and scheduling controls. Double-click `Set Up Updates.command` in Source, paste your own GitHub repository URL and rebuild before your first public auto-updating release. The setup keeps the private signing key in Keychain. This Mac already has the Island signing key prepared; other developers create their own. Follow `docs/RELEASING.md` for publishing.

The complete download also contains Source/Integrations/README.md for local ChatGPT/Codex/Claude/Cursor setup and Source/Power/README.md for the optional Low Power Mode service. Never include your private bridge folder or client settings in a release.

## Every later update

Make and test changes, increase both version and build number, build a new ZIP, prepare its signed `appcast.xml` with `scripts/prepare-release.py` (the local command reads the signing key from Keychain), and attach both to a GitHub Release. Your app checks your own feed for newer builds. Do not reuse a build number.

## What not to upload

No passwords, private update keys, Apple signing certificates, access tokens or personal files. Only your Sparkle **public** key belongs in the project. Private keys belong in Keychain and, if you later use Actions, GitHub Actions secrets. The included `.gitignore` excludes common credential-file types, but always review staged files before publishing.
