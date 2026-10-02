# Build Jerd

Use Xcode with Swift 6 on macOS. The runtime preparation scripts require
Apple Silicon. For supported and tested systems, see the [verification record](Verification.md).

## Prepare the runtimes

1. From the repository root, prepare PHP, Caddy, Composer, and Laravel:

   ```sh
   python3 Scripts/prepare-development-runtimes.py
   ```

2. To include database services, prepare their runtimes:

   ```sh
   python3 Scripts/prepare-database-runtimes.py
   ```

   This step requires the Xcode compiler and GnuPG. It does not install them.

3. To include local mail, prepare Mailpit:

   ```sh
   python3 Scripts/prepare-mail-runtime.py
   ```

4. To include S3 storage, prepare RustFS:

   ```sh
   python3 Scripts/prepare-storage-runtime.py
   ```

The scripts verify the pinned downloads and retain license notices.
The build embeds the prepared files. Without these files, the app builds but
reports the missing runtimes. For download checks, see [runtime supply](Architecture.md#runtime-supply-and-release-scope).

## Build for UI development

Run this command from the repository root:

```sh
xcodebuild -project Jerd.xcodeproj -scheme Jerd -configuration Debug \
	-derivedDataPath .build/xcode \
	-clonedSourcePackagesDirPath .build/SourcePackages \
	CODE_SIGNING_ALLOWED=NO build
```

The command resolves Sparkle 2.10.0 and builds the app without a signing identity.
This build cannot complete privileged HTTPS setup.

## Build a signed local app

1. Replace the team and identity values, then build:

   ```sh
   xcodebuild -project Jerd.xcodeproj -scheme Jerd -configuration Release \
		-derivedDataPath .build/signed \
		-clonedSourcePackagesDirPath .build/SourcePackages \
		DEVELOPMENT_TEAM=YOURTEAMID \
		CODE_SIGN_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)' \
		CODE_SIGN_STYLE=Manual build
   ```

2. Verify the app signature:

   ```sh
   codesign --verify --deep --strict .build/signed/Build/Products/Release/Jerd.app
   ```

3. Copy the app to its intended location before you approve HTTPS setup.
4. Open the app from that location.

Keep the app at the same path while its helper is registered.
Before you move the app, select **System setup > Remove system setup**.
Before you replace a running app, use **Quit Jerd** and wait for its services to stop.
Use an atomic bundle replacement so the running helper's files remain valid.

For distribution, complete [Publish an app update](PublishUpdate.md).
A local signature alone does not establish notarization. The bundled runtime
executables still need a release-signing step with updated digest receipts.

## Change the Xcode project

1. Edit `project.yml`, which is the XcodeGen source.
2. Run `xcodegen generate`.
3. Include the generated `Jerd.xcodeproj` changes with the source change.

Keep the Sparkle package version and `Package.resolved` consistent.
