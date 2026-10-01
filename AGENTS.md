# Jerd instructions

Report in ASD-STE100 Simplified Technical English.

## Scope

The user approved the real PHP/TLS engine test, approved host/trust setup, and
standard-port integration. On 2026-10-01 the user clarified that Jerd must
serve all enabled registered sites at the same time. Implement that behavior
with each site's selected PHP runtime. Keep the app small. Do not expand into
updates or release distribution except for the approved development bootstrap.
The user also approved PHP, Composer, and Laravel installer CLI companions.
Composer must use the PHP selection for the registered site containing the
working directory, with the default used outside registered sites.
The user also approved a first database-service version after research into
DBngin. Add independent MySQL, PostgreSQL, and Redis services with native
runtimes, private data folders, and per-service controls. Keep existing DBngin
services and data separate. The user then approved a Mailpit-like feature.
Add a separate local mail service with an inbox, SMTP capture, service controls,
and Laravel settings. Keep existing mail services and inboxes separate.
The user then approved native RustFS storage with an Add bucket form. Saving a bucket must start the owned
storage service as needed and verify the bucket before reporting it ready.
The user then approved a Dashboard, independent menu bar and Dock controls,
selection of the existing app icon designs, a managed runtime version list,
and runtime update checks and installation. This replaces the earlier limit
on runtime updates. Use the tab order Dashboard, Sites, Databases, Storage, Mail.
After all features are complete, use three fresh independent agents to review
code, architecture, and performance. Fix the agreed findings.

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
