import 'dart:io';

import '../lib/io_fs.dart';
import '../lib/sync_engine.dart';

Future<void> main() async {
  const dest = '/run/media/user/PHILIPS UFD/Music';
  final exts = {'.mp3', '.flac'};

  Future<SyncStats> runOnce() => Syncer(
        sources: [IoFileSystem('/home/user/Downloads/maxell-work/testmusic')],
        dest: IoFileSystem(dest),
        extensions: exts,
        onProgress: (s) {},
      ).run();

  // pass 1: initial copy
  var s = await runOnce();
  print('PASS1: planned=${s.planned} copied=${s.copied} failed=${s.failed} bytes=${s.bytesCopied}');
  assert(s.copied == 5, 'expected 5 files copied, got ${s.copied}');
  assert(s.failed == 0, 'failures during pass 1');

  // notes.txt must NOT be on the stick
  final txt = await File('$dest/notes.txt').exists();
  print('notes.txt present on USB (should be false): $txt');
  assert(!txt, 'non-audio file leaked to USB');

  // pass 2: nothing changed -> nothing copied
  s = await runOnce();
  print('PASS2: copied=${s.copied} failed=${s.failed}');
  assert(s.copied == 0, 'pass 2 should copy nothing, copied ${s.copied}');

  // modify one file -> exactly one re-copy
  final f = File('/home/user/Downloads/maxell-work/testmusic/Rock/song2.mp3');
  await f.writeAsBytes(List.filled(999, 7));
  s = await runOnce();
  print('PASS3: copied=${s.copied} failed=${s.failed}');
  assert(s.copied == 1, 'pass 3 should copy 1 changed file, copied ${s.copied}');

  // mirror mode: remove a source file, mirror deletes it from USB
  await f.delete();
  s = await Syncer(
    sources: [IoFileSystem('/home/user/Downloads/maxell-work/testmusic')],
    dest: IoFileSystem(dest),
    extensions: exts,
    mirror: true,
  ).run();
  print('PASS4(mirror): deleted=${s.deleted} failed=${s.failed}');
  assert(s.deleted == 1, 'mirror should delete 1 file, deleted ${s.deleted}');
  final gone = !await File('$dest/Rock/song2.mp3').exists();
  print('song2.mp3 removed from USB (should be true): $gone');

  print('ALL SMOKE TESTS PASSED');
}
