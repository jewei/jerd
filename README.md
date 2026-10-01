# Jerd

Jerd is a native macOS app for local PHP projects. Choose a folder, check the
suggested `folder-name.test` hostname, and approve HTTPS setup. The current
implementation serves all enabled sites at the same time. Each site uses its
selected PHP runtime. The bundled versions are PHP 8.5.11 and Caddy 2.11.4.
The app also includes Composer 2.10.3 and Laravel Installer 5.32.0.
It has no remote Swift package dependencies.

**Verification status:** The signed app serves `https://games-jp.test` and
`https://games-hk.test` at the same time on the development Mac. Safari, Brave,
and the normal macOS HTTPS trust check pass for both sites. Helper
setup, Start/Stop, app restart, system cleanup, and setup restoration pass.
All 40 core tests pass, including five real PHP/TLS cases. This is a local
development build, not a notarized release. See [the verification record](Docs/Verification.md).

## Requirements

- macOS 14 or later and Xcode with Swift 6.
- The prepared runtime payload is for native Apple Silicon only.
- An Apple signing identity is required for privileged setup. The app and
  helper must have the same signing team and must not have `get-task-allow`.
- Ports 80 and 443 on `127.0.0.1` must be free. Stop a conflicting server in
  its own app. Jerd does not stop another application's services.

The tested host is arm64, macOS 27.0.1, Xcode 27.0, Swift 6.4. The deployment
target does not establish Intel or macOS 14 runtime support.

## Prepare development runtimes

```sh
python3 Scripts/prepare-development-runtimes.py
```

This downloads the fixed PHP/Caddy artifacts in `DevelopmentRuntimes/pins.json`
from `lerd-env/php` and `caddyserver/caddy`. It verifies GitHub release metadata
over HTTPS, checks the reviewed asset ID, size, and archive digest, then
extracts named regular files only. License notices and receipts are retained.
It does not run an upstream PHP installer or load shared extension modules.

Composer's PHAR comes from [getcomposer.org](https://getcomposer.org/download/).
Its published checksum and fixed local SHA-256 pin must match. The license is
retained. Jerd PHP then runs Composer to install the Laravel installer from
the committed dependency lock file, with plugins and scripts disabled.
The prepared dependency files and license notices are retained and hashed.
Laravel dependency downloads use Composer's lock references and HTTPS;
these are not publisher-signed or independently digest-pinned archives.

This is the explicitly approved development bootstrap. It does not verify
a publisher signature and is not the production runtime update system.
The release installer, signed update metadata, and supported extension
profiles remain Milestone 4 work.

The build embeds the verified files. On first launch, Jerd checks their
file digests, installs them in its own data directory, and inspects the
actual binaries. PHP becomes the default if no default is set. Existing
runtime selections are retained. If the payload is absent, the app shows
the error; local executable selection remains available for development.
Jerd does not use Herd binaries or install Homebrew. Shell commands are an
explicit, optional setup step described below.

## Build and run

The generated `Jerd.xcodeproj` is included. Open it and select the **Jerd**
scheme. `project.yml` is the source for XcodeGen project changes.

For core and UI development without system setup:

```sh
xcodebuild -project Jerd.xcodeproj -scheme Jerd -configuration Debug \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
```

For a signed local build, replace the team and identity placeholders:

```sh
xcodebuild -project Jerd.xcodeproj -scheme Jerd -configuration Release \
  -derivedDataPath .build/signed DEVELOPMENT_TEAM=YOURTEAMID \
  CODE_SIGN_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)' \
  CODE_SIGN_STYLE=Manual build
codesign --verify --deep --strict .build/signed/Build/Products/Release/Jerd.app
open .build/signed/Build/Products/Release/Jerd.app
```

Keep the signed app at a stable path while its helper is registered.
Unregister the helper with **Remove system setup** before moving that app.
Before replacing it at the same path, quit Jerd and stop its helper through
launchd so that the next connection loads the matching helper. For manual
acceptance testing, copy the signed app to Applications
first. This build is not notarized or ready for distribution.

## Use the app

1. Select **Add site**, then choose an existing folder. The display name and
   hostname are filled in. You can edit the hostname on the same screen.
2. Check the document root. Laravel file detection suggests `public`.
   Confirm the directory that can be served, then save the registration.
3. Check the HTTPS setup screen that follows Save. It lists all enabled
   hostnames and the CA fingerprint. You can also select **Enable HTTPS** later.
4. Select **Approve and start**. macOS can require administrator approval
   or approval in **Login Items & Extensions**. If approval is pending, allow
   Jerd there, then select **Approve and start** again.
5. Jerd shows **Ready** only after its PHP/Caddy checks and a request using
   normal macOS hostname resolution and certificate trust pass for every site. Then use
   **Open in Browser**.

Setup adds one owned section to `/private/etc/hosts`, imports the installation's
CA into the system keychain, and trusts that CA for TLS server certificates.
This CA trust covers any hostname, not only the registered sites. Jerd still
routes only registered `.test` hostnames on loopback. The app displays macOS
certificate consent through an authenticated
callback from the helper. PHP and Caddy remain unprivileged. The helper binds loopback ports
80/443 and passes the listening sockets to the app. It receives no project
paths or executable commands. The CA key remains in the user's data directory.

One Caddy process serves all enabled sites. Sites with the same PHP runtime
share a PHP-FPM process group. Different runtime selections use separate groups.
Each hostname routes to its own document root and selected PHP socket.
Laravel's `public/storage` link can serve public images and other static files.
Project-root storage stays blocked. PHP files under `/storage` are also blocked.
**Start all sites** and **Stop all sites** control the environment. Changes to a
running site's settings restart the environment, which briefly affects all sites.
Adding a hostname requires HTTPS approval for the updated list.
Closing the window keeps the
menu app running; **Quit Jerd** stops its services and releases the sockets.

