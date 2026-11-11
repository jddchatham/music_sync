/// Filesystem abstraction under the sync engine.
///
/// Every path ([relPath]) is relative to the filesystem's root and uses
/// '/' separators. Implementations: [IoFileSystem] (desktop, dart:io) and
/// SafFileSystem (Android, Storage Access Framework — see saf_fs.dart).
class FsEntry {
  final String relPath;
  final bool isFile;
  final int size;
  final DateTime? modified;

  /// Backend-specific identity of this entry. IO impl: absolute path.
  /// SAF impl: content:// uri. Used by read/delete to skip re-resolution.
  final String uri;

  FsEntry({
    required this.relPath,
    required this.isFile,
    required this.size,
    this.modified,
    required this.uri,
  });
}

abstract class SyncFs {
  /// Short display name of the root (folder name / drive name), used to
  /// disambiguate relative-path collisions between sources.
  String get rootName;

  /// All entries under the root, recursively. Must be called before
  /// [create]/[delete] so the implementation can resolve parents.
  Stream<FsEntry> walk();

  Stream<List<int>> read(FsEntry entry);

  /// Create or overwrite [relPath], creating parent directories as needed.
  Future<SyncWriter> create(String relPath);

  Future<void> delete(FsEntry entry);

  /// Best-effort mtime preservation. No-op where unsupported (SAF).
  Future<void> setModified(String relPath, DateTime when);
}

abstract class SyncWriter {
  Future<void> write(List<int> chunk);
  Future<void> close();
}
