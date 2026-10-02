# Jerd

Jerd is a native macOS app for local PHP projects. Choose a folder, check the
suggested `folder-name.test` hostname, and approve HTTPS setup. The current
implementation serves all enabled sites at the same time. Each site uses its
selected PHP runtime. The bundled versions are PHP 8.5.11 and Caddy 2.11.4.
The app also includes Composer 2.10.3 and Laravel Installer 5.32.0.
The Databases tab manages separate MySQL 8.4.11, PostgreSQL 18.6, and Redis 8.8.3
services. Each service has its own port, password, and persistent data folder.
The Storage tab creates S3 buckets with a managed RustFS 1.0.0 service.
The Mail tab runs Mailpit 1.31.3 for local SMTP capture and a persistent web inbox.
The Dashboard shows the four service areas. Appearance controls Dock and menu bar
visibility and seven app icon choices. Runtimes lists installed versions and
runtime updates.
It has no remote Swift package dependencies.

**Verification status:** The signed app serves `https://games-jp.test` and
`https://games-hk.test` at the same time on the development Mac. Safari, Brave,
and the normal macOS HTTPS trust check pass for both sites. Helper
setup, Start/Stop, app restart, system cleanup, and setup restoration pass.
All 73 core tests pass, including five real PHP/TLS cases with PHP 8.5.11 and
8.4.26, a real three-engine database test, SMTP capture, S3 persistence, and
mail/storage update recovery. Real download and install tests also pass for all
nine managed runtimes. This is a local
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

This PHP/Caddy setup is the approved development bootstrap. Runtime updates use
the publisher sources described below. Signed Jerd release metadata, notarized
distribution, and supported extension profiles remain later work.

The build embeds the verified files. On first launch, Jerd checks their
file digests, installs them in its own data directory, and inspects the
actual binaries. PHP becomes the default if no default is set. Existing
runtime selections are retained. If the payload is absent, the app shows
the error; local executable selection remains available for development.
Jerd does not use Herd binaries or install Homebrew. Shell commands are an
explicit, optional setup step described below.

## Dashboard and preferences

The tab order is Dashboard, Sites, Databases, Storage, Mail. Dashboard has a
left menu with Dashboard, Appearance, Runtimes, Advanced, and About. Each item
opens in the right pane. **Settings…** in the app or menu bar menu and
`Command-,` open Appearance in the main window. **About Jerd** opens About.
Appearance has independent menu bar and Dock controls. When both are off,
open Jerd from Applications to
return to its window. The original icon and six existing designs are available;
the chosen icon is used in the Dock and menu bar while the app is open.

In Runtimes, select **Check for runtime updates**, choose an available version, then
install it. PHP supports **Install & use** and **Install only**. A new default
restarts running sites, while pinned sites keep their selected PHP version.
Only stable macOS packages for this Mac are shown. PHP 8.6 will appear when the
configured PHP source publishes a matching stable package.

Database runtime installation adds a version for new services. Existing database
services keep their runtime and data directory. MySQL uses 8.4 LTS; PostgreSQL
uses the 18 series from Postgres.app. Redis needs the local Xcode compiler.
Mailpit and RustFS updates stop the owned service, copy its data and settings
to a private `runtime-backups` folder, start and check the new runtime, then
restore its previous running state. A failed update restores the saved copy.
Backups remain available in the service folder. Advanced settings contains
local executable selection and PHP inspection details. About shows the app
version, build, macOS version, app architecture, project credits, and a local
development disclaimer. Its app-update control is a disabled placeholder.
Sparkle integration is planned for a later change. Runtime updates remain
available in Runtimes.

Downloads use HTTPS, host restrictions, byte limits, and a SHA-256 check before
extraction. MySQL uses Oracle's pinned RSA publisher key and its detached
signature. Laravel dependencies use Composer in a private folder with scripts
and plugins disabled. This uses upstream HTTPS and Composer checks; it does not
add independent publisher signatures to those dependencies. Version folders
and receipts remain in Jerd's Application Support directory.

To prepare the database payload as well:

```sh
python3 Scripts/prepare-database-runtimes.py
```

This requires the installed Xcode compiler and GnuPG. It does not install
Homebrew or a system database service. Fixed pins in `DatabaseRuntimes/pins.json`
select Oracle's MySQL archive, the PostgreSQL runtime from Postgres.app, and
Redis source. The script checks MySQL's publisher signature, all archive
SHA-256 values, and the Postgres.app code signature. Redis is compiled locally.
The build embeds the prepared files; Jerd verifies and copies them to its own
runtime directory. The current development database payload is about 1.1 GB.
It includes upstream shared libraries and notices. Downloads on demand and
smaller release packages are later work.

