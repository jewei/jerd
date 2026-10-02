# Use Jerd

Use trusted local projects. PHP code runs with your user account's permissions.
For data paths and recovery limits, see [Data and components](Reference.md).

## Add a site

1. Open **Sites > Add site**.
2. Choose an existing project folder.
3. Check the suggested `.test` hostname.
4. Check the document root. For Laravel, use the project's `public` directory.
5. Save the registration.
6. Review the enabled hostnames, CA fingerprint, and trust scope on the HTTPS setup screen.
7. Select **Approve and start**.
8. If macOS requests approval, complete it in **Login Items & Extensions**.
9. If approval was pending, select **Approve and start** again.
10. When the site shows **Ready**, select **Open in Browser**.

HTTPS setup changes the hosts file and trusts Jerd's CA for TLS server certificates.
That trust covers all hostnames. Jerd routes only registered `.test` names on loopback.
For the permission boundary, see [Hosts and certificates](Architecture.md#hosts-and-certificates).

## Control sites

- To run all enabled sites, select **Start all sites**.
- To stop the web environment, select **Stop all sites**.
- To retain a registration without its route, disable that site.
- To remove a registration and its host mapping, remove that site.
- To remove all host mappings, CA trust, and helper registration, select **System setup > Remove system setup**.

These actions retain project files. A change to a running site's settings
restarts the web environment and briefly affects all enabled sites.
A new hostname requires HTTPS approval for the updated list.

For PHP inspection and local executable selection, open **Dashboard > Advanced**.
A missing pinned PHP version causes an error. Jerd does not select another version automatically.

## Add a database

1. Open **Databases** and select the add control.
2. Select MySQL, PostgreSQL, or Redis.
3. Enter a service name.
4. Check the suggested free port and runtime version.
5. Save the service.
6. Select **Start**.
7. Copy the connection settings into your database client or Laravel project.

Each service has its own data directory and generated password.
To change an engine version, create a new service and use the engine's export/import tools.
Removal deletes the registration after shutdown. It retains data and credentials.

## Add a storage bucket

1. Open **Storage > Add bucket**.
2. Enter an S3 bucket name.
3. For anonymous object reads, enable public read. Otherwise, leave it off.
4. Select **Save**.
5. Wait for **Ready**. Jerd starts RustFS and checks the bucket before it reports this state.
6. Select **Copy Laravel settings**.
7. Apply those settings to your project with its S3 filesystem adapter.
8. To manage objects, select **Open console**.
9. Sign in with **Copy access key** and **Copy secret key**.

Buckets share one RustFS service and credential pair. Public read permits object
reads only. Anonymous listing, uploads, and deletion remain blocked.
The S3 and console endpoints use HTTP on `127.0.0.1`.

To change ports, stop storage and open **Storage settings**.
If bucket setup fails, retry the saved incomplete entry.
A missing completed bucket is reported; Jerd does not recreate it automatically.

## Capture mail

1. Open **Mail** and select **Start mail**.
2. Select **Copy Laravel settings**.
3. Apply the settings to your project.
4. Select **Send test email**, or send a message from your application.
5. Select **Open inbox** to view Mailpit in your browser.

The copied settings select local SMTP without authentication or TLS.
Jerd does not configure external delivery. Stop and Quit retain captured messages.
To change ports, stop mail and select **Edit ports**.
To delete messages, use the inbox. Automatic message deletion is disabled.

## Change appearance

1. Open **Dashboard > Appearance**, or press `Command-,`.
2. Set the menu bar and Dock switches independently.
3. Select the app icon.

If both switches are off, open Jerd from Applications to restore its window.
The selected icon applies while the app runs. Closing the window keeps Jerd open.
To stop the owned services and exit, select **Quit Jerd**.
If a data service cannot stop within its grace period, Jerd stays open.
Start data services manually after you reopen the app.

## Install a runtime version

1. Open **Dashboard > Runtimes**.
2. Select **Check for runtime updates**.
3. Select an available stable version for this Mac.
4. Select the install action. For PHP, choose **Install & use** or **Install only**.

A new default PHP version restarts running sites. Pinned sites retain their selection.
Database installation adds a version for new services. Existing database services retain their versions.
Mail and storage updates save a private backup before they change the runtime.
A failed update restores the saved data and settings when the candidate has stopped.

## Check for an app update

1. Open **Dashboard > About**.
2. Select **Check for app updates**.
3. If Sparkle offers an update, review the release details.
4. Select the install action to download and install the signed app.

You can also use **Jerd > Check for Updates**.
To enable periodic checks, turn on **Automatically check for app updates** in About.
Automatic checks start disabled. Installation requires your action.
Jerd stops its services before replacement. A cancelled shutdown prevents installation.
After relaunch, start the data services you need.

The initial feed has no update archive. Until a release is published, a successful
check reports that no new update is available.

## Set up PHP, Composer, and Laravel commands

After the signed app installs its tools, run this optional setup from the repository:

```sh
python3 Scripts/Development/setup-php-cli.py
exec zsh -l
php --version
composer --version
laravel new --help
```

The script backs up `.zprofile` and `.zshrc` before it adds Jerd's bin directory to PATH.
It refuses to replace unrelated commands in that directory.

Before you run Composer, use `cd` to enter the intended project.
The launcher selects PHP from the current directory's most specific registered project.
Outside registered projects, it uses the default PHP version.
`composer --working-dir` does not change this selection.

After a CLI launcher update, rerun the setup script.
To remove shell integration, remove the marked Jerd block from both shell files.
Then remove only Jerd's `php`, `composer`, and `laravel` links from its private bin directory.
