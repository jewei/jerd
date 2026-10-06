# JerdCLICore

JerdCLICore supplies the `php`, `composer`, and `laravel` commands. It selects the PHP
runtime of the registered project that contains the working folder, prepares the CLI INI,
and runs PHP. It also installs the commands for zsh. It depends on JerdFoundation,
JerdRuntimes, and JerdWeb. `Apps/JerdCLI/main.swift` only calls `CLILauncher`.

## Main types

| Type | Purpose |
| --- | --- |
| `CLICommand` | The command that the link name selects. |
| `CLIRuntimeResolver`, `CLIRuntimeSelection` | The PHP runtime for a working folder. Pure. |
| `PHPINIArguments`, `CLIIniDecision` | The one rule for the INI file and the TLS trust. Pure. |
| `CLIIniWriter` | Writes `cli.ini`, `cli-local-tls.ini`, and the empty scan folder. |
| `CLILaunchPlanner`, `CLILaunchPlan` | The exact argument vector, environment, and PATH. Pure. |
| `CLILauncher` | Loads the configuration for each call, plans, and calls `execv`. |
| `ShellPathBlockEditor` | Inserts or replaces the managed PATH block. Pure. |
| `ShellSetupInstaller` | Installs the launcher, the three links, and the PATH block. |

Ports: `ProcessImageReplacing` (`ProcessImage`, `execv`), `DiagnosticWriting`
(`StandardErrorWriter`), `CLICABundlePreparing` (JerdWeb `PHPCABundleBuilder`), and
`LauncherSignatureChecking` (`CodeSignatureCheck`).

## App entry points

The app uses only these calls (all on the actor `ShellSetupInstaller`):

| Call | Purpose |
| --- | --- |
| `ShellSetupInstaller.live(appBundle:)` | The installer for the current user (`HOME`) and the running app's signer. |
| `install() throws -> ShellSetupReport` | Runs the setup. `report.summary` gives the lines for the user, with the backup path. |
| `state() -> CommandLineToolsState` | `.notInstalled`, `.installed`, or `.outdatedLauncher`, with a one-line `summary`. |
| `refreshLauncherIfInstalled() throws -> Bool` | At app launch: replaces an outdated `bin/JerdCLI` through the same staged, signature-checked path. Shell files do not change. |

The "Install Command-Line Tools" control in Dashboard > Advanced calls `install()`.

## Rules

- The deepest registered project that contains the folder wins, after symbolic link
  resolution and by path components. Two equal matches are an error. A disabled site
  keeps its pin. A missing selection fails. There is no fallback.
- `PHPRC`, or `-n`, `-c`, or `--php-ini` before the `php` script: Jerd adds no INI.
  `composer` and `laravel` give INI options to their script.
- `SSL_CERT_FILE`, `SSL_CERT_DIR`, or `CURL_CA_BUNDLE`: Jerd's INI without the local CA.
- Else Jerd's INI with the local CA when macOS trusts it. A CA failure gives one warning,
  and PHP runs without the local CA.
- `PHP_INI_SCAN_DIR` is Jerd's empty folder unless the user set it.
- The command line is `<php> [-c <ini>] [<script>] <user arguments>`. `PATH` starts with
  Jerd's `bin` folder once. A missing or empty `PATH` becomes `/usr/bin:/bin`.
- Errors go to standard error as `Jerd: <message>`, with exit status 1. After `execv`,
  the exit status is PHP's.
- Runtime trust, one rule (`CLIRuntimeOrigin`). A managed runtime (below `runtimes/` or
  `runtime-updates/`, installed by Jerd with a receipt) is verified against its receipt when
  the shell setup runs. A failure stops the setup. An imported runtime (anywhere else) is
  trusted, because the user chose it explicitly, and never blocks the setup. The launcher does
  not hash a runtime on each call, because that is slow. It checks only that the selected
  executable is a regular file that the user can run.
- The setup checks everything before it writes.
- The setup edits the existing `.zprofile` and `.zshrc`, or creates `.zshrc` (mode 0600)
  when neither exists. It never replaces a symbolic link, a hard link, a file of another
  user, a non-UTF-8 file, or a malformed block. The editor works on bytes: a UTF-8 byte order
  mark, CRLF line ends, and the bytes around the block stay.
- Originals go to `shell-backups/<YYYYmmdd-HHMMSS-ffffff>/` (0700, files 0600). Each file
  is replaced atomically with its mode. A new `.zshrc` is created with `RENAME_EXCL`, so a
  file that appears during the setup stays. A failure restores the files already replaced,
  but only while they still have the setup's bytes. An edited file stays, and the error
  names it and its backup.
- The launcher copy `bin/JerdCLI` (0700) must have a valid code signature from the app's
  signer (`CodeSignatureCheck.forRunningApp()`). For a signed app, the rule is
  `anchor apple generic` with the app's Team ID. For an ad hoc or unsigned development app,
  only an ad hoc launcher passes. The links
  `php`, `composer`, and `laravel` point to `JerdCLI`. The setup removes leftovers of a
  crashed run (`.zshrc.jerd-tmp`, `.JerdCLI-next`, `.php-next`).

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdCLICoreTests
```

The tests use temporary folders as the data root and the home folder. They never touch
the real shell files. The smoke test runs the launch plan with a fake PHP script.
