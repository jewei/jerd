# Jerd agent guide

Jerd is a native macOS app for local PHP development. Read this file before
you change the repository. Read [Architecture](Docs/Architecture.md) before you
change a module boundary.

## Commands

Run every task through `./dev`. It works from any folder in the repository.

| Command | Purpose |
| --- | --- |
| `./dev check` | Run everything CI runs: lint, JerdKit tests, Tools tests, and the Debug build |
| `./dev test [TARGET...] [--filter X]` | Run JerdKit unit tests, for example `./dev test JerdWeb` |
| `./dev test --integration web,database,mail,storage` | Also run opt-in runtime tests; see [Tools](Tools/README.md) |
| `./dev test --tools` | Run the tests of the `./dev` tool |
| `./dev build [--release] [--sign ID --team T]` | Build the app (unsigned Debug by default) and print its path |
| `./dev snapshots [PAGE...]` | Render UI pages to PNG files in `.build/snapshots` |
| `./dev format [--check]` | Format all Swift code with swift-format |
| `./dev lint` | Check the format, `generate --check`, and the repository policies |
| `./dev generate [--check]` | Generate `Jerd.xcodeproj` from `project.yml` |
| `./dev doctor` | Check Xcode, Swift, swift-format, XcodeGen, and `gh`, with install hints |
| `./dev clean [--all]` | Remove build output; `--all` also removes packages and runtimes |
| `./dev help [COMMAND]` | List every command, or show the options of one command |

Add `--verbose` to a command to see each underlying command line. Exit status:
0 success, 1 a check failed, 2 usage error, 3 a prerequisite is missing.

For quick loops inside the package, `swift test --package-path Packages/JerdKit
--filter JerdWebTests` also works.

## Repository map

| Path | Contents |
| --- | --- |
| `Packages/JerdKit/` | All product logic, UI, and tests, in small targets |
| `Apps/Jerd/` | App entry point, Sparkle adapter, live wiring, and resources |
| `Apps/JerdHelper/` | Privileged helper entry point and launchd plist |
| `Apps/JerdCLI/` | `php`, `composer`, and `laravel` launcher entry point |
| `Tools/` | The `jerd-dev` tool behind `./dev` |
| `Runtimes/` | Pinned runtime versions and lock files |
| `Configuration/` | Xcode build settings and the app version |
| `Docs/` | User, build, test, release, and architecture documentation |

`project.yml` is the XcodeGen source. Run `./dev generate` after you change it.
Do not edit `Jerd.xcodeproj` by hand.

## Code rules

- Swift 6 language mode, strict concurrency, macOS 14 or later.
- One main type per file. The file name is the type name.
- Keep files under 300 lines and functions under 40 lines. Split a larger type
  into extensions in separate files named `Type+Topic.swift`.
- Name types for what they are and functions for what they do. Do not use
  abbreviations other than common ones (URL, ID, PHP, TLS, CA, S3, SMTP).
- Put a one-line `///` comment on every public type and on every non-obvious
  function. Explain why, not what.
- Use `public` only for API that another target uses. Use `package` for API
  that only tests or sibling targets use.
- Keep side effects behind a protocol. Name the protocol for its role, for
  example `CommandRunning`. Give the live type a plain name, for example
  `CommandRunner`. Test doubles live in the test target and start with `Fake`
  or `Recording`.
- Prefer pure values and functions for policy. Put file, process, and network
  work in actors, never on the main actor.
- Throw `JerdError` with a message that a user can act on. Never use `try?` to
  hide a failure in a safety path.
- Use argument arrays and absolute executable URLs. Never run a shell.

## Tests

- Use Swift Testing (`import Testing`). Name a test for the behavior it proves.
- Every rule in a module has a test in that module's test target.
- Default tests run without root, without network, and without changes to
  `/etc/hosts`, trust stores, shell files, or system services.
- Tests that need real runtimes are opt-in through `JERD_*` environment
  variables. See [Run tests](Docs/Testing.md).
- Bind test servers to `127.0.0.1` on ports above 1023. Use an isolated CA.

## Safety boundaries

These rules protect user data and the user's Mac. Do not weaken them.

- Keep project code and all runtime processes unprivileged.
- Product setup changes hosts and trust only after explicit user approval,
  through the narrowly scoped, authenticated helper.
- Do not run project code to detect a project. Never delete a registered project.
- Never verify TLS with `curl -k` or a disabled check.
- Stop only processes that Jerd owns. Do not use `killall` or `pkill`.
- Preserve corrupt data. Do not replace it with an empty configuration.
- Never force-kill a data service. A shutdown timeout keeps the process, its
  record, and its data lock, and cancels Quit.
- Never reuse a database folder with a different runtime version.
- Keep captured mail, buckets, objects, and credentials after Stop and Quit.
- New buckets are private. Never allow anonymous writes.
- Keep tunnel tokens out of settings, command arguments, and logs. Save does
  not connect a tunnel. Never change remote Cloudflare routes.
- Keep all data-service listeners on loopback.

## Compatibility contract

Installed copies of Jerd have user data. Keep these stable, or add a migration
with a test that reads the old form:

- Every path under `~/Library/Application Support/Jerd` and
  `/Library/Application Support/JerdHelper`.
- Every JSON key, value form, and encoder option of saved files.
- UserDefaults keys in the `dev.jerd.app` domain.
- Keychain service and account names.
- Bundle identifiers, the helper Mach service name, XPC selectors, and the
  code-signing requirements.
- The Sparkle feed URL and public key.

## Product scope

Implement only the approved features:

- Serve all enabled registered `.test` sites over HTTPS, each with its selected
  PHP runtime.
- Provide `php`, `composer`, and `laravel` commands that select PHP from the
  registered project that contains the working directory.
- Manage independent MySQL, PostgreSQL, and Redis services, a Mailpit inbox,
  RustFS storage, and connectors for existing Cloudflare Tunnels.
- Tabs in this order: Dashboard, Sites, Databases, Storage, Mail. Dashboard
  pages in this order: Dashboard, Appearance, Runtimes, Advanced, About.
- Independent menu bar and Dock controls, and the shipped icon designs.
- Runtime version checks and installation. Sparkle app updates from the signed
  HTTPS feed of the public `jewei/jerd` repository.

## Workflow

- Work on a branch. Make small commits with a clear subject line.
- Run `./dev check` before you push.
- Report in ASD-STE100 Simplified Technical English.
