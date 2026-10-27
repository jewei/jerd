# Changelog

This file lists the changes that users see. Add one line under `## [Unreleased]`
for each such change. The release commit of `./dev release` moves these lines
under the new version, and Sparkle shows them in the update window as plain
text. Thus write each note as one `- ` list item, without headings, links, or
code marks.

## [Unreleased]

## [0.1.6] - 2026-10-27

- Redis now stops when Jerd asks, also after the Mac woke from a deep sleep on low battery. Before, Redis could ignore Stop and Quit, and block a restart.
- The php, composer, and laravel commands start faster, because the check of the local HTTPS CA takes less time.
- An existing installation can update its local CA to one that can sign only .test hostnames: choose Update CA on the Sites page and approve once. Jerd then stops trusting the old CA.
- New installations get a local CA that can sign certificates only for .test hostnames, so a stolen CA key cannot fake any other website.
- A new HTTPS setup, for example after Remove System Setup, now always uses the CA for .test hostnames. The Jerd helper no longer trusts a new CA that can sign any name.
- A site can have aliases: more .test hostnames that serve the same document root, for example for tenants. Add them in Edit Site, then approve HTTPS for the new names.
- Process recovery no longer reports that a saved process could not be stopped when the process exits during the stop.
- Create a Cloudflare Tunnel in one step: connect Cloudflare once with an API token, then choose a domain, a subdomain, and a site. Jerd creates the tunnel and its DNS record and connects it.
- Removing a tunnel that Jerd created can also delete the tunnel and its DNS record in Cloudflare.
- A connected tunnel now warns you when its public hostname has no DNS record, with the record to add in Cloudflare.
- Sidebar rows no longer show through the Add button and the count at the bottom of a long Sites, Databases, or Storage list, and the count no longer gets cut off in a narrow window.
- A sidebar that cannot load its settings now shows the full message on two lines.
- The Storage page now tells you to install RustFS first when its settings load and RustFS is not installed.
- The Edit Cloudflare Tunnel sheet now says that Save changes the registration. It no longer says that Save adds one.
- The Advanced page and the shell setup report now describe the PHP selection of php, composer, and laravel with one sentence, and each registered PHP runtime labels its registration ID and default mark.
- Text on the Runtimes, Advanced, About, Sites, and Mail pages now uses short, active sentences, and the Connection Checks use one result text for both checks.
- A database service page no longer repeats that database files remain after Stop, Quit, or removal.
- When the settings of sites, tunnels, databases, storage, or mail do not load, the sidebar, the page, and the Dashboard card now use the same message.
- When the Jerd helper is turned off in Login Items or is not registered, starting sites now tells you what to do and offers Open Login Items or Reconnect Helper.
- A Keychain failure of the Cloudflare API token now names the Cloudflare API token, not a tunnel token.
- When recovery cannot stop a saved process, the message now shows the system cause and tells you to quit the process in Activity Monitor.
- Removing the Jerd section from the hosts file no longer joins your line before the section with the line after it.
- A database start no longer sends the database password to another program that took the database port. Jerd now checks that its own server holds the port before each readiness check.
- A service error message can no longer show part of a password from the end of the service log.
- When Jerd cannot read the Cloudflare API token from the Keychain or load your domains, the tunnel editor now shows the error with a way to connect or load again.
- When the Cloudflare API token lacks a permission, Jerd now lists the permissions that the token needs.
- When a Create fails because Cloudflare already has a tunnel with the same name, for example after a lost answer, Jerd now names that tunnel so that you can delete it.
- Create in Cloudflare now accepts only a subdomain without a dot, because Cloudflare's free certificate covers only one level below the domain.
- When Cloudflare is not connected, Remove and Delete in Cloudflare now says where to connect it.
- Check Again on a missing DNS record warning now works while Jerd checks another tunnel.

## [0.1.5] - 2026-10-10

- A damaged tunnel settings file no longer stops your sites from starting or changing.
- Stopping a tunnel while it connects no longer stops all sites, and a failed restart for a tunnel now restores the sites that ran.
- Connecting a tunnel now waits for a running site change instead of failing, and restarts the sites only when the saved public hostnames of local tunnels changed.
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
