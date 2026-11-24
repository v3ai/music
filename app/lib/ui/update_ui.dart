import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import '../core/updater.dart';
import 'theme.dart';

String _status(Updater u) => switch (u.state) {
  UpdateState.checking => 'Checking for updates…',
  UpdateState.upToDate => 'You have the latest version.',
  UpdateState.available => 'Version ${u.latest} is available.',
  UpdateState.downloading => 'Downloading ${u.latest}… ${(u.progress * 100).round()}%',
  UpdateState.ready => switch (u.kind) {
    UpdateKind.android => 'Version ${u.latest} is ready to install.',
    _ => 'Version ${u.latest} is ready. Restart music to finish updating.',
  },
  UpdateState.installing => 'Installing ${u.latest}…',
  UpdateState.failed => u.error ?? 'Something went wrong.',
  UpdateState.idle => '',
};

/// Shown at the top of Home while there's an update to get.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.pad});
  final double pad;
  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  String? _dismissed; // version the user closed the banner for

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: App.updater,
    builder: (c, _) {
      final u = App.updater;
      final show = u.hasUpdate || (u.state == UpdateState.failed && u.latest != null && Updater.newer(u.latest!, u.current));
      if (!show || _dismissed == u.latest) return const SizedBox.shrink();
      final busy = u.state == UpdateState.downloading || u.state == UpdateState.installing;
      return Padding(
        padding: EdgeInsets.fromLTRB(widget.pad, 0, widget.pad, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(color: const Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt_rounded, color: C.text, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Update to music ${u.latest}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(_status(u), style: subtle),
                    if (u.state == UpdateState.downloading) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: u.progress, minHeight: 3, color: C.text, backgroundColor: const Color(0x33FFFFFF)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!busy)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, visualDensity: VisualDensity.compact),
                  onPressed: u.run,
                  child: Text(u.state == UpdateState.failed ? 'Try again' : u.action, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              IconButton(
                tooltip: 'Later',
                icon: const Icon(Icons.close_rounded, size: 20, color: C.sub),
                onPressed: () => setState(() => _dismissed = u.latest),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The Updates section in Settings.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: App.updater,
    builder: (c, _) {
      final u = App.updater;
      final status = _status(u);
      final busy = u.state == UpdateState.checking || u.state == UpdateState.downloading || u.state == UpdateState.installing;
      return Column(
        children: [
          SwitchListTile(
            value: u.auto,
            onChanged: (v) => u.auto = v,
            title: const Text('Update automatically', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(switch (u.kind) {
              UpdateKind.android => 'Check for new versions and offer to install them.',
              UpdateKind.apt => 'Check for new versions. Updates also come with apt upgrade.',
              UpdateKind.manual => 'Check for new versions.',
              _ => 'Download new versions in the background, ready for your next restart.',
            }, style: subtle),
          ),
          ListTile(
            title: Text('Version ${u.current.isEmpty ? '…' : u.current}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: status.isEmpty ? null : Text(status, style: subtle),
            trailing: TextButton(
              onPressed: busy
                  ? null
                  : (u.hasUpdate || (u.state == UpdateState.failed && u.latest != null && Updater.newer(u.latest!, u.current)) ? u.run : () => u.check()),
              child: Text(
                u.hasUpdate ? u.action : 'Check now',
                style: TextStyle(color: busy ? C.sub : C.text, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    },
  );
}
