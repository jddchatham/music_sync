import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_sync/sync_engine.dart';

Future<SyncStats> runSync(String src, String dest,
    {bool mirror = false, Set<String> exts = const {'.mp3', '.flac'}}) {
  return Syncer(
    sources: [src],
    destRoot: dest,
    extensions: exts,
    mirror: mirror,
  ).run();
}

void main() {
  test('copies only audio, skips unchanged, recopies changed, mirrors deletes',
      () async {
    final tmp = await Directory.systemTemp.createTemp('musync_test');
    final src = Directory('${tmp.path}/src');
    final dest = Directory('${tmp.path}/dest');
    await src.create(recursive: true);
    await dest.create(recursive: true);

    await File('${src.path}/a.mp3').writeAsBytes(List.filled(100, 1));
    await File('${src.path}/b.flac').writeAsBytes(List.filled(200, 2));
    await File('${src.path}/notes.txt').writeAsBytes(List.filled(50, 3));

    // pass 1: audio only
    var s = await runSync(src.path, dest.path);
    expect(s.copied, 2);
    expect(s.failed, 0);
    expect(await File('${dest.path}/notes.txt').exists(), isFalse);

    // pass 2: nothing to do
    s = await runSync(src.path, dest.path);
    expect(s.copied, 0);

    // change one file
    await File('${src.path}/a.mp3').writeAsBytes(List.filled(120, 9));
    s = await runSync(src.path, dest.path);
    expect(s.copied, 1);

    // mirror: deleted source file disappears from dest
    await File('${src.path}/b.flac').delete();
    s = await runSync(src.path, dest.path, mirror: true);
    expect(s.deleted, 1);
    expect(await File('${dest.path}/b.flac').exists(), isFalse);

    await tmp.delete(recursive: true);
  });

  test('cancel stops the sync', () async {
    final tmp = await Directory.systemTemp.createTemp('musync_cancel');
    final src = Directory('${tmp.path}/src');
    final dest = Directory('${tmp.path}/dest');
    await src.create(recursive: true);
    await dest.create(recursive: true);
    for (var i = 0; i < 5; i++) {
      await File('${src.path}/f$i.mp3').writeAsBytes(List.filled(10, i));
    }
    var calls = 0;
    final s = await Syncer(
      sources: [src.path],
      destRoot: dest.path,
      extensions: const {'.mp3'},
      shouldCancel: () => ++calls > 1,
    ).run();
    expect(s.cancelled, isTrue);
    await tmp.delete(recursive: true);
  });
}
