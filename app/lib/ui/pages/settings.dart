import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../core/images.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<int> _artSize = NetArt.cacheSize();

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Watch(
      builder: (context) {
        final lib = App.lib;
        final dlSize = lib.downloads.values.fold<int>(0, (s, d) => s + (d.size ?? 0));
        return ListView(padding: EdgeInsets.fromLTRB(wide ? 16 : 4, 0, wide ? 16 : 4, 32), children: [
          const PageTop(),
          Padding(padding: EdgeInsets.fromLTRB(wide ? 8 : 12, 8, 12, 16), child: const Text('Settings', style: titleXL)),
          const _Header('Playback'),
          SwitchListTile(
            value: App.player.autoplay,
            onChanged: (v) => App.player.autoplay = v,
            title: const Text('Autoplay', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('When your music ends, keep playing similar songs.', style: subtle),
          ),
          const _Header('Storage'),
          ListTile(
            title: const Text('Downloads', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${songs(lib.downloads.length)} • ${fmtBytes(dlSize)}', style: subtle),
            trailing: const Icon(Icons.chevron_right_rounded, color: C.sub),
            onTap: Nav.downloads,
          ),
          FutureBuilder<int>(
            future: _artSize,
            builder: (_, s) => ListTile(
              title: const Text('Artwork cache', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(s.hasData ? fmtBytes(s.data!) : '…', style: subtle),
              trailing: TextButton(
                onPressed: () async {
                  await NetArt.clear();
                  setState(() => _artSize = NetArt.cacheSize());
                  Nav.toast('Cache cleared');
                },
                child: const Text('Clear', style: TextStyle(color: C.text, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          ListTile(
            title: const Text('Clear recent searches', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              lib.clearSearches();
              Nav.toast('Recent searches cleared');
            },
          ),
          const _Header('About'),
          const ListTile(
            title: Text('music', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Ad-free. Plays from YouTube Music on this device, with no account or server.', style: subtle),
          ),
        ]);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: titleM),
      );
}
