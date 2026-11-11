import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'settings.dart';
import 'sync_engine.dart';
import 'usb_detect.dart';

void main() {
  runApp(const MusicSyncApp());
}

class MusicSyncApp extends StatelessWidget {
  const MusicSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Sync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD2001F), // maxell red
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppSettings settings = AppSettings();
  List<UsbDrive> drives = [];
  UsbDrive? selectedDrive;
  bool scanning = true;
  bool running = false;
  bool cancelRequested = false;
  SyncStats stats = SyncStats();
  String lastSummary = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await settings.load();
    await _rescan();
    // preselect the previously used drive if still attached
    if (settings.lastDestPath != null) {
      try {
        selectedDrive = drives.firstWhere((d) => d.mountPath == settings.lastDestPath);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _rescan() async {
    setState(() => scanning = true);
    final found = await UsbDetect.scan();
    if (!mounted) return;
    setState(() {
      drives = found;
      scanning = false;
      if (selectedDrive != null &&
          !drives.any((d) => d.mountPath == selectedDrive!.mountPath)) {
        selectedDrive = null;
      }
    });
  }

  Future<void> _addFolder() async {
    String? path;
    try {
      path = await getDirectoryPath(confirmButtonText: 'Choose folder');
    } catch (_) {
      path = null;
    }
    if (path == null && mounted) {
      path = await _askPathManually();
    }
    final String? newPath = path;
    if (newPath != null && newPath.isNotEmpty && !settings.sources.contains(newPath)) {
      setState(() => settings.sources.add(newPath));
      settings.save();
    }
  }

  Future<String?> _askPathManually() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add source folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/home/you/Music',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    return (result == null || result.isEmpty) ? null : result;
  }

  Future<void> _sync() async {
    if (selectedDrive == null || settings.sources.isEmpty) return;
    settings.lastDestPath = selectedDrive!.mountPath;
    settings.lastDestLabel = selectedDrive!.label;
    settings.save();

    setState(() {
      running = true;
      cancelRequested = false;
      stats = SyncStats();
      lastSummary = '';
    });

    final syncer = Syncer(
      sources: List.of(settings.sources),
      destRoot: selectedDrive!.mountPath,
      extensions: settings.audioOnly
          ? settings.extensions.map((e) => e.toLowerCase()).toSet()
          : <String>{},
      mirror: settings.mirror,
      shouldCancel: () => cancelRequested,
      onProgress: (s) {
        if (mounted) setState(() {});
      },
    );

    final result = await syncer.run();

    if (!mounted) return;
    setState(() {
      running = false;
      lastSummary = result.cancelled
          ? 'Sync cancelled — ${result.copied} copied, ${result.failed} failed'
          : 'Done — ${result.copied} copied, ${result.deleted} deleted, ${result.failed} failed';
    });

    if (settings.ejectAfterSync && selectedDrive != null && !result.cancelled) {
      await UsbDetect.eject(selectedDrive!.device ?? selectedDrive!.mountPath);
      if (mounted) {
        setState(() {
          lastSummary += ' — USB ejected, safe to unplug';
          selectedDrive = null;
        });
        _rescan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSync = !running &&
        !scanning &&
        selectedDrive != null &&
        settings.sources.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.album),
            SizedBox(width: 10),
            Text('Music Sync'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSourcesCard(theme),
          const SizedBox(height: 12),
          _buildDriveCard(theme),
          const SizedBox(height: 12),
          _buildOptionsCard(theme),
          const SizedBox(height: 20),
          if (running) _buildProgress(theme) else _buildSyncButton(canSync, theme),
          if (lastSummary.isNotEmpty && !running) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(
                  lastSummary.startsWith('Done') ? Icons.check_circle : Icons.info,
                  color: lastSummary.startsWith('Done') ? Colors.green : Colors.orange,
                ),
                title: Text(lastSummary),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Native replacement for the Maxell Music Auto Backup tool',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_music, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Source folders', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: running ? null : _addFolder,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add folder',
                ),
              ],
            ),
            if (settings.sources.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No folders yet — add the folder(s) that hold your music.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ...settings.sources.map((s) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder),
                    title: Text(s, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: running
                          ? null
                          : () {
                              setState(() => settings.sources.remove(s));
                              settings.save();
                            },
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.usb, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('USB drive', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  onPressed: running ? null : _rescan,
                  icon: scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: 'Rescan',
                ),
              ],
            ),
            if (drives.isEmpty && !scanning)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No USB drives found. Plug one in and press refresh.'),
              ),
            ...drives.map((d) => RadioListTile<UsbDrive>(
                  dense: true,
                  value: d,
                  groupValue: selectedDrive,
                  onChanged: running
                      ? null
                      : (v) => setState(() => selectedDrive = v),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(d.label, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${d.freeGb} GB free',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  subtitle: Text(d.mountPath),
                  secondary: const Icon(Icons.sd_storage),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard(ThemeData theme) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.audiotrack),
            title: const Text('Music files only'),
            subtitle: Text(settings.extensions.join(' ')),
            value: settings.audioOnly,
            onChanged: running
                ? null
                : (v) {
                    setState(() => settings.audioOnly = v);
                    settings.save();
                  },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.delete_sweep),
            title: const Text('Mirror mode'),
            subtitle: const Text('Delete USB files that are no longer in the source folders'),
            value: settings.mirror,
            onChanged: running
                ? null
                : (v) {
                    setState(() => settings.mirror = v);
                    settings.save();
                  },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.eject),
            title: const Text('Eject when done'),
            value: settings.ejectAfterSync,
            onChanged: running
                ? null
                : (v) {
                    setState(() => settings.ejectAfterSync = v);
                    settings.save();
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton(bool canSync, ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: canSync ? _sync : null,
            icon: const Icon(Icons.sync),
            label: const Text('SYNC TO USB', style: TextStyle(fontSize: 16)),
          ),
        ),
        if (!canSync)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              selectedDrive == null
                  ? (settings.sources.isEmpty
                      ? 'Add a source folder and select a USB drive'
                      : 'Select a USB drive')
                  : 'Add a source folder to start',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: stats.fraction),
        const SizedBox(height: 10),
        Text(
          '${stats.copied}/${stats.planned} files copied  •  ${(stats.fraction * 100).toStringAsFixed(0)}%',
          style: theme.textTheme.titleSmall,
        ),
        if (stats.currentFile.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              stats.currentFile,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => cancelRequested = true,
          icon: const Icon(Icons.cancel),
          label: const Text('Cancel'),
        ),
      ],
    );
  }
}
