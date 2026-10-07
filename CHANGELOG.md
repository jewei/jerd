# Changelog

## [Unreleased]

- Serve registered PHP sites together with local HTTPS and per-site PHP selection.
- Add PHP, Composer, and Laravel installer command-line tools.
- Manage separate MySQL, PostgreSQL, Redis, mail, and S3 storage services.
- Manage existing Cloudflare Tunnel connectors with Keychain tokens, native runtimes, and per-connector controls.
- Add Dashboard settings, runtime management, and signed app update checks.
- Refine native service pages and simplify icon choices.
- Switch top tabs without page fades or toolbar movement, while retaining sidebar, scroll, and editor state.
- Preserve concurrent hosts-file changes during setup and provide access to web logs in Sites.
- Add a local release procedure with runtime signing and Apple notarization.
- Run only the PHP script that the site routes select. Path-info URLs such as
  `/index.php/storage/upload.php` no longer run uploads or `vendor` files, `/index.php/route`
  works with `PATH_INFO`, a script must end in lowercase `.php` on disk, and `.pht`, `.phps`,
  `.phpt`, `.php[0-9]`, and `.inc` files answer 404.
