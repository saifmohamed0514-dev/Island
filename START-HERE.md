# Start here — publishing Island for the first time

Everything is local right now. You do not need to create a website or pay for hosting to share the source.

1. Create a GitHub account if you do not have one.
2. In GitHub, choose **New repository**, name it **Island**, and choose **Public**. Do not add a second README or license: this project already contains them.
3. Use GitHub Desktop: **File → Add local repository**, choose this project folder (the `Source` folder if you extracted the complete ZIP), and publish it to the empty repository. If needed, use GitHub Desktop's existing-repository instructions. Keep the GPL license and third-party notices.
4. Read `App-Read-Me.txt` in the package and `FEATURE-STATUS.md`. Describe the app as a development preview until the missing features and verification are finished.
5. To share a manual download, build with `scripts/build.sh`, create a GitHub Release and attach `dist/Island.zip`. Users can download the ZIP. The local preview is not Apple-notarized, so macOS may block it on another Mac; explain that clearly.
6. Automatic in-app updates need a one-time signing-key and feed setup. Follow `docs/RELEASING.md` before your first auto-updating public build.

## Every later update

Make and test changes, increase both version and build number, build a new ZIP, prepare its signed `appcast.xml`, and attach both to a GitHub Release. Your app checks your own feed for newer builds. Do not reuse a build number.

## What not to upload

No passwords, private update keys, Apple signing certificates, access tokens or personal files. Only your Sparkle **public** key belongs in the project. Private keys belong in Keychain and, if you later use Actions, GitHub Actions secrets. The included `.gitignore` excludes common credential-file types, but always review staged files before publishing.
