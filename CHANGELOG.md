# Changelog

This file lists the changes that users see. Add one line under `## [Unreleased]`
for each such change. The release commit of `./dev release` moves these lines
under the new version, and Sparkle shows them in the update window as plain
text. Thus write each note as one `- ` list item, without headings, links, or
code marks.

## [Unreleased]

- A damaged tunnel settings file no longer stops your sites from starting or changing.
- Stopping a tunnel while it connects no longer stops all sites, and a failed restart for a tunnel now restores the sites that ran.
- Connecting a tunnel now waits for a running site change instead of failing, and restarts the sites only when the tunnel's public hostname changed.
- When a site stops, is removed, or gets a new hostname, Jerd now stops the tunnels that route to it, so public traffic cannot reach another site.
- The tunnel editor now asks you to confirm the route in both modes, starts without a local address, and says that a route set by Jerd works only for a locally managed tunnel.
- Connect when Jerd opens is now off for a tunnel that routes to a Jerd site, because sites do not start when Jerd opens.
- A public tunnel hostname that ends in .test is now refused, because Cloudflare cannot route it.

## [0.1.4] - 2026-10-10

- Local tunnels now keep their public hostname when serving PHP, so generated assets, links, and redirects use the public address instead of the local .test address.

## [0.1.3] - 2026-10-10

- Jerd can now configure locally managed Cloudflare tunnels from the selected site, including the local route and verified HTTPS connection.

## [0.1.2] - 2026-10-08

- Jerd now asks one time whether to check for updates automatically, so you learn about new versions. It still installs an update only after you approve it.
- HTTPS keeps working after an app update. The system helper now stops by itself when it has no work, and Jerd restarts an outdated helper one time without a question. Your host entries and certificate settings do not change.
- Reconnect Helper is more reliable: Jerd waits until the old helper has stopped before it starts the new one, so it no longer fails with "Operation not permitted".
- Clearer helper messages: when Jerd cannot reach its helper, the Sites page shows a Reconnect Helper button. When the helper is not allowed in Login Items, it shows Open Login Items and Check Again buttons. The messages no longer name a menu that you cannot see.
- Jerd starts more smoothly, because it no longer checks its code signature on the main thread at launch.

## [0.1.1] - 2026-10-08

- Jerd is smaller: it no longer includes Mailpit. Start Mail or Install Mailpit on the Mail page downloads it first (about 10 MB). A Mailpit that you already have stays in use, and your captured mail stays.
- The download is about 30 percent smaller, because the disk image uses stronger compression. The PHP, Mailpit, and Redis programs also use less disk space.
- The app is a little smaller: the Redis runtime and the Laravel installer no longer include build output, documentation, tests, and translations that they do not use.

## [0.1.0] - 2026-10-07

- Jerd is rebuilt from the ground up. Your sites, PHP selections, databases, mail, buckets, tunnels, and settings stay where they are.
- Security: PHP now runs only the script that the site routes select. A path such as /index.php/storage/upload.php can no longer run an uploaded or vendor PHP file.
- Jerd now runs only on Macs with Apple silicon, with macOS 14 or later.
- Quit lets each data service stop safely. When a service does not stop in 30 seconds, Jerd keeps it running and cancels Quit.
- After a crash, Jerd finds the processes that still run and offers Process recovery. It no longer reports only that a port is occupied.
- HTTPS setup, removal, and recovery undo their own steps when one step fails. Changes that other tools make to the hosts file stay.
- A rejected tunnel token and a lost connection now show different messages. A permanent error stops the retries.
- The php, composer, and laravel commands use the PHP of the registered project that contains the current folder.
- Jerd checks each runtime download and installed runtime against its pinned digest before use.
- The Lock and Stack icons are removed. If you used one, Jerd now shows the Rainbow hook icon.
- Jerd is much smaller: it no longer includes MySQL, PostgreSQL, and the RustFS storage server. Install an engine from the Databases page, or add a database and Jerd installs the engine first. Start Storage installs RustFS first. Redis and Mailpit stay included, and runtimes that you already have stay installed.
