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
| SystemCertificateTrust | System keychain and hostname-limited TLS trust through Security.framework |
| TrustConsentClient, TrustConsentService, TrustConsentScope | App-side macOS consent for the exact approved certificate and hostnames |
| JerdCLI, CLIRuntimeSelection | Project-aware PHP selection and direct execution of PHP/Composer/Laravel |

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
Version 1 records with one hostname are accepted and become version 2 records
on the next write. The hostname list must contain 1 to 256 distinct `.test` names.
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
one SSL trustRoot rule per approved hostname. The app accepts only the exact
CA and hostname set approved for the active operation. Its scope includes
the previous hostnames when rollback can require them. An empty hostname list
cannot grant unrestricted trust. No password enters Jerd.
Interactive trust calls have no arbitrary transport timeout. A lost connection
during consent leaves a recovery record because the outcome can be unknown.

Cleanup removes the
recorded certificate and its trust, not certificates selected by display name.
An untracked duplicate CA is rejected. The CA key is never sent to the helper.
Certificate deletion retrieves a keychain-backed reference by issuer/serial,
compares the complete DER, then deletes only that reference. A fresh in-memory
certificate is not a valid persistent-item reference for this operation.
The system keychain API is deprecated by Apple and builds with a warning.
Actual import, constrained trust, removal, and rollback were tested on macOS 27.

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
Database client modules do not imply database server management.

Jerd uses its own source and interface. It copies no Herd binary or asset.
This tool runs trusted local code; it is not a sandbox for hostile projects.
