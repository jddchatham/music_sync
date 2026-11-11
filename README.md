# Music Sync

A native, cross-platform replacement for the discontinued **Maxell Music Auto Backup** tool (the 2010 DMailer-based sync program that shipped on Maxell myGEN USB sticks). Pick your music folders, pick a USB stick, sync — no Wine, no 32-bit Windows binaries.

## Features

- Multiple source folders
- Auto-detects mounted USB drives with free-space display
- Music-only filtering (mp3, flac, wav, ogg, m4a, aac, wma, opus, aiff) — or sync everything
- Incremental sync: copies only new/changed files (size + mtime with FAT-timestamp tolerance)
- Optional mirror mode: delete USB files no longer present in sources
- Progress display with cancel
- Optional eject-when-done (via udisksctl)
- Settings persisted to `~/.config/music_sync/`

## Platforms

| Platform | Status |
|---|---|
| Linux (desktop) | Working |
| Android | Planned — same Flutter codebase, USB access via Storage Access Framework |

## Build & run (Linux)

```sh
flutter pub get
flutter run -d linux          # debug
flutter build linux --release # release bundle in build/linux/x64/release/bundle/
```

## Test

```sh
flutter test        # engine unit tests (temp dirs, no USB needed)
dart run tool/smoke_test.dart   # end-to-end against a real USB stick
```

## Layout

- `lib/sync_engine.dart` — pure sync logic (source scan, change detection, copy, mirror)
- `lib/usb_detect.dart` — Linux removable-drive detection (df/udisks)
- `lib/settings.dart` — JSON config persistence
- `lib/main.dart` — Flutter UI
- `tool/smoke_test.dart` — end-to-end smoke test against real hardware