Disabling a site stops its route but retains its registration and approved
hostname. Removal deletes that registration and its host mapping.
The CA remains trusted until the last approved host or all system setup is removed.
Other enabled sites restart if the environment was running. Project files remain.
The toolbar's **System setup → Remove system setup** removes all recorded
hosts, CA trust/certificate, and helper registration. It retains
site records and user data. It does not delete the private CA files or runtimes.

**PHP and Caddy** shows actual versions and CLI/FPM modules. A pinned runtime
never falls back to another version. Reassign
all users of a runtime before removing its record.

## PHP, Composer, and Laravel commands

After the signed app has installed its bundled tools, run this optional setup:

```sh
python3 Scripts/setup-php-cli.py
exec zsh -l
php --version
composer --version
laravel new --help
```

The setup copies Jerd's native CLI launcher and creates `php`, `composer`, and
`laravel` links in `~/Library/Application Support/Jerd/bin`. It adds that
directory to zsh PATH, with private backups of `.zprofile` and `.zshrc`.
It refuses to replace unrelated commands in the Jerd directory.

Each command reads the saved app configuration. Inside a registered project,
including its nested directories, it selects that site's PHP. The most specific
registered project wins. Outside registered projects, it selects the default.
A missing pin is an error. Disabling web serving does not remove the PHP pin.
Composer and Laravel run through that selected PHP executable. Child `php`
commands use the same selector. Arguments, standard streams, and exit status
are passed through. No new Laravel project is created during setup.

Selection uses the current working directory. Run `cd` into the project before
Composer commands; `composer --working-dir` does not change this selection.
Changing a site's pin or the default in Jerd applies to the next command.
The included PHP payload currently contains only 8.5.11; other versions need
an explicitly inspected CLI/FPM pair. Multiple bundled PHP versions are later work.

Rerun the setup script after upgrading the CLI launcher. To remove its shell
integration, remove the marked Jerd block from both shell files and remove only
the Jerd command links/launcher. Keep any unrelated shell edits. Composer
`self-update` changes the managed PHAR and will fail the next app integrity
check; update the prepared payload and rebuild instead.

## Tests

Default tests need no root access and do not change system files or trust:

```sh
swift test --package-path Packages/JerdCore
```

Run the real PHP/TLS tests with the prepared binaries:

```sh
JERD_INTEGRATION=1 \
JERD_PHP_CLI="$PWD/.build/development-runtimes/php/php-native-8.5" \
JERD_PHP_FPM="$PWD/.build/development-runtimes/php/php-native-fpm-8.5" \
JERD_CADDY="$PWD/.build/development-runtimes/caddy/caddy" \
swift test --package-path Packages/JerdCore
```

The test uses separate high loopback ports and an isolated CA. It verifies
TLS with `curl --cacert --resolve --noproxy '*'`; it never uses `-k`.
It checks real PHP output, static files, sensitive paths, unknown hosts,
redirects, listeners, FPM failure, and cleanup. It runs both direct listeners
and inherited sockets. Two-site cases check separate roots with one shared
PHP group and with two separate PHP groups. Both use the available PHP 8.5.11
binary; execution with two different PHP versions still needs a separate check.
The public storage case verifies linked asset bytes and rejects private storage,
hidden files, PHP source, and PHP execution under the storage URL.
Set `JERD_KEEP_TEST_FILES=1` to retain diagnostic files.
Never install a test CA in a system trust store.

The signed XPC harness is documented in [Verification](Docs/Verification.md).
It uses an anonymous listener and high ports. It installs no system service.

## Data and recovery

```text
~/Library/Application Support/Jerd/
  configuration.json
  configuration.previous.json
  runtimes/             checked binaries, receipts, and license notices
    cli-tools.json      installed Composer and Laravel script paths
  bin/                  optional native CLI launcher and command links
  shell-backups/        private shell-file backups from explicit CLI setup
  environment/
    installation-id     stable identity for this installation's CA
    configuration/      generated Caddy/FPM/INI files
    certificates/       private CA keys and issued certificates
    logs/               operational output
/Library/Application Support/JerdHelper/   created only by approved setup
  registration.json     owner UID, hostnames, installation ID, CA certificate
  hosts.previous        previous host file for recovery
  pending.json          present only during a transaction or failed recovery
```

Each run uses a new private temporary directory for the FPM Unix sockets.
The helper reads version 1 and 2 records and retains their old hostname-limited
trust policy. The updated HTTPS review requests approval for server TLS trust,
which Chromium browsers can read. Version 3 records store that approved policy
so failed changes can restore the previous policy exactly.
Configuration writes are atomic and retain a valid backup. Corrupt documents
are preserved and block changes. Restore a reviewed backup after inspection;
there is no destructive automatic reset.

If helper setup is interrupted and `pending.json` remains, further system
changes stop. Preserve the helper directory and inspect the recorded hostnames,
CA fingerprint, and hosts backup before manual recovery. Do not copy the whole
backup over a hosts file that has since changed. Automated recovery is pending.

Use trusted projects only. Project PHP has access to your user account; the
served directory is not a filesystem sandbox. Logs do not rotate yet. A forced
app kill can leave runtime processes alive; a new app instance reports the port
conflict and does not signal saved PIDs. Normal quit and runtime-exit cleanup
are tested. Full crash recovery, updates, and a complete
uninstaller remain later work.

See [Architecture](Docs/Architecture.md) and [Implementation plan](Docs/ImplementationPlan.md).