To prepare the mail payload:

```sh
python3 Scripts/prepare-mail-runtime.py
```

This downloads the official Mailpit 1.31.3 arm64 archive from its fixed GitHub
release. `MailRuntime/pin.json` records its size and SHA-256 digest. The script
checks both, extracts the binary and upstream notices, and records file hashes.
Embedding and app installation check those hashes again. The prepared payload
is about 26 MB. It does not use an existing Mailpit installation or run a system
installer. This is a development pin, not a publisher-signed update manifest.

To prepare the storage payload:

```sh
python3 Scripts/prepare-storage-runtime.py
```

This downloads the official RustFS 1.0.0 Apple Silicon binary and its license.
`StorageRuntime/pin.json` fixes the archive size, SHA-256, and license digest.
Only the named regular executable is extracted. File hashes are checked at
build and app installation time. The prepared payload is about 225 MB.

## Database services

1. Open **Databases → Add database**.
2. Choose MySQL, PostgreSQL, or Redis. Check the version, service name, and port.
   Jerd suggests a free port and reserves a different port for each registration.
3. Select **Create and start**. Ready requires a successful authenticated query
   or Redis `PING`, plus inspection of the process's network listeners.
4. Use **Copy Laravel settings** or **Copy password** for your application or
   database client. Jerd does not edit project `.env` files.

The first build provides one fixed version per engine. It supports multiple
instances of each engine. Each listens on `127.0.0.1` as the current user.
The SQL user is `jerd`; the initial database is `jerd` for MySQL and `postgres`
for PostgreSQL. Redis uses its `default` user and database 0. Passwords are
generated separately for each service and stored in private files with mode 0600.
Passwords are passed through private client files or the Redis client environment,
not process arguments. These local connections do not have database TLS configured.

Start and Stop affect only the selected service. Sites and other databases
continue to run. **Remove registration** stops that service and keeps all its
database files. Use **Show data folder** and **Open log** to inspect them.
Quitting Jerd requests graceful database shutdown. A 30-second timeout keeps
the process tracked and cancels app termination; it does not force-kill it.
Services start manually after the app reopens.

A service's database version is fixed when its data is created. Use a new
service and the engine's export/import tools to move to another version.
Jerd does not reuse DBngin runtimes or data. Existing DBngin services can run
beside Jerd on different ports.

## Local storage

1. Open **Storage → Add bucket**.
2. Enter the bucket name. Leave public read off for a private bucket, or turn
   it on to serve local test assets without signed read requests.
3. Select **Save**. Jerd starts its own RustFS service, creates the bucket,
   applies its access policy, and checks the bucket before reporting Ready.
4. Select **Copy Laravel settings** and apply them to your project. The settings
   include the endpoint, bucket, generated keys, region, and path-style option.
   Laravel needs its S3 filesystem adapter. Jerd does not edit project files.
5. Use **Open console** to upload and inspect files. Sign in with the values from
   **Copy access key** and **Copy secret key**.

The tabs are **Sites, Databases, Storage, Mail**. Buckets share one native RustFS
process and one generated credential pair. Jerd suggests free S3 and console
ports, starting at 9000 and 9001. Both listen only on `127.0.0.1`. Connections
use local HTTP. Public read grants only `s3:GetObject`; anonymous listing,
uploads, and deletion remain blocked.

The data and credentials stay after Stop or Quit. Start storage after reopening
Jerd. Use **Storage settings** to change ports while stopped. An incomplete
bucket setup stays recorded and can be retried. A missing bucket is reported;
Jerd does not silently recreate it. The native list shows buckets added in Jerd.
The console can manage other buckets directly. A stopped or failed service
never reports its buckets as Ready.

Storage uses an app-owned runtime and data folder. It does not use Docker,
Homebrew, or another application's RustFS instance. Shutdown is graceful;
a timeout keeps the app open. The runtime version is fixed to its data folder.

## Local mail

1. Open **Mail** and select **Start mail**.
2. Select **Copy Laravel settings** and apply the settings to the project you
   want to test. Jerd does not edit project files. The copied values select
   local SMTP, clear an old mail URL, and disable authentication and encryption.
