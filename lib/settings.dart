import 'dart:convert';
import 'dart:io';

class AppSettings {
  List<String> sources = [];
  bool audioOnly = true;
  List<String> extensions = const [
    '.mp3', '.flac', '.wav', '.ogg', '.m4a', '.aac', '.wma', '.opus', '.aiff',
  ];
  bool mirror = false;
  bool ejectAfterSync = false;
  String? lastDestPath;
  String? lastDestLabel;

  static File get _file {
    final xdg = Platform.environment['XDG_CONFIG_HOME'] ?? '${Platform.environment['HOME']}/.config';
    return File('$xdg/music_sync/config.json');
  }

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final j = jsonDecode(await _file.readAsString());
        sources = (j['sources'] as List?)?.cast<String>() ?? [];
        audioOnly = j['audioOnly'] ?? true;
        extensions = (j['extensions'] as List?)?.cast<String>() ?? extensions;
        mirror = j['mirror'] ?? false;
        ejectAfterSync = j['ejectAfterSync'] ?? false;
        lastDestPath = j['lastDestPath'];
        lastDestLabel = j['lastDestLabel'];
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      await _file.create(recursive: true);
      await _file.writeAsString(jsonEncode({
        'sources': sources,
        'audioOnly': audioOnly,
        'extensions': extensions,
        'mirror': mirror,
        'ejectAfterSync': ejectAfterSync,
        'lastDestPath': lastDestPath,
        'lastDestLabel': lastDestLabel,
      }));
    } catch (_) {}
  }
}
