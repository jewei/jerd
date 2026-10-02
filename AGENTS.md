# Jerd instructions

Report in ASD-STE100 Simplified Technical English.

## Scope

Keep Jerd small. Implement only the approved features below.

- Serve all enabled registered sites together with each site's selected PHP runtime.
- Use approved host/trust setup and standard loopback ports for local HTTPS.
- Provide PHP, Composer, and Laravel CLI commands. Select PHP from the registered
  project that contains the working directory, or use the default outside projects.
- Manage independent MySQL, PostgreSQL, and Redis services with native runtimes,
  private data, and per-service controls. Keep DBngin services and data separate.
- Provide a separate local Mailpit service with SMTP capture, an inbox, and Laravel settings.
- Provide native RustFS storage. On bucket Save, start the owned service as needed
  and verify the bucket before reporting Ready.
- Use the tab order Dashboard, Sites, Databases, Storage, Mail.
- Use Dashboard's two-pane navigation in this order: Dashboard, Appearance,
  Runtimes, Advanced, About. Settings commands open Appearance in the main window.
- Provide independent menu bar and Dock controls and the existing icon designs.
- List managed runtime versions and support runtime checks and installation.
- Put credits, disclaimer, versions, and app update controls in About.
- Use Sparkle with the public `jewei/jerd` repository and a published HTTPS feed.
  Verify signed feeds and archives. Preserve normal graceful service shutdown.
  Keep private signing keys in the local Keychain, outside the repository.
The user also approved adapting the Claude Meter release procedure for Jerd.
Prepare and validate signed, notarized private candidates. Keep publication
as a separate command.

The approved runtime and Sparkle updates replace the earlier limit on update work.
After feature work, use three fresh independent agents to review code,
architecture, and performance. Fix the agreed findings.

## Safety boundaries

- Keep project code and all runtime processes unprivileged.
- Default tests must not change `/etc/hosts`, trust stores, shell files,
  system services, or privileged helpers. Product setup must use explicit
  user approval and narrowly scoped, authenticated system integration.
- Do not stop another application's service to obtain a port.
  Exception: on 2026-10-01 the user explicitly approved stopping Herd's
  confirmed web service to free ports 80/443 for the Jerd system test.
  Use Herd's own service control. This does not permit using its runtimes
  or assets in Jerd.
- Do not use Herd binaries or assets. Do not install Homebrew.
- Use explicit executable URLs and argument arrays. Do not use a shell for
  runtime execution. Do not run project code for project detection.
- Remove site records only. Never delete a registered project.
- Bind test servers to loopback on ports above 1023. Use an isolated CA.
  Verify TLS with that CA. Never use `curl -k`.
- Do not report browser trust or architecture support without evidence.
- Stop only owned processes. Do not use `killall` or `pkill`.
- Default tests must not require root or change system configuration.
- Preserve corrupt data. Do not replace it with an empty configuration.
- Keep file and process work off the main actor.
- Preserve database data when stopping or removing a service registration.
  Never reuse an existing database directory with a different runtime version.
  Database shutdown must be graceful; a timeout must not force-kill the server.
- Keep captured mail after Stop or Quit. Use loopback-only SMTP and HTTP ports.
  Do not configure external mail relay, forwarding, or inherited mail settings.
- Keep storage buckets, objects, and credentials after Stop or Quit. Use an
  owned RustFS runtime with loopback-only S3 and console ports. New buckets are
  private unless the user selects public read. Never allow anonymous writes.

## Build and test

```sh
swift test --package-path Packages/JerdCore
xcodebuild -project Jerd.xcodeproj -scheme Jerd -configuration Debug \
	-derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
```

Run the opt-in test only with explicitly selected, trusted local binaries:

```sh
JERD_INTEGRATION=1 JERD_PHP_CLI=/absolute/path/php \
JERD_PHP_FPM=/absolute/path/php-fpm JERD_CADDY=/absolute/path/caddy \
swift test --package-path Packages/JerdCore --filter TLSSmokeTests
```

`project.yml` is the XcodeGen source. The generated Xcode project is included.
Run `xcodegen generate` after project structure changes if XcodeGen is available.

For the complete test procedures, see [Run tests](Docs/Testing.md).
