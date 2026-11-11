import 'dart:io';

class SyncStats {
  int planned = 0;
  int copied = 0;
  int deleted = 0;
  int failed = 0;
  int bytesCopied = 0;
  int bytesTotal = 0;
  String currentFile = '';
  bool cancelled = false;

  double get fraction => bytesTotal == 0 ? 0 : bytesCopied / bytesTotal;

  Map<String, Object> toJson() => {
        'planned': planned,
        'copied': copied,
        'deleted': deleted,
        'failed': failed,
        'bytesCopied': bytesCopied,
        'bytesTotal': bytesTotal,
        'cancelled': cancelled,
      };
}

class _Item {
  final String srcPath;
  final String relPath; // path relative to its source root
  final int size;
  _Item(this.srcPath, this.relPath, this.size);
}

typedef ProgressFn = void Function(SyncStats stats);
typedef CancelFn = bool Function();

class Syncer {
  final List<String> sources;
  final String destRoot;
  final Set<String> extensions; // lowercase with dot, e.g. {'.mp3'}; empty = all files
  final bool mirror;
  final ProgressFn? onProgress;
  final CancelFn? shouldCancel;

  final SyncStats stats = SyncStats();

  Syncer({
    required this.sources,
    required this.destRoot,
    required this.extensions,
    this.mirror = false,
    this.onProgress,
    this.shouldCancel,
  });

  bool _cancelled() => shouldCancel?.call() ?? false;

  Future<SyncStats> run() async {
    final planned = <_Item>[];
    final usedRelPaths = <String>{};

    for (final src in sources) {
      if (_cancelled()) { stats.cancelled = true; return stats; }
      final srcDir = Directory(src);
      if (!await srcDir.exists()) continue;
      await for (final entity in srcDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          if (extensions.isNotEmpty && !extensions.contains(_extOf(entity.path))) continue;
          var rel = entity.path.length > src.length + 1
              ? entity.path.substring(src.length + 1)
              : entity.uri.pathSegments.last;
          // collision between sources -> prefix with source folder name
          if (usedRelPaths.contains(rel)) {
            final base = src.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;
            rel = '$base/$rel';
            var n = 2;
            while (usedRelPaths.contains(rel)) {
              rel = '$base ($n)/${entity.path.substring(src.length + 1)}';
              n++;
            }
          }
          usedRelPaths.add(rel);
          planned.add(_Item(entity.path, rel, await entity.length()));
        }
      }
    }

    stats.planned = planned.length;
    stats.bytesTotal = planned.fold(0, (a, b) => a + b.size);

    final destSet = <String>{};

    for (final item in planned) {
      if (_cancelled()) { stats.cancelled = true; return stats; }
      destSet.add(item.relPath);
      final dest = File('$destRoot/${item.relPath}');
      stats.currentFile = item.relPath;
      try {
        if (await _isUpToDate(item.srcPath, dest, item.size)) {
          stats.bytesCopied += item.size;
          onProgress?.call(stats);
          continue;
        }
        await dest.parent.create(recursive: true);
        final inStream = File(item.srcPath).openRead();
        final out = dest.openWrite();
        await out.addStream(inStream);
        await out.close();
        // keep mtimes in sync so later runs can skip
        final srcStat = await File(item.srcPath).stat();
        await dest.setLastModified(srcStat.modified);
        stats.copied++;
        stats.bytesCopied += item.size;
      } catch (e) {
        stats.failed++;
      }
      onProgress?.call(stats);
    }

    if (mirror && !_cancelled()) {
      await for (final entity in Directory(destRoot).list(recursive: true, followLinks: false)) {
        if (_cancelled()) { stats.cancelled = true; return stats; }
        if (entity is File) {
          final rel = entity.path.length > destRoot.length + 1
              ? entity.path.substring(destRoot.length + 1)
              : entity.uri.pathSegments.last;
          if (extensions.isNotEmpty && !extensions.contains(_extOf(entity.path))) continue;
          if (!destSet.contains(rel)) {
            try {
              await entity.delete();
              stats.deleted++;
            } catch (_) {
              stats.failed++;
            }
            onProgress?.call(stats);
          }
        }
      }
    }

    stats.currentFile = '';
    onProgress?.call(stats);
    return stats;
  }

  Future<bool> _isUpToDate(String srcPath, File dest, int srcSize) async {
    if (!await dest.exists()) return false;
    final d = await dest.stat();
    if (d.size != srcSize) return false;
    final s = await File(srcPath).stat();
    // FAT/exFAT sticks have 2-second mtime granularity
    return (s.modified.difference(d.modified)).inSeconds.abs() <= 2;
  }

  static String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i).toLowerCase();
  }
}
