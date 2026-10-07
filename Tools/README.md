# Tools

`Tools/` is the Swift package of `jerd-dev`, the tool behind `./dev`. For the
command list, see [AGENTS.md](../AGENTS.md#commands) or run `./dev help`.

## How `./dev` runs

1. The `dev` shim finds the repository root and checks that Xcode is selected.
2. SwiftPM builds `jerd-dev` in release mode into `Tools/.build/dev`. It builds
   again only when a Tools source changes. The test build uses another folder.
3. The tool runs from the repository root. Each command prints `==>` step
   headers. A command with more than one step ends with a summary.

Exit status: 0 success, 1 a check failed, 2 usage error, 3 a prerequisite is
missing. After SIGINT, SIGTERM, or SIGHUP, the status is 128 plus the signal number.
`--verbose` shows each underlying command line. `--json` prints one summary
object on standard output and sends every other line to standard error:

```json
{"command":"lint","exitStatus":0,"message":null,"status":"ok","steps":[{"messages":[{"level":"ok","text":"…"}],"seconds":0.2,"status":"ok","title":"Format check"}]}
```

Each child process leads its own process group. A time limit sends SIGTERM and
then SIGKILL to the whole group, and a signal to `./dev` goes to every running
group. A failed quiet step writes its full output to `.build/logs/<step>.log`;
CI uploads that folder when `./dev check` fails.

## Builds

Every build checks the built app: the update feed URL and public key in
`Info.plist`, the Sparkle keys, and arm64-only executables. The runtime payloads
are arm64 only, so `Configuration/Base.xcconfig` sets `ARCHS = arm64`.

The Xcode phase `Scripts/embed-app-contents.sh` calls `./dev runtimes embed`.
That command copies only the embedded payloads (`EmbeddedPayloads.pins`, which reads
`PayloadInventory.embeddedPayloads`; `./dev release` uses the same rule): every pin except those that `Runtimes/runtimes.json` marks
`"embedded": false`, today MySQL, PostgreSQL, and RustFS. Redis stays in the `database`
folder of the app. The app installs MySQL, PostgreSQL, and RustFS on demand from the same
pins. The RustFS preparation needs the reviewed XZ library, so the command also copies
`.build/runtimes/support/xz` into `RuntimePayloads/support/xz` (`EmbeddedSupport`): about
180 KB with `support-receipt.json`. The receipt must name the pinned XZ source and the
deployment target of the app, and every file must match it. A Release build refuses a
missing library; a Debug build warns and cannot install RustFS. `./dev release` signs the
library, records the new digests and a signing record in its receipt, checks its minimum
macOS and its libraries, and refuses any other support folder. The command verifies every embedded payload before it copies. The receipt must
match its pin in `Runtimes/runtimes.json`. Every file must match its SHA-256
and executable flag. It copies with `rsync --delete`, so an unchanged payload is
not copied again, and it removes folders that no embedded pin names. The script calls
`./dev` and does not check the files itself. The receipt rules are in
JerdManifest and JerdRuntimes, the same code that the app uses to install the
payloads. The `dev` shim rebuilds `jerd-dev` only when a Tools source changes,
so a build from Xcode works too.

A Release build requires every embedded payload. A Debug build embeds the
prepared embedded payloads and warns about missing ones. `./dev check` and CI build
Release with `--allow-missing-runtimes`, which turns the gate off for an
unsigned check build only.

## Runtime payloads

| Command | Purpose |
| --- | --- |
| `./dev runtimes prepare [GROUP...]` | Download, verify, and prepare the pinned payloads. Default: every group |
| `./dev runtimes verify [GROUP...]` | Verify each payload against its pin and receipt, file by file, and require every `@loader_path`, `@rpath`, and `@executable_path` reference of each Mach-O file to resolve inside the payload (embedded and on-demand payloads); require each Mach-O file of an embedded payload to run on the deployment target. With `storage`, `xz`, or no group it also verifies the XZ support library (`.build/runtimes/support/xz`) the same way; `database`, `development`, and `mail` alone skip it |
| `./dev runtimes status` | List each payload with its group, whether the app embeds it, its version, size, and state |
| `./dev runtimes embed DEST [--require-all]` | Verify and copy the embedded payloads into an app; the Xcode phase calls it |

Groups: `development` (PHP, Caddy, Composer, Laravel installer), `database`
(MySQL, PostgreSQL, Redis), `mail` (Mailpit), `storage` (RustFS), and `xz` (the
reviewed XZ library of RustFS; `storage` selects it too). Names ignore case,
and `Support/XZ` names the library.

`prepare` prepares every pin, also MySQL, PostgreSQL, and RustFS, which the app does not
embed: CI and the integration tests use those payloads. `verify` with the `storage` or
`xz` group (or no group) also checks `support/xz`: its receipt, its files, its libraries,
and that every file runs on the minimum macOS of the app. It uses
`PinnedPayloadPreparer`, the same pipeline as managed runtime updates and the
on-demand database installation in the app. The output is `.build/runtimes/payloads/<group>/<payload
ID>/` with `payload-receipt.json`, and a copy of the catalog. A payload that
exists is verified and kept. A payload of an older pin is preserved and stops
the run; remove `.build/runtimes/payloads` and prepare again. Downloads are kept
in `.build/runtimes/downloads/<sha256>`; only a file with the pinned digest goes
into or comes out of that cache.

The preparation removes the local symbols (`/usr/bin/strip -x`) of the PHP CLI and FPM,
`mailpit`, `redis-server`, and `redis-cli` before it writes the receipt (`SymbolStripping` in
JerdRuntimes). This removes about 9.8 MB before compression (3.8 MB from each PHP 8.5 file,
1.7 MB from Mailpit, and 0.4 MB from Redis) and changes nothing at run time. Each stripped file
must keep a valid signature and pass its version probe. A stripped payload has new file digests,
so its folder ID changes; to strip a payload that an older `./dev` prepared, remove its folder
and prepare it again.

Prerequisites: an arm64 Mac and Xcode. Redis and XZ build with the Xcode
compiler. Both target the `MACOSX_DEPLOYMENT_TARGET` of
`Configuration/Base.xcconfig`, not the macOS of the build Mac: each build gets
it as `MACOSX_DEPLOYMENT_TARGET` and as `-mmacosx-version-min` in `CFLAGS` and
`LDFLAGS`. The MySQL signature is checked in Swift with Oracle's pinned key, so
GnuPG is not needed. XZ builds into `.build/runtimes/support/xz` with a fixed
environment. Its `support-receipt.json` records the pin, the deployment target,
and the file digests, so a later run reuses the build.

`./dev runtimes verify` also requires every Mach-O file of an embedded payload
to run on that deployment target. It reads `minos` of `LC_BUILD_VERSION` (or
`LC_VERSION_MIN_MACOSX`) from the same `otool -l` output as the dependency
check, and a failure names the file and both versions, for example
`bin/redis-cli: it needs macOS 27.0, above the deployment target 14.0`. To fix a
payload that an older `./dev` built, remove its folder and prepare it again. An
on-demand payload is exempt, because the app checks the minimum of its release
before it installs it.

## Integration tests

`./dev test` removes every inherited `JERD_*` variable. Only the variables of
the groups in `--integration` reach the tests. The paths come from the receipts
of the prepared payloads, so no file name, for example a PHP version, is in the
tool. Every payload is verified before a test uses it. When you set every
required path of a group, your paths win; set them to absolute paths of trusted
local runtimes.

| Group | Required | Optional |
| --- | --- | --- |
| `web` | `JERD_PHP_CLI`, `JERD_PHP_FPM`, `JERD_CADDY` | `JERD_SECOND_PHP_CLI`, `JERD_SECOND_PHP_FPM`, `JERD_KEEP_TEST_FILES` |
| `database` | `JERD_DATABASE_RUNTIMES` | `JERD_OCCUPIED_DATABASE_PORT`, `JERD_RUNTIME_DOWNLOADS`, `JERD_ON_DEMAND_ENGINE` |
| `mail` | `JERD_MAIL_RUNTIME` | |
| `storage` | `JERD_STORAGE_RUNTIME` | |

The `database` group also sets `JERD_ON_DEMAND_INTEGRATION=1` and
`JERD_RUNTIME_DOWNLOADS=.build/runtimes/downloads` when that folder exists, so the
on-demand installation test runs from the verified downloads without internet.
The download cache also keeps the pinned MySQL signature file under its SHA-256;
`./dev runtimes prepare database` adds it when an earlier run did not. With the
file cached, prepare verifies an existing payload without the network. Offline
and without the file, prepare still verifies the payload and warns that one
small download is needed for the on-demand test. The
release runtime tests take the embedded payloads from the candidate app and the
on-demand payloads (MySQL, PostgreSQL, and RustFS) from `.build/runtimes/payloads`, each
verified file by file. The `storage` group also sets `JERD_XZ_SUPPORT` and
`JERD_ON_DEMAND_STORAGE_INTEGRATION=1` when `.build/runtimes/support/xz` exists, so the
on-demand RustFS test runs too.
Each group also sets `JERD_INTEGRATION=1`. The `database`, `mail`, and
`storage` groups also set their own switch, for example
`JERD_MAIL_INTEGRATION=1`. The database tests read a folder with `pins.json`
and one folder for each engine. `./dev` writes that index in
`.build/runtimes/integration/database` with links to the payloads, so the
payloads stay unchanged.

CI runs the `runtime-integration` job weekly and on manual dispatch. It caches
`.build/runtimes` with a key on every input that changes the prepared bytes:
the files in `Runtimes/`, the deployment target in `Configuration/Base.xcconfig`,
and the preparation code in JerdManifest, JerdRuntimes, and the Tools runtime
steps. `./dev lint` checks that the key covers these paths. Then the job runs `./dev runtimes prepare`, `./dev runtimes verify`, and
`./dev test --integration web,database,mail,storage`.

## Pinned versions

| File | Pins |
| --- | --- |
| `../.xcode-version` | The Xcode that the repository is tested with. CI selects it. |
| `xcodegen-version` | The XcodeGen version. CI installs it after a SHA-256 check. |
| `Package.resolved` | `swift-argument-parser`. |

`./dev doctor` shows a warning when a local version is different.

## Release

`./dev release VERSION BUILD` builds, signs, notarizes, and publishes a release in
one run. Only the maintainer runs it, on the Mac that holds the keys. The private
keys stay in the Keychain.

| Option | Default |
| --- | --- |
| `--minimum-macos M` | `MACOSX_DEPLOYMENT_TARGET` of `Configuration/Base.xcconfig`. A lower value is refused |
| `--identity ID` | The only valid Developer ID Application identity of the team. Give the SHA-1 when two certificates have the same name, for example during a renewal |
| `--team T` | `4L4SS26L9J` |
| `--notary-profile P`, `--keychain K` | `notarytool` in the default Keychain search list |
| `--prepare-only` | Off. See below |

### One-time setup

1. The Developer ID Application identity of the team with its private key in the
   login Keychain. Check with `security find-identity -v -p codesigning`.
2. The notary credentials in the profile `notarytool`:
   `xcrun notarytool store-credentials notarytool --apple-id <Apple ID> --team-id 4L4SS26L9J --password <app-specific password>`.
3. The Sparkle EdDSA private key in the Keychain account `dev.jerd.sparkle`. Run
   `./dev build` once, so that the Sparkle tools are in `.build/SourcePackages`.
4. The prepared runtime payloads: `./dev runtimes prepare`.
5. `gh auth login` with access to `jewei/jerd`.

### Make a release

1. Add the notes under `## [Unreleased]` in `CHANGELOG.md`.
2. Merge everything to `main`, and wait until the `./dev check` job of CI passes for
   the last commit.
3. Optional: run `./dev release VERSION BUILD --prepare-only` for a private candidate.
4. On `main`, run `./dev release VERSION BUILD`.

A candidate takes about 6 minutes on an Apple silicon Mac: about 2 minutes for the
archive and about 3 minutes for the two notarizations. The public steps add the
upload of the disk image.

### What the command does

Each step prints `==> <step>`, and the summary gives the time of each step. All
local work comes first:

1. **Check preconditions.** The tree is clean, also without untracked files.
   VERSION and BUILD exceed every item of the committed, signed `appcast.xml`.
   VERSION is not lower than `Configuration/Version.xcconfig`, and BUILD is not lower
   than its build; when the tag of that version exists, BUILD must be higher. No tag
   of VERSION exists on this Mac. The `## [Unreleased]` notes exist and are plain
   `- ` items. For a publication also: the branch is `main` of `jewei/jerd`, HEAD
   equals the fetched `origin/main`, CI has a successful `./dev check` run for HEAD,
   and no tag, release, or draft of VERSION exists on GitHub. Then the identity, the
   notary profile, the Sparkle key, and every embedded runtime payload are checked.
2. **Archive the app.** A Release archive with the version and build on the
   command line, in `.build/releases/Jerd-VERSION-BUILD` (mode 0700). A new run of the
   same version and build replaces that folder.
3. **Sign and check the app.** It signs every Mach-O file of each embedded payload
   and writes the new digests into the receipt with a signing record. It refuses an
   app that contains any other payload. Then it signs Sparkle, the launcher, the
   helper, and the app, and checks every signature, the Info.plist, arm64, and the
   debug symbols.
4. **Run the signed runtimes.** It runs each embedded executable once from the
   signed app with a version argument (PHP also with `-m`; Composer and the Laravel
   installer with the embedded PHP). Each command has a time limit, a private
   temporary home, and a minimal environment, and none uses the network. A fault that
   only the signed form has, for example a missing entitlement, stops the release.
5. **Notarize the app** and staple it.
6. **Build and notarize the disk image** with `Jerd.app` and a link to
   `/Applications`, then staple it. The image uses `ULMO` (LZMA) compression, which macOS
   opens since 10.15. For Jerd 0.1.1 it is 87 MB, not 122 MB with `UDZO` (zlib) or 120 MB
   with `ULFO` (LZFSE). It takes about a minute to build, and it opens in a few seconds.
7. **Sign the disk image and the feed.** `sign_update` signs the disk image for
   Sparkle, and the candidate feed gets one new item. The item uses
   `<description sparkle:format="plain-text">` with the notes, so Sparkle shows the
   text as it is. `sign_update` then signs the whole feed.
8. **Validate the candidate.** It checks everything again on the final files, the
   app inside the mounted disk image, and that HEAD and the tree did not change.

With `--prepare-only` the command stops here. It allows any branch, changes no
tracked file, and never contacts GitHub. Without it, it continues:

9. **Check the source again.** HEAD and the tree are as before the build, and a new
   fetch shows that `main` on GitHub did not move. Nothing changed yet.
10. **Commit and tag the release.** It writes the version and build into
    `Configuration/Version.xcconfig`, moves the notes under `## [VERSION] - date` in
    `CHANGELOG.md`, copies the candidate feed to `appcast.xml`, commits
    `Release vVERSION`, and makes an annotated tag.
11. **Push the tag.**
12. **Publish the GitHub release** with the disk image and the symbols zip.
13. **Check the uploaded assets.** GitHub must report both assets with the size and
    the SHA-256 of the candidate files.
14. **Publish the feed.** It pushes `main`. Installed apps read the feed from
    `main`, so they see the new item only after the disk image is on GitHub.

The release does not run the full runtime integration tests. CI runs them weekly and
on a manual run of the workflow; see [Integration tests](#integration-tests).

### Recovery

A failed step stops the run. The command then names the step, says what is public,
and prints the exact commands for that step, with absolute paths and the folder to
run them in. A stop by Ctrl-C prints the same text. The commands undo only what the
release did: they restore only the three release files, and they move HEAD only with
`git reset --keep` from the release commit, so edits that are not committed and other
commits stay.

- **Steps 1 to 9.** Nothing was published, and no tracked file changed. Correct the
  cause and run the command again. If `main` moved, pull it and wait for CI first.
- **Commit and tag the release.** Undo the changes of the release:
  `git tag -d vVERSION` (if it exists); if `git log -1 --format=%s` prints
  `Release vVERSION`, `git reset --keep <source commit>`; then
  `git restore --source=<source commit> --staged --worktree -- Configuration/Version.xcconfig CHANGELOG.md appcast.xml`.
- **Push the tag.** If `git ls-remote --tags origin vVERSION` prints a line, the tag
  is public: continue as for a failed **Publish the GitHub release** step. Otherwise
  undo the commit and the tag as above, and run the command again.
- **Publish the GitHub release.** The tag is on GitHub. Run
  `gh release view vVERSION --repo jewei/jerd --json isDraft,assets`. Without a
  release, run the printed `gh release create` command. For a draft, run
  `gh release upload vVERSION <disk image> <symbols> --repo jewei/jerd --clobber` and
  `gh release edit vVERSION --repo jewei/jerd --draft=false`. For a public release with
  both assets, do nothing more here. Then run `git push origin HEAD:main`. To cancel,
  run `gh release delete vVERSION --repo jewei/jerd --yes` (if a release or draft
  exists) and `git push origin :refs/tags/vVERSION`, and undo the commit and the tag
  as above.
- **Check the uploaded assets.** Upload the files again with
  `gh release upload vVERSION <disk image> <symbols> --repo jewei/jerd --clobber`,
  compare them with `gh release view vVERSION --repo jewei/jerd --json assets`, then run
  `git push origin HEAD:main`.
- **Publish the feed.** The release is public, but installed apps do not see it yet.
  Run `git push origin HEAD:main` again. If `main` moved, merge with
  `git pull --no-rebase origin main` (the tag must stay on a commit of `main`). A
  conflict in `CHANGELOG.md` comes from new notes under `## [Unreleased]`: keep the
  section of the release and put the new notes under `## [Unreleased]` above it.
  Check that the new item is the first item of `appcast.xml`, and push.

Each candidate takes about 2.5 GB. Remove an old one by hand, for example
`rm -rf .build/releases/Jerd-0.1.0-6`. Keep the folder of a release whose
publication did not finish, because the recovery commands use its files.

## Manual checks

These two harnesses need an Apple code-signing identity in the Keychain, so CI
does not run them. Each one writes a dated JSON evidence record to
`.build/evidence/<UTC date>-<check>.json`. The record gives the macOS and Xcode
versions, the commit, the dirty state of the worktree, and the result of each
case. A failed run also writes a record.

| Command | What it proves |
| --- | --- |
| `./dev check updates --identity ID` | Sparkle installs only signed updates. It compiles `Fixtures/AppUpdateTest.swift` with the resolved Sparkle (run `./dev build` first) and signs version 1 and version 2 of a temporary test app. Sparkle inside each test app gets the signatures of a release (`AppSigner.signSparkle`), so the update proves them. Each case serves a feed signed with a temporary key on `127.0.0.1`. The cases are `no-update`, `altered-feed`, `altered-archive`, `success`, and `refused-quit`. The test apps copy the Sparkle keys of `Apps/Jerd/Resources/Info.plist` and never load Jerd settings or services. At the end the check stops only its own test processes, removes the defaults domain of the random `dev.jerd.updater-test.*` bundle identifier, its `Preferences` plist file, its `HTTPStorages` folder and cookies, its caches, and its saved state (`UpdateCaseCleanup`), also after a failed case, and removes `.build/check-updates-*`. |
| `./dev check xpc --identity ID` | Signed XPC accepts only the Jerd code identities. It runs the JerdKit test `SignedXPCCheckTests` (it signs the `JerdXPCCheck` probe) with `JERD_XPC_IDENTITY=ID`. The check fails when the test does not run or is skipped. |

## Code layout

| Folder | Contents |
| --- | --- |
| `Sources/JerdDevKit/Process` | The process runner: argument arrays, time limits, separate output |
| `Sources/JerdDevKit/Planning` | Pure plans: the exact command that each command runs |
| `Sources/JerdDevKit/Policies` | Pure repository policies that `./dev lint` checks |
| `Sources/JerdDevKit/Steps` | Steps that run plans and policies and report results |
| `Sources/JerdDevKit/Runtimes` | Payload preparation, verification, embedding, the XZ build, and integration paths |
| `Sources/JerdDevKit/Release` | The release command: preconditions, local steps, public steps, and recovery |
| `Sources/JerdDevKit/Checks` | The manual harnesses and their evidence records |
| `Sources/JerdDevKit/Commands` | One file for each command; `CommandCatalog` lists them |
| `Scripts/embed-app-contents.sh` | The Xcode build phase that embeds the helper, CLI, and runtimes |
| `Fixtures` | Swift sources that the harnesses compile at run time; not part of the package |

The package uses the JerdKit products `JerdManifest` and `JerdRuntimes`, so the
tool and the app share one set of receipt, pin, and feed rules.

To add a command, add one file in `Commands/` and one entry in `CommandCatalog`.
