# Music Sync

A native, cross-platform replacement for the discontinued **Maxell Music Auto Backup** tool (the 2010 DMailer-based sync program that shipped on Maxell myGEN USB sticks). Pick your music folders, pick a USB stick, sync — no Wine, no 32-bit Windows binaries.

## Features

- Multiple source folders
- Auto-detects mounted USB drives with free-space display (Linux) or SAF tree picking (Android)
- Music-only filtering (mp3, flac, wav, ogg, m4a, aac, wma, opus, aiff) — or sync everything
- Incremental sync: copies only new/changed files (size + mtime on desktop, size-based on Android where SAF hides mtimes)
- Optional mirror mode: delete USB files no longer present in sources
- Progress display with cancel
- Optional eject-when-done on Linux (via udisksctl)
- Settings persisted per platform

## Platforms

| Platform | Status | USB access |
|---|---|---|
| Linux (desktop) | Working | direct mount (`/run/media`) |
| Android | Working (APK) | Storage Access Framework (pick the stick once, remembered) |
| Windows | Use the original Maxell `.exe` | n/a |

## Architecture

The sync engine talks to a filesystem abstraction, not `dart:io` directly — that is what makes the Android port share ~all of its logic with the desktop build:

- `lib/sync_fs.dart` — `SyncFs` interface (walk / read / create / delete / setModified) + `FsEntry`
- `lib/io_fs.dart` — desktop implementation over `dart:io`
- `lib/saf_fs.dart` — Android implementation over Storage Access Framework (MethodChannel)
- `lib/sync_engine.dart` — pure sync planning/execution on top of `SyncFs`
- `lib/usb_detect.dart` — Linux removable-drive detection (df/udisks)
- `lib/main.dart` — Flutter UI (small per-platform branches)
- `android/.../SafPlugin.kt` — native SAF bridge (tree picker, chunked read/write)

## Build & run

Linux:
```sh
flutter pub get
flutter run -d linux          # debug
flutter build linux --release # bundle in build/linux/x64/release/bundle/
```

Android:
```sh
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

## Test

```sh
flutter test                    # engine unit tests (temp dirs, no USB needed)
dart run tool/smoke_test.dart   # end-to-end against a real USB stick (Linux)
```
