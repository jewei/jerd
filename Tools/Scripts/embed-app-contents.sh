#!/bin/sh
# Xcode build phase: copy the helper, the launcher, and the prepared runtime payloads into the app.
#
# Payloads come from `./dev runtimes prepare` in .build/runtimes/payloads/<group>/<payload ID>.
# Pins that Runtimes/runtimes.json marks `"embedded": false` (MySQL and PostgreSQL) stay out of
# the app. The app installs them on demand from the same pins.
# `./dev runtimes embed` verifies each receipt against its pin in Runtimes/runtimes.json, and every
# file against its SHA-256 and executable flag, before it copies anything. It copies with
# `rsync --delete`, so unchanged payloads are not copied again on every build.
#
# Why this script calls ./dev instead of checking the files itself: the receipt rules live in
# JerdManifest and JerdRuntimes, the same code that the app uses to install the payloads. A shell
# copy of those rules would be a third implementation that drifts. The `dev` shim builds jerd-dev
# only when a Tools source changed, so a build from Xcode works too. The tool runs with a minimal
# environment, because the Xcode build settings in the environment would change the SwiftPM build.
#
# JERD_REQUIRE_RUNTIMES=YES (Release) requires every embedded payload. Without payloads, Debug and
# the check build (`--allow-missing-runtimes`) warn and build an app without runtimes.
set -eu

contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/RuntimePayloads"
payloads="$SRCROOT/.build/runtimes/payloads"
# Tests set JERD_DEV_COMMAND to a fake tool. Builds use the shim in the repository.
tool="${JERD_DEV_COMMAND:-$SRCROOT/dev}"

mkdir -p "$contents/Library/LaunchServices" "$contents/Library/LaunchDaemons" "$contents/MacOS"
cp "$BUILT_PRODUCTS_DIR/JerdHelper" "$contents/Library/LaunchServices/JerdHelper"
cp "$BUILT_PRODUCTS_DIR/JerdCLI" "$contents/MacOS/JerdCLI"
cp "$SRCROOT/Apps/JerdHelper/dev.jerd.helper.plist" "$contents/Library/LaunchDaemons/dev.jerd.helper.plist"

require=NO
[ "${JERD_REQUIRE_RUNTIMES:-NO}" = "YES" ] && require=YES

if [ "$require" = "NO" ] && [ -z "$(find "$payloads" -name payload-receipt.json -print 2>/dev/null | head -n 1)" ]; then
	echo "warning: Runtime payloads are missing. The app builds without runtimes. Run ./dev runtimes prepare." >&2
	rm -rf "$destination"
	exit 0
fi

set -- runtimes embed "$destination"
[ "$require" = "YES" ] && set -- "$@" --require-all

if [ -n "${DEVELOPER_DIR:-}" ]; then
	exec /usr/bin/env -i HOME="${HOME:-}" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="${TMPDIR:-/tmp}" \
		DEVELOPER_DIR="$DEVELOPER_DIR" "$tool" "$@"
fi
exec /usr/bin/env -i HOME="${HOME:-}" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="${TMPDIR:-/tmp}" "$tool" "$@"
