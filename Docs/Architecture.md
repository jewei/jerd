# Architecture and security boundaries

`Jerd/` contains SwiftUI views, the main-actor model, file dialogs, Finder and
browser access, and app lifecycle handling. `Packages/JerdCore` contains core
logic. `JerdHelper/` contains the narrow privileged service. File and process
work runs in actors away from the UI actor.

| Component | Responsibility |
| --- | --- |
| Models, Sites, SiteRegistry, Persistence | Validation, hostname suggestions, runtime selections, serialized atomic storage |
| Runtimes, BundledRuntimes | Actual binary inspection; verified app-owned development payload installation |
| Configuration, Processes, ServingEngine | Caddy/FPM configuration; owned process groups; startup, TLS checks, and cleanup |
| LocalEnvironment | All enabled sites; stable CA identity; normal macOS HTTPS trust check for every hostname |
| HelperClient, SystemIntegration | SMAppService registration and typed authenticated XPC |
| HelperService, ListeningSockets | Exclusive loopback socket lease per client; descriptor transfer |
| PrivilegedSetupStore, AtomicHostsFile, HostsDocument | Owned host section, certificate ownership, rollback, and recovery records |
| SystemCertificateTrust, CertificateTrustSettings | System keychain and explicit TLS trust policies through Security.framework |
| TrustConsentClient, TrustConsentService, TrustConsentScope | App-side macOS consent for the exact approved certificate, setup hosts, and trust policy |
| JerdCLI, CLIRuntimeSelection | Project-aware PHP selection and direct execution of PHP/Composer/Laravel |
| DatabaseModel, DatabaseServicesView | Database list, connection details, and independent service controls |
| DatabaseManager, DatabaseDriver | Data initialization, engine arguments, readiness, owned processes, and graceful stop |
| MailManager, MailDriver, MailStore | Independent Mailpit inbox, SMTP/HTTP checks, persistent settings, and graceful stop |
| LocalServicePorts | Shared wildcard-port detection and exact listener ownership checks for databases and mail |
| DatabaseStore, BundledDatabaseRuntimes | Separate versioned service records and verified native runtime installation |

## Projects and processes

Detection reads file names only. It never executes `artisan` or project
scripts. Roots are canonicalized and must remain inside the project.
Removal never deletes project files.

PHP and Caddy run as the user. The process supervisor uses `posix_spawn`, a
new process group, a clean signal mask, an explicit environment, and closed
inherited file descriptors. Only the two approved listener descriptors reach
Caddy, at descriptors 3 and 4. Commands use executable URLs and argument arrays.

One Caddy process routes all enabled hostnames. The engine groups sites by
runtime ID and starts one PHP-FPM master per runtime, each with its own Unix
socket and generated settings. Sites that select the same runtime share that
group. All roots, runtimes, and generated settings are checked before startup.
Changing the active site list rebuilds and restarts the whole environment.

The supervisor retains an exited group leader unreaped until group cleanup.
This prevents PID reuse while it signals the owned group. It never loads a
PID from disk or selects a process by name. Existing socket directories are
rejected. A new short private path is used for each FPM Unix socket.

The engine checks readiness before reporting running, then watches the owned
services. If Caddy or any PHP-FPM master exits, all are stopped. The coordinator releases
the socket lease on failure or stop. A normal app quit waits for cleanup.
SIGKILL or an app crash can leave runtimes alive. New instances report port
conflicts; verified recovery across an app crash is still pending.

## HTTP and TLS

Only IPv4 loopback listeners are used. Caddy's admin API, HTTP/3, and automatic
redirect listeners are disabled. Known hosts redirect to HTTPS; unknown hosts
are rejected. HTTPS uses strict SNI/Host checks and a separate route for each
hostname, with that site's document root and PHP socket.