3. Select **Send test email** to check the local SMTP route, or send mail from
   your application. External mail delivery is not configured.
4. Select **Open inbox** to open Mailpit in your default browser. It provides
   message search, HTML and text views, headers, attachments, and deletion.

Jerd suggests free SMTP and web ports. Both listeners use `127.0.0.1` and run
as your user. Existing Mailpit or other services keep their own ports and data.
Use **Edit ports** while stopped to change the ports; the inbox is retained.
The inbox uses one private SQLite database. Automatic message deletion is
disabled, so use the inbox to delete messages you no longer need.

Stop and Quit retain captured messages. Mailpit has 30 seconds to stop
gracefully; a timeout cancels app termination and retains the owned process.
Start is manual after reopening Jerd. An inbox cannot be opened with a different
saved runtime version, and a previous live process blocks a second start.
There is no automatic mail migration or recovery after an app crash.

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

Run the real database test with the prepared independent runtimes:

```sh
JERD_DATABASE_INTEGRATION=1 \
JERD_DATABASE_RUNTIMES="$PWD/.build/database-runtimes" \
swift test --package-path Packages/JerdCore --filter Database
```

The test creates temporary instances of all three engines on high loopback
ports. It checks real writes, wrong-password rejection, persistence after
restart, independent shutdown, process-exit detection, version mismatch,
and retained data after registration removal. No existing databases are used.

The separate `JERD_OCCUPIED_DATABASE_PORT` option enables a read-only regression
check against an existing wildcard TCP listener. It checks that registration
rejects the port without changing or connecting to that service. This passed
with DBngin Redis on port 6379.

Run the real SMTP and inbox test with the prepared Mailpit binary:

```sh
JERD_MAIL_INTEGRATION=1 \
JERD_MAIL_RUNTIME="$PWD/.build/mail-runtime/mailpit-1.31.3-arm64" \
swift test --package-path Packages/JerdCore --filter Mail
```

It uses a temporary inbox and high loopback ports. It sends a MIME message over
SMTP, reads text, HTML, and attachment bytes through the API, rejects an unknown
HTTP Host, changes ports, and checks persistence after restart. It also checks
process-exit detection, missing-database preservation, and runtime identity.
It does not access an existing inbox or configure external mail delivery.

The signed XPC harness is documented in [Verification](Docs/Verification.md).
It uses an anonymous listener and high ports. It installs no system service.

The storage test uses an explicitly selected RustFS runtime and temporary data:

```sh
JERD_STORAGE_INTEGRATION=1 \
JERD_STORAGE_RUNTIME="$PWD/.build/storage-runtime/rustfs-1.0.0-arm64" \
swift test --package-path Packages/JerdCore --filter StorageIntegrationTests
```

It checks automatic bucket startup, signed S3 reads and writes, public/private
access, persistence, port conflicts, credentials, and interrupted setup retry.

## Data and recovery

```text
~/Library/Application Support/Jerd/
  configuration.json
  configuration.previous.json
  runtimes/             checked binaries, receipts, and license notices
    cli-tools.json      installed Composer and Laravel script paths
  bin/                  optional native CLI launcher and command links
  shell-backups/        private shell-file backups from explicit CLI setup
  database-runtimes/    fixed database versions, libraries, receipts, notices
  databases/
    services.json       database runtime and service records
    services.previous.json
    instances/<UUID>/
      data/             database files, retained after removal
      credentials.json  private generated password
      runtime.json      immutable instance/runtime identity
      initialized.json  successful data initialization record
      active-run.json   present while an owned database process runs
      server.log        current output; previous start retained separately
  mail-runtimes/        fixed Mailpit binary, receipt, and upstream notices
  mail/
    settings.json       runtime and SMTP/web ports; previous copy retained
    active-run.json     present while the owned mail process runs
    server.log          current output; previous start retained separately
    inbox/
      messages.sqlite   captured mail; WAL and SHM files while open
      runtime.json      fixed inbox/runtime identity
      initialized.json successful inbox initialization record
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

Database startup rejects a different runtime identity, incomplete initialization,
missing credentials, and an instance already in use. If an app crash leaves a
database process alive, the saved process record blocks a second start. Jerd
does not signal a process that it did not spawn in the current session.
Automatic recovery of such processes is not implemented. A removed database
can be recovered from its retained folder with engine-specific tools; the app
does not yet have a restore-registration action.

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
