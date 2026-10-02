# Publish an app update

Use `Scripts/release.sh` on the Mac that holds the Jerd signing keys. The script
has three commands: `prepare`, `validate`, and `publish`. Preparation writes a
private candidate to `.build/releases/`. Publication is a separate command.

## Requirements

- A clean Git worktree, with all source changes committed.
- Xcode, GitHub CLI (`gh`), and the prepared runtimes from [Build Jerd](Build.md).
- A Developer ID Application certificate and private key in the local Keychain.
- The existing Sparkle key under the Keychain account `dev.jerd.sparkle`.
- Apple notary credentials stored under the Keychain profile `notarytool`.
- Release notes under `## [Unreleased]` in `CHANGELOG.md`.

The default team is `4L4SS26L9J`. The default certificate is
`Developer ID Application: Jewei Mak (4L4SS26L9J)`. The notary profile uses
`~/Library/Keychains/login.keychain-db`. Command options can select another
certificate, team, profile, or Keychain. Do not export private keys to files or CI.
The Sparkle key must match the public key in `project.yml`.

## Prepare a candidate

Choose a version and a build number. The build must exceed the project build
and every published build. The version must exceed every published version.
An empty feed is valid for the first release.

```sh
Scripts/release.sh prepare 0.1.0 3
```

The command prints the candidate directory. It then:

1. Archives an arm64 Release app from the clean source commit.
2. Copies the app into the candidate directory.
3. Builds the pinned XZ library for RustFS, corrects bundled library paths,
   signs each native runtime, and updates its digest receipt.
4. Gives signed payloads separate installation IDs. Existing runtime folders
   and service selections remain valid.
5. Signs Sparkle’s embedded tools, its framework, and the app. It checks all
   native signatures, receipts, dependencies, and symbols.
6. Runs the core tests and real runtime tests with private data and loopback ports.
7. Submits the app to Apple, requires `Accepted`, and staples the ticket.
8. Builds, signs, notarizes, and staples a DMG.
9. Signs the final DMG and candidate feed with the Jerd Sparkle key.
10. Validates the DMG, app, symbols, receipt hashes, and feed together.

Jerd and its managed runtime payloads target Apple Silicon. The bundled Sparkle
framework can retain its upstream universal architecture. The default minimum macOS version is
the version of the build Mac. Use `--minimum-macos` only after testing that OS.
Validation also rejects a minimum below any bundled runtime requirement.
The optional upstream PostgreSQL PL/Python extensions are excluded because they
require a separately installed Python framework. Other PostgreSQL extensions
remain subject to their normal runtime requirements.

Preparation keeps the source tree unchanged. It retains archives, symbols,
notary results, logs, and `release.json` in the private candidate directory.
On failure, inspect the logs, fix the cause, commit the fix, and prepare a new
candidate. Each attempt uses a new directory. Failed artifacts are not published.

## Validate a candidate

Use the exact directory printed by preparation:

```sh
Scripts/release.sh validate .build/releases/Jerd-0.1.0-3-EXAMPLE
```

Validation checks the local app and the app mounted from the DMG. It checks
Gatekeeper acceptance, stapled tickets, runtime signatures, file hashes, dynamic
library paths, debug-symbol UUIDs, and the signed feed and archive.
Do not change the app, DMG, feed, notes, or symbols after validation.

## Publish a candidate

Push the source commit to `main` first. The local source commit and `origin/main`
must equal the candidate's source commit. Then run:

```sh
Scripts/release.sh publish .build/releases/Jerd-0.1.0-3-EXAMPLE
```

The command validates the candidate again. It makes an isolated Git worktree,
sets both project version files, promotes the changelog, and copies the signed
feed. It commits these changes and pushes a temporary release branch. It then
creates a draft GitHub release, uploads the DMG and debug symbols, downloads
both assets, and checks their SHA-256 values. It publishes the release before
it pushes the feed to `main`. The push is a normal fast-forward push.

The local checkout remains on the source commit. After success, run
`git pull --ff-only`. The public feed is
[appcast.xml](https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml).

If publication fails, `publication.json` identifies the last completed stage.
Do not repeat the command without inspection. The script refuses to overwrite
an existing release tag or restart a recorded publication. If assets are public
but the feed push failed, verify the assets and staged commit, resolve any
concurrent changes on `main`, and publish the feed only after review. Keep the
previous valid public feed until recovery is complete.

After publication, test **Check for Updates** from an older installed build.
Check graceful shutdown, relaunch, and retained service data. Local release
validation does not replace this public update test.

See [Sparkle manual signing](https://sparkle-project.org/documentation/sandboxing/#code-signing),
[Sparkle publishing](https://sparkle-project.org/documentation/publishing/)
and [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
for the upstream procedures.