Sensitive paths and PHP-like source files are rejected before static serving.
The executable PHP suffix matcher is case-sensitive. This prevents an uppercase
`.PHP` file from entering FastCGI through Caddy's case-insensitive path matcher.
FastCGI failures never fall through to static serving.
[Caddy PHP routing](https://caddyserver.com/docs/caddyfile/directives/php_fastcgi).

When the document root is the project directory, `/storage` remains blocked.
With a separate public document root, it can serve Laravel's `public/storage`
link to `storage/app/public`. Hidden files and PHP-like source stay blocked;
PHP under `/storage` is rejected before FastCGI, including path-info requests
and directory URLs rewritten to `index.php`.
[Laravel public storage](https://laravel.com/docs/12.x/filesystem#the-public-disk).

`/.jerd/ready` is a reserved static health response. Readiness checks do not
execute project code or require a working project home page.

Caddy's internal issuer always has `install_trust: false`. The app creates a
stable installation UUID and a CA named `Jerd Local CA <UUID>`. CA preparation
uses Caddy validation with only the PKI app, without opening network listeners.
Each isolated test gets separate storage and never installs trust.

Engine readiness uses a CA-verified request. Product readiness also requires
actual helper host/trust status, a matching CA fingerprint, and a check for
each enabled hostname: resolution to 127.0.0.1 and a URLSession request using
default macOS trust.
The URLSession probe rejects redirects and uses no custom CA or TLS bypass.
Browsers with separate trust stores still require their own acceptance check.

## Privileged boundary

The helper uses SMAppService. The setup screen explains host/trust changes
and shows the certificate fingerprint before registration. macOS handles
administrator and background-item approval. Jerd collects no password.
[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

The listener and each XPC connection require an Apple signing chain, the exact
app/helper identifier, the same team as the running binary, and absence of
`get-task-allow`. The app verifies the helper too. These checks use Foundation's
connection code-signing requirement APIs. Caller ownership comes from the
XPC connection's effective UID, not a claimed UID or PID supplied by a client.

XPC offers status, configure a validated hostname list and CA, acquire/release sockets, and
remove setup. It accepts no command, arbitrary file path, executable, project
root, or network destination. Root never runs PHP or Caddy.

The helper binds only 127.0.0.1:80 and :443. It reserves both before changing
hosts or trust. A conflict changes neither. On start, it passes both listening
file descriptors to the app. Caddy 2.11.4 accepts `fd/3` and `fd/4` directly;
there is no proxy process or wildcard bind. `SO_REUSEADDR` permits prompt
restart; `SO_REUSEPORT` is not used. A live listener cannot be shared.
[Caddy descriptor listener implementation](https://github.com/caddyserver/caddy/blob/v2.11.4/listen_unix.go).

Only one authenticated connection can lease the sockets. Invalidation marks
the session closed before asynchronous cleanup, so a delayed acquire cannot
recreate its lease. XPC reply continuations complete once. A timeout closes
the corresponding connection. Explicit Sendable callbacks avoid inheriting
Swift actor isolation on Foundation reply queues.

## Hosts and certificates

The helper uses fixed paths and records the owning UID, installation UUID,
hostnames, and exact CA DER. Another user cannot replace that registration.
Version 1 and 2 records remain under their original hostname trust policy.
Version 3 records store the approved policy. Loading an old record never
broadens its trust. The hostname list must contain 1 to 256 distinct `.test` names.
The CA must have the installation-specific name, matching issuer/subject,
and a CA basic constraint. A different CA requires cleanup first.

The hosts editor changes only an exact tracked `BEGIN JERD`/`END JERD` section.
It rejects duplicates, malformed sections, conflicts, or external changes to
that section. It preserves unrelated bytes, including original line endings.
Reads reject symlinks, non-regular files, unexpected ownership and hard links.
Replacement uses an advisory lock, content and inode/time checks, metadata
copy (owner/mode/ACL/xattrs), fsync, and a same-volume rename. Software that
ignores advisory locks can still race after the last check.

A durable pending record and hosts backup precede system writes. Normal
failures restore prior hosts, trust, and registration. Removal also restores
state if certificate deletion fails. Tests inject partial failures. A crash
with a pending record blocks further mutation and preserves recovery evidence;
automated recovery is not implemented.

The helper imports the root into System.keychain. A reverse call on the same
authenticated XPC connection asks the logged-in app to set admin-domain trust:
one SSL server trustRoot rule for the installation CA. This trust applies to
all hostnames; it does not grant code-signing or general X.509 trust. The setup
screen states that scope. Chromium ignores macOS trust entries that contain
`kSecTrustSettingsPolicyString`, so the old per-host rule is retained only for
legacy records and rollback.
[Chromium macOS trust reader](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/net/cert/internal/trust_store_mac.cc).

The app accepts only the exact CA, setup hostname set, and policy approved
for the active operation. Its scope includes the previous hostnames and policy
when rollback can require them. An empty hostname list cannot set trust, and
a hostname-only approval cannot authorize the server TLS policy. No password
enters Jerd. No browser certificate database or security bypass is required.
Interactive trust calls have no arbitrary transport timeout. A lost connection
during consent leaves a recovery record because the outcome can be unknown.

Cleanup removes the
recorded certificate and its trust, not certificates selected by display name.
An untracked duplicate CA is rejected. The CA key is never sent to the helper.
Certificate deletion retrieves a keychain-backed reference by issuer/serial,
compares the complete DER, then deletes only that reference. A fresh in-memory
certificate is not a valid persistent-item reference for this operation.
The system keychain API is deprecated by Apple and builds with a warning.
Actual import, original hostname trust, removal, and rollback were tested on
macOS 27. The approved migration to server TLS trust was also applied on that
host, and the user confirmed that Brave loads both registered sites.

## CLI companions

The app bundles Composer's pinned official PHAR and a locked Laravel installer
dependency tree. Both use Jerd PHP. An explicit shell setup copies the signed
native CLI launcher to the app's private bin directory and creates three links.
It backs up shell files before adding the managed PATH block.

The launcher reads the current app configuration for each invocation. It
resolves working-directory symlinks and chooses the longest matching project
path by path components. A registered site's PHP pin applies even when its web
server is disabled. The default applies outside registered projects. Missing
selections fail without fallback. Composer's `--working-dir` argument does not
alter this initial selection; the caller must change directory first.

The launcher replaces itself with the selected PHP through `execv`. It adds the
companion script path before the user's arguments and places Jerd's bin directory
first for child commands. It preserves terminal input, output, and exit status.
It neither starts web services nor changes a project during selection.

## Runtime supply and release scope

The development PHP comes from [lerd-env/php](https://github.com/lerd-env/php),
not Herd. Caddy comes from its official releases. Fixed pins are checked
against GitHub metadata over authenticated HTTPS before download. Archive
size and SHA-256 are checked before extraction. Only named regular binaries
and license/build notices are extracted. Per-file receipts are checked during
embedding and app installation. No upstream PHP installer or external PHP module is run.

Composer's download and license have fixed SHA-256 pins. Laravel dependencies
are installed from a committed lock file using verified HTTPS, without Composer
plugins or scripts. Every prepared file is hashed for embedding and installation.
The dependency archives do not have an independent publisher-signature check.

This is an approved development trust basis, not publisher-signed metadata.
Production artifacts still need authenticated manifests, version/architecture/
minimum-OS binding, tested capabilities, updates, and rollback. The current
payload has only been tested on arm64 macOS 27.0.1. Lerd's build-script license
does not replace the binary and linked-library license notices, which are
retained with the payload.

PHP inspection uses `-n` and an empty INI scan directory. Runtime startup uses
Jerd's INI and an empty scan directory. The UI reports observed CLI/FPM modules.
The intended common extension profile remains a release target. Upstream
built-in extras do not establish a supported optional-extension feature.
Database servers are managed by the separate modules described below. The
tested PHP build includes `pdo_mysql`, `pdo_pgsql`, and `redis` for clients.

Jerd uses its own source and interface. It copies no Herd binary or asset.
This tool runs trusted local code; it is not a sandbox for hostile projects.

## Database research and implementation

Research date: 2026-10-01. [DBngin](https://dbngin.com/) describes native
database processes with selectable versions and ports. Its
[public repository](https://github.com/TablePlus/DBngin) is an issue tracker
with screenshots, not application source. The screenshots show a short
create form and a service list with per-row Start/Stop controls. The installed
DBngin 27.0.1 app was inspected through its window and public scripting command.
Its PostgreSQL 18.4 and Redis 8.8.0 services were already running on 5432 and
6379. No DBngin binary or image is included in Jerd.

Jerd adopts the independent-service workflow. Database records are separate
from site records. Every instance has a UUID, runtime ID, name, unique port,
private credentials, and an owned data directory. The first catalog supplies
one version per engine and permits multiple instances. It does not implement
a SQL editor, automatic data migration, Homebrew service control, or login startup.

Runtime sources are [Oracle MySQL 8.4](https://dev.mysql.com/downloads/mysql/8.4.html),
[Postgres.app](https://postgresapp.com/downloads.html), and
[Redis source](https://redis.io/docs/latest/operate/oss_and_stack/install/archive/install-redis/install-redis-from-source/).
The exact selected versions and SHA-256 values are in `DatabaseRuntimes/pins.json`.
MySQL 8.4.11 also passes the upstream GPG signature check with the pinned
Oracle key. PostgreSQL 18.6 comes from the digest-pinned Postgres.app 2.9.6
image; its app signature is checked before runtime extraction. Redis 8.8.3
source matches the official redis-hashes entry and is compiled locally with
the installed compiler. The script stages files in the repository's build
directory and runs no system installer. Safe in-archive links become regular
files; per-file hashes are checked during embedding and installation.

DatabaseManager runs off the UI actor. It serializes each instance's lifecycle
and all record mutations, while different instances can start independently.
An exclusive file lock prevents two Jerd processes from using the same instance.
The saved runtime identity must match before existing data can start. A failed
or interrupted initialization preserves partial data and blocks reinitialization.
A saved live PID from a previous app session blocks a second server; automatic
attachment to or signalling of that old process is deliberately not implemented.

MySQL uses `--no-defaults`, a private data directory, no X Protocol listener,
and an initial socket-only bootstrap. That bootstrap sets passwords and creates
the `jerd` user and database before TCP starts. PostgreSQL uses `initdb` with
SCRAM password authentication and a private password file. Redis uses a private
configuration, a generated password, and append-only persistence. All final
listeners are restricted to `127.0.0.1`; runtime processes have no root access.
Readiness requires an authenticated SQL query or Redis PING and actual per-PID
TCP/UDP listener inspection. Passwords do not enter process arguments or probe
results. They are retained in mode-0600 files within mode-0700 instance folders.

The manager watches process exit. One failed database does not stop other
databases or the web environment. MySQL and Redis receive SIGTERM for shutdown;
PostgreSQL receives SIGINT for its documented fast shutdown. The supervisor
waits up to 30 seconds without escalating to SIGKILL. On timeout the process
remains tracked, and app termination is cancelled. Removal first completes
shutdown, then removes only the registration. Data and credentials remain.
See [PostgreSQL shutdown modes](https://www.postgresql.org/docs/18/server-shutdown.html).

The database port check first inspects active TCP listeners with `lsof`,
then checks a loopback bind with SO_REUSEADDR. This allows restart while closed
connections are in TIME_WAIT. A bind alone is insufficient on macOS: a specific
address can share a port with an existing wildcard listener. The live DBngin
Redis service exposed this case. Jerd now rejects any existing listener on the
port, then checks after startup that only its own PID listens there.
It never enables SO_REUSEPORT. See [Apple socket options](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setsockopt.2.html).

The development build embeds the full prepared payload, about 1.1 GB, including
shared libraries and upstream notices. An on-demand installer, smaller release
packages, more versions, export/import UI, and crash recovery are later work.

## Local mail

The [Mailpit site](https://mailpit.axllent.org/) describes a standalone SMTP
capture service with a web UI and API. Jerd manages the upstream binary as a
separate service. The native Mail tab supplies lifecycle controls, port editing,
Laravel settings, data/log access, and a local test message. The full inbox opens
in the user's default browser. No SMTP implementation or HTML mail viewer is
duplicated in Jerd, and mail is not a database engine entry.

The first runtime is [Mailpit 1.31.3](https://github.com/axllent/mailpit/releases/tag/v1.31.3).
Its fixed arm64 archive size and SHA-256 match GitHub release metadata. The
preparation script extracts only the binary, license, and readme as regular
files. Per-file hashes are checked at build and installation time. The binary's
`version --no-release-check` output is checked before opening the inbox database;
a version in the executable path cannot satisfy this check. The payload is
about 26 MB and does not depend on the installed Homebrew Mailpit service.

MailManager is an actor with serialized operations. It stores settings and a
backup independently from sites and databases. MailPaths defines a private
SQLite inbox, runtime identity, initialization marker, log, and active-run record.
An exclusive file lock and the previous-process check block concurrent use.
An initialized but missing inbox file is not silently replaced. A different
runtime identity is rejected before Mailpit opens existing data.

[Runtime options](https://mailpit.axllent.org/docs/configuration/runtime-options/)
provide an explicit database path, SMTP/web bind addresses, and retention controls.
Jerd binds both ports to `127.0.0.1`, disables automatic message deletion and
version checks, and disables reverse DNS lookups. The process receives the
supervisor's clean environment. External relay, forwarding, webhooks, POP3,
and metrics listeners are not configured. SMTP and HTTP have no authentication
or TLS in this local development version. The UI states those connection settings.

The [HTTP host allowlist](https://mailpit.axllent.org/docs/configuration/http/)
is enabled for local access. Unknown DNS hostnames are rejected before API
handling. Remote CSS and fonts are blocked by Mailpit. These options do not
promise that every optional inbox action or remote image works without a network.

Ready requires the expected version and private database path from the
[information API](https://mailpit.axllent.org/docs/api-v1/), a successful SMTP
NOOP response, and exact listener/PID checks on both ports with no UDP sockets.
Send test email uses SMTP, not the send API. The monitor detects process exit.
Stop sends SIGTERM and waits up to 30 seconds without a forced kill. A timeout
keeps the owned process and cancels quit. If a later database stop cancels quit,
the mail controls and monitor resume. Stop and Quit never delete captured mail.

The development Mac initially ran Homebrew Mailpit on 1025/8025. Jerd selected
other free ports and did not import that inbox. The user later requested that
the Homebrew service be stopped; its own service command was used.

## Local storage

[RustFS](https://docs.rustfs.com/en/installation/macos) supplies a native Apple
Silicon server with an S3 API and embedded console. Jerd bundles the official
[1.0.0 release](https://github.com/rustfs/rustfs/releases/tag/1.0.0) with its
Apache license. The fixed archive digest matches the GitHub asset metadata.
The preparation script checks size, digest, and regular archive member type.
The embed script and app installer check the per-file receipt again.

[Lerd's S3 service](https://github.com/lerd-env/lerd/blob/5b42cb29d7ed2723d37d2d65d033dc73620cda2b/internal/serviceops/s3.go)
uses one shared instance and a built-in S3 client for bucket operations. Jerd
uses that arrangement with a native Swift client. It does not need a client
container. Jerd creates random credentials, defaults to private buckets, and
limits optional anonymous access to object reads. It does not adopt Lerd's
anonymous write policy or forced bucket deletion.

StorageManager serializes lifecycle and bucket changes. Save validates the S3
name, starts the owned service when needed, then records an incomplete setup
before sending bucket operations. The client creates the bucket, applies and
reads back its access policy, and checks it with HeadBucket. Only then does
the record become complete. A failure leaves the intent available for retry.
Saved complete buckets that disappear from the server are reported missing.
They are not recreated automatically. The native list contains Jerd records;
the full RustFS console manages objects and other server buckets.

StorageS3Client uses path-style S3 requests with AWS Signature Version 4 and
CryptoKit. It handles UTF-8 object keys with byte-based URI encoding. It uses
an ephemeral URLSession with no cookies, cache, proxies, or redirects. Requests
have timeouts and response size bounds. XML parsing disables external entity
resolution. Credentials are not placed in commands, URLs, or error messages.
The generated keys use private 0600 files; RustFS reads each key through its
credential-file flag. The containing data folders use mode 0700.

The process gets a clean environment with telemetry export and upstream update
checks disabled. Both API and console listeners bind to loopback. Ready needs
a signed ListBuckets response, an accessible embedded console, and exact PID
ownership of the two expected listeners with no UDP socket. The real binary
serves its console at `/rustfs/console/`, not the authenticated root route.
RustFS splits volume arguments at spaces, so Jerd passes the fixed relative
`data` directory from its private working directory. This supports the macOS
Application Support path and Unicode without symlinks or shell escaping.

A file lock and previous-process record prevent competing use. Runtime identity
and an initialization marker preserve the selected version, RustFS format file,
and credential digest. Missing initialized data or credentials block startup.
SIGTERM shutdown has a 30-second grace period and no forced kill. A timeout
cancels Quit. Storage controls resume if a later service cancels app termination.
