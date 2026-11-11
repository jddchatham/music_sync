import 'dart:io';

class UsbDrive {
  final String label;
  final String mountPath;
  final String? device; // e.g. /dev/sdc1, for eject
  final int bytesFree;
  final int bytesTotal;

  UsbDrive({
    required this.label,
    required this.mountPath,
    required this.device,
    required this.bytesFree,
    required this.bytesTotal,
  });

  String get freeGb => (bytesFree / 1073741824).toStringAsFixed(1);

  @override
  String toString() => '$label ($mountPath)';
}

/// Linux drive detection: scan the standard removable-media mount points.
class UsbDetect {
  static Future<List<UsbDrive>> scan() async {
    final user = Platform.environment['USER'] ?? '';
    final roots = <String>[
      '/run/media/$user',
      '/media/$user',
      '/media',
    ];
    final found = <UsbDrive>[];
    final seen = <String>{};
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final mount = entity.path;
          if (seen.contains(mount)) continue;
          // skip the user's home-like mounts and the usb's own system dirs
          if (mount.startsWith('/media/$user') && mount == '/media/$user') continue;
          seen.add(mount);
          final info = await _df(mount);
          if (info == null) continue;
          final label = mount.split('/').last;
          found.add(UsbDrive(
            label: label,
            mountPath: mount,
            device: info.$1,
            bytesFree: info.$3,
            bytesTotal: info.$2,
          ));
        }
      }
    }
    found.sort((a, b) => a.mountPath.compareTo(b.mountPath));
    return found;
  }

  /// returns (device, bytesTotal, bytesFree) or null on failure
  static Future<(String?, int, int)?> _df(String path) async {
    try {
      final r = await Process.run('df', ['-B1', '--output=source,size,avail', path]);
      if (r.exitCode != 0) return null;
      final lines = (r.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      final cols = lines[1].trim().split(RegExp(r'\s+'));
      if (cols.length < 3) return null;
      final dev = cols[0].startsWith('/dev/') ? cols[0] : null;
      return (dev, int.tryParse(cols[1]) ?? 0, int.tryParse(cols[2]) ?? 0);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> eject(String deviceOrMount) async {
    try {
      final r = await Process.run('udisksctl', ['unmount', '-b', deviceOrMount]);
      if (r.exitCode == 0) {
        final dev = deviceOrMount.replaceAll(RegExp(r'\d+$'), '');
        await Process.run('udisksctl', ['power-off', '-b', dev]);
        return true;
      }
      // fall back: maybe it is a mount path
      final r2 = await Process.run('udisksctl', ['unmount', '-p', deviceOrMount]);
      return r2.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
