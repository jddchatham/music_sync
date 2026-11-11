#!/bin/sh
# Music Sync - portable launcher for FAT32 USB sticks.
# FAT32 does not store the execute permission, so this copies the app
# to a temporary folder, makes it executable there, and runs it.
set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Copying Music Sync to $TMP_DIR ..."
cp -r "$SCRIPT_DIR" "$TMP_DIR/app"
chmod +x "$TMP_DIR/app/music_sync"
exec "$TMP_DIR/app/music_sync" "$@"
