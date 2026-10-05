#!/bin/sh
# Xcode build phase: copy the helper, the launcher, and prepared runtime payloads
# into the app bundle. Payloads come from `./dev runtimes prepare`. The app
# verifies every payload receipt again before it installs a runtime.
set -eu

contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"

mkdir -p "$contents/Library/LaunchServices" "$contents/Library/LaunchDaemons" "$contents/MacOS"
cp "$BUILT_PRODUCTS_DIR/JerdHelper" "$contents/Library/LaunchServices/JerdHelper"
cp "$BUILT_PRODUCTS_DIR/JerdCLI" "$contents/MacOS/JerdCLI"
cp "$SRCROOT/Apps/JerdHelper/dev.jerd.helper.plist" "$contents/Library/LaunchDaemons/dev.jerd.helper.plist"

payloads="$SRCROOT/.build/runtimes/payloads"
if [ -d "$payloads" ]; then
	mkdir -p "$resources/RuntimePayloads"
	rsync -a --delete "$payloads/" "$resources/RuntimePayloads/"
elif [ "${JERD_REQUIRE_RUNTIMES:-NO}" = "YES" ]; then
	echo "error: Runtime payloads are missing. Run ./dev runtimes prepare." >&2
	exit 1
else
	echo "warning: Runtime payloads are missing. The app builds without runtimes. Run ./dev runtimes prepare." >&2
	rm -rf "$resources/RuntimePayloads"
fi
