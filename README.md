# Jerd

Jerd is a native macOS app for local PHP development. It does these tasks:

- It serves your registered `.test` sites over HTTPS. Each site uses the PHP
  version that you select for it.
- It gives you `php`, `composer`, and `laravel` commands. These commands use the
  PHP version of the registered project that contains the current folder.
- It manages MySQL, PostgreSQL, and Redis services, a Mailpit inbox for test
  mail, and RustFS storage with an S3 API.
- It runs connectors for Cloudflare Tunnels that you already have.
- It checks for new runtime versions and installs them.

## Requirements

- A Mac with Apple silicon. Jerd does not run on an Intel Mac.
- macOS 14 or later.
- Ports 80 and 443 on `127.0.0.1` must be free. Other web servers must not
  use them.
- An administrator account, to approve the HTTPS setup one time.
- An internet connection the first time you add a database engine. The app
  does not include MySQL, PostgreSQL, and Redis. Jerd downloads an engine only
  when you select Install or Add Database: MySQL is about 168 MB, PostgreSQL
  about 123 MB, and Redis about 5 MB (about 295 MB for all three). Jerd builds
  Redis from its source, so Redis also needs the Xcode Command Line Tools
  (`xcode-select --install`). Jerd installs an engine only when the download
  matches its reviewed checksum (and, for MySQL, the publisher signature).

## Install and update

1. Download the signed and notarized release from the
   [GitHub releases](https://github.com/jewei/jerd/releases) page.
2. Move `Jerd.app` to the Applications folder, then open it.
3. To serve sites over HTTPS, open the Sites tab and approve the system setup.

Jerd uses [Sparkle](https://sparkle-project.org) for app updates. It reads
only the signed feed [`appcast.xml`](appcast.xml) in this repository, over
HTTPS. Sparkle installs an update only when its signature is correct. You can
change the update settings on the About page of the Dashboard.

## What Jerd changes on your Mac

Jerd changes system files only after you approve the change. These are the
changes:

| Change | Purpose |
| --- | --- |
| A helper in Login Items & Extensions | It opens ports 80 and 443 on `127.0.0.1` and makes the two changes below. It never starts a process |
| A section between `# BEGIN JERD` and `# END JERD` in `/etc/hosts` | It sends your `.test` hostnames to `127.0.0.1` |
| The certificate "Jerd Local CA" in the System keychain, with trust for TLS | Browsers and PHP accept the HTTPS certificates of your sites |
| Optional: a PATH block in `~/.zprofile` and `~/.zshrc` | It adds the `php`, `composer`, and `laravel` commands. Jerd keeps a backup of each file that it changes |

To remove the changes, open the Sites tab and select **System Setup** >
**Remove System Setup…**. Jerd stops the sites, removes its hosts section and
its CA certificate, and removes its helper. Your site records and project
files stay.

Jerd keeps its data in `~/Library/Application Support/Jerd`. The helper keeps
its records in `/Library/Application Support/JerdHelper`. To remove all data,
first remove the system setup. Then quit Jerd and delete these two folders.
The second folder needs administrator approval. Also remove the tunnel tokens
(service `dev.jerd.cloudflared.tunnel-token`) in Keychain Access.

## Privacy and safety

- Jerd sends no analytics. It connects to the internet only to check for app
  and runtime updates, to download runtimes, and to run your tunnels.
- All data services listen only on `127.0.0.1`.
- PHP, the web server, and the data services run as your user, not as root.
- Jerd never deletes a project folder. Stop and Quit keep your databases,
  captured mail, buckets, objects, and credentials.
- Jerd keeps tunnel tokens only in your Keychain.
- When Jerd finds a damaged settings file, it keeps the file and tells you. It
  does not replace the file with empty settings.

## Build from source

You need Xcode (the version in [`.xcode-version`](.xcode-version)), XcodeGen,
and swift-format. Do these steps in the repository folder:

1. Run `./dev doctor`. It checks the tools and gives install hints.
2. Run `./dev runtimes prepare`. It downloads, checks, and prepares the pinned
   runtimes.
3. Run `./dev build`. It builds an unsigned Debug app and shows its path.

Run `./dev help` to see all commands. Read [AGENTS.md](AGENTS.md) before you
change the code. More documents:

| Document | Contents |
| --- | --- |
| [Architecture](Docs/Architecture.md) | Modules, layers, the process model, and app startup |
| [Data reference](Docs/Reference.md) | Every saved file, setting, and Keychain item |
| [Run tests](Docs/Testing.md) | Unit tests, opt-in integration tests, and manual checks |
| [Tools](Tools/README.md) | The `./dev` tool, runtime payloads, and releases |
| [Changelog](CHANGELOG.md) | Changes in each release |
