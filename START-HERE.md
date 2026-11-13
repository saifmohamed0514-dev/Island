# Start here — publishing Island for the first time

Everything is local right now. You do not need to create a website or pay for hosting to share the source.

1. Create a GitHub account if you do not have one.
2. In GitHub, choose **New repository**, name it **Island**, and choose **Public**. Do not add a second README or license: this project already contains them.
3. Use GitHub Desktop: **File → Add local repository**, choose this project folder (the `Source` folder if you extracted the complete ZIP), and publish it to the empty repository. If needed, use GitHub Desktop's existing-repository instructions. Keep the GPL license and third-party notices.
4. Read `App-Read-Me.txt` in the package and `FEATURE-STATUS.md`. Describe the app as a development preview until the missing features and verification are finished.
5. Keep one installed copy at Applications → Island. To share a manual download, build with `scripts/build.sh`, commit the matching source, then run `scripts/package-dmg.sh`. Create a GitHub Release and attach `dist/Island-VERSION.dmg` for drag-to-Applications installation, alongside the update files described below. The local preview is not Apple-notarized, so macOS may block it on another Mac; explain that clearly.
6. Automatic in-app updates have consent and scheduling controls. Double-click `Set Up Updates.command` in Source, paste your own GitHub repository URL and rebuild before your first public auto-updating release. The setup keeps the private signing key in Keychain. This Mac already has the Island signing key prepared; other developers create their own. Follow `docs/RELEASING.md` for publishing.

The complete download also contains Source/Integrations/README.md for local ChatGPT/Codex/Claude/Cursor setup and Source/Power/README.md for the optional Low Power Mode service. Never include your private bridge folder or client settings in a release.

## Every later update

Make and test changes, increase both version and build number, build a new ZIP, prepare its signed `appcast.xml` with `scripts/prepare-release.py` (the local command reads the signing key from Keychain), and attach both to a GitHub Release. Your app checks your own feed for newer builds. Do not reuse a build number.

## What not to upload

No passwords, private update keys, Apple signing certificates, access tokens or personal files. Only your Sparkle **public** key belongs in the project. Private keys belong in Keychain and, if you later use Actions, GitHub Actions secrets. The included `.gitignore` excludes common credential-file types, but always review staged files before publishing.


## A simple first-release checklist

1. Create an empty public repository at https://github.com/new, named Island. Leave README, .gitignore and license creation off; they already exist here.
2. Give your developer or assistant its full URL. Configure Island’s feed with that repository and the existing public key, then rebuild before uploading the first auto-updating download. A DMG built before that step will have no update channel.
3. Publish the reviewed source to the repository with GitHub Desktop’s Add local repository and Publish repository. Choose this Source folder, not the whole downloads folder. For an already-created empty repository, use Repository settings → Remote or the official existing-repository instructions to connect it before pushing.
4. On the repository page, choose Releases → Draft a new release. Use the exact version tag printed by the release preparation tool, a clear preview title and release notes.
5. Attach Island-VERSION.dmg, Island.zip and appcast.xml. Save draft while checking them. The DMG is the human download; the ZIP is the signed update payload; appcast.xml tells Island which build is available. Keep those two updater asset names exactly as shown.
6. The current automatic-update feed requires a regular latest release, rather than GitHub’s pre-release checkbox. Publish only after all files and source are ready. Updates remain optional in Island Settings → Updates.
7. For each later release, increase version and build number, rebuild, prepare a new signed appcast, create the DMG and publish the matching source and assets. Uploading source changes alone does not ship an app update.

Official walkthroughs: [Create a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository), [Create a release and attach downloads](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository), [Sparkle update publishing](https://sparkle-project.org/documentation/publishing/).
