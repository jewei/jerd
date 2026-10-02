# Publish an app update

The current build is for local development. Release publication is blocked until
all bundled executables have suitable Developer ID signatures and runtime settings.
The preparation scripts currently retain upstream or ad hoc runtime signatures.
The app's outer signature does not make those executables ready for notarization.

Before this procedure, implement and verify release signing for the runtime files.
Update their digest receipts after signing, then embed them and sign the app.
Do not use `codesign --deep` to replace that signing sequence.

Use the Mac that holds the `dev.jerd.sparkle` signing key in its local Keychain.
Use a Developer ID identity and a configured `notarytool` Keychain profile.
Keep the private key outside the repository and GitHub Actions.

Run these commands from the repository root. The example uses version `0.1.1`;
replace it with the version you intend to publish.
For tool behavior, see [Sparkle publishing](https://sparkle-project.org/documentation/publishing/)
and [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Build and verify the app

1. Increase `CURRENT_PROJECT_VERSION` in `project.yml` above every published build.
2. Set `MARKETING_VERSION` to the release version.
3. Run `xcodegen generate`.
4. Prepare the required runtimes with [Build Jerd](Build.md).
5. Complete the applicable checks in [Run tests](Testing.md).
6. Build and verify the signed Release app with [Build Jerd](Build.md).
7. Inspect its `Contents/Info.plist` for the feed URL, public key, and signed-feed settings.
8. Check the app and runtime architectures against the intended release systems.

Retain the existing bundle identifier, feed URL, and public key.
A signing-key change requires a planned migration for installed clients.

## Notarize the archive

1. Create a private staging folder and a submission archive:

   ```sh
   mkdir -p .build/release-0.1.1
   ditto -c -k --sequesterRsrc --keepParent \
		.build/signed/Build/Products/Release/Jerd.app \
		.build/release-0.1.1/submission.zip
   ```

2. Replace `JERD_NOTARY` with your configured Keychain profile, then submit:

   ```sh
   xcrun notarytool submit .build/release-0.1.1/submission.zip \
		--keychain-profile JERD_NOTARY --wait
   ```

3. Continue only after Apple reports `Accepted`.
4. Staple and validate the ticket:

   ```sh
   xcrun stapler staple .build/signed/Build/Products/Release/Jerd.app
   xcrun stapler validate .build/signed/Build/Products/Release/Jerd.app
   codesign --verify --deep --strict .build/signed/Build/Products/Release/Jerd.app
   spctl --assess --type execute --verbose .build/signed/Build/Products/Release/Jerd.app
   ```

5. Create the final archive in a separate folder:

   ```sh
   mkdir -p .build/release-0.1.1/updates
   ditto -c -k --sequesterRsrc --keepParent \
		.build/signed/Build/Products/Release/Jerd.app \
		.build/release-0.1.1/updates/Jerd-0.1.1.zip
   ```

Do not change the app or archive after the next signing step.

## Sign the app feed

1. Write the release notes to `.build/release-0.1.1/updates/Jerd-0.1.1.md`.
2. Copy the current feed into the update folder:

   ```sh
   cp appcast.xml .build/release-0.1.1/updates/appcast.xml
   ```

3. Generate the signed archive entry and feed:

   ```sh
   .build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
		--account dev.jerd.sparkle \
		--download-url-prefix https://github.com/jewei/jerd/releases/download/v0.1.1/ \
		--link https://github.com/jewei/jerd \
		--embed-release-notes --maximum-deltas 0 \
		.build/release-0.1.1/updates
   ```

4. Check the archive URL, build number, minimum macOS version, and hardware requirements in the generated feed.
5. If you change the feed, sign it again:

   ```sh
   .build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
		--account dev.jerd.sparkle .build/release-0.1.1/updates/appcast.xml
   ```

6. Verify the feed signature:

   ```sh
   .build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
		--account dev.jerd.sparkle --verify .build/release-0.1.1/updates/appcast.xml
   ```

Do not infer runtime support from the app's deployment target.
Set requirements to match the systems that passed release testing.

## Publish and check the update

1. Commit the release source and version changes.
2. Create the corresponding Git tag.
3. Create a draft GitHub release for that tag in `jewei/jerd`.
4. Attach the exact signed `Jerd-0.1.1.zip` archive.
5. Review the release notes and publish the release.
6. Download the public asset and compare its SHA-256 with the local archive.
7. Copy the verified generated feed to the repository's `appcast.xml`.
8. Commit and push that feed to `main`.
9. Download the [public feed](https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml) and verify its signature.
10. From an older installed build, select **Check for Updates**.
11. Install the update and verify graceful shutdown, relaunch, and retained service data.

Publish the archive before the feed so clients can retrieve every advertised update.
