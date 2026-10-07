# Changelog

This file lists the changes that users see. Add one line under `## [Unreleased]`
for each such change. `./dev release bump` moves these lines under the new
version, and Sparkle shows them in the update window as plain text. Thus write
each note as one `- ` list item, without headings, links, or code marks.

## [Unreleased]

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
- Jerd is much smaller: it no longer includes MySQL and PostgreSQL. Install one from the Databases page, or add a database and Jerd installs the engine first. Redis stays included, and engines that you already have stay installed.
