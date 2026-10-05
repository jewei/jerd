#!/bin/sh
# Xcode build phase: copy the helper, the launcher, and prepared runtime payloads
# into the app bundle. Payloads come from `./dev runtimes prepare`, one folder for
# each runtime group in Runtimes/ that has a pin.json or pins.json file:
# .build/runtimes/payloads/<Group>/ (Database, Development, Mail, Storage).
#
# JERD_REQUIRE_RUNTIMES=YES (Release) refuses a missing or empty payload folder and
# a group folder that is missing or has no files. This is an interim guard: the
# check of each receipt against its pin and of each file digest comes with
# `jerd-dev runtimes verify` and JerdManifest (review tooling-r1, H1). The app also
# verifies every payload receipt before it installs a runtime.
set -eu

contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"

mkdir -p "$contents/Library/LaunchServices" "$contents/Library/LaunchDaemons" "$contents/MacOS"
cp "$BUILT_PRODUCTS_DIR/JerdHelper" "$contents/Library/LaunchServices/JerdHelper"
cp "$BUILT_PRODUCTS_DIR/JerdCLI" "$contents/MacOS/JerdCLI"
cp "$SRCROOT/Apps/JerdHelper/dev.jerd.helper.plist" "$contents/Library/LaunchDaemons/dev.jerd.helper.plist"

payloads="$SRCROOT/.build/runtimes/payloads"

# Succeeds when the folder exists and has at least one regular file.
has_files() {
	[ -n "$(find "$1" -type f ! -name .DS_Store -print 2>/dev/null | head -n 1)" ]
}

# Prints the name of each pinned runtime group whose payload folder has no regular file.
missing_groups() {
	for folder in "$SRCROOT"/Runtimes/*/; do
		[ -f "${folder}pin.json" ] || [ -f "${folder}pins.json" ] || continue
		group=$(basename "$folder")
		has_files "$payloads/$group" || echo "$group"
	done
}

if [ "${JERD_REQUIRE_RUNTIMES:-NO}" = "YES" ]; then
	missing=$(missing_groups | tr '\n' ' ' | sed 's/ $//')
	if ! has_files "$payloads" || [ -n "$missing" ]; then
		echo "error: Runtime payloads are missing or incomplete in .build/runtimes/payloads (missing: ${missing:-all}). Run ./dev runtimes prepare." >&2
		exit 1
	fi
fi

if has_files "$payloads"; then
	mkdir -p "$resources/RuntimePayloads"
	rsync -a --delete "$payloads/" "$resources/RuntimePayloads/"
else
	echo "warning: Runtime payloads are missing. The app builds without runtimes. Run ./dev runtimes prepare." >&2
	rm -rf "$resources/RuntimePayloads"
fi
