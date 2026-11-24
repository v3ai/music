import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Shelf>> _feed = App.ytm.home();

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 5 ? 'Good evening' : (h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening'));
  }

  Future<void> _refresh() async {
    setState(() => _feed = App.ytm.home());
    await _feed.catchError((_) => <Shelf>[]);
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final pad = wide ? 24.0 : 16.0;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.black,
      backgroundColor: Colors.white,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, wide ? 24 : 16, pad / 2, 12),
              child: Row(children: [
                Expanded(child: Text(_greeting, style: titleXL.copyWith(fontSize: wide ? 32 : 26))),
                if (!wide) IconBtn(Icons.settings_outlined, tooltip: 'Settings', onTap: Nav.settings),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(child: Watch(player: false, builder: (_) => _Quick(pad: pad))),
        FutureBuilder<List<Shelf>>(
          future: _feed,
          builder: (c, s) {
            if (s.hasError) {
              final local = App.lib.downloadedTracks.where((t) => App.lib.isDownloaded(t.id)).toList();
              return SliverToBoxAdapter(
                child: local.isEmpty
                    ? ErrorMessage(onRetry: _refresh)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
                          child: const Text('You’re offline. Your downloads still play.', style: subtle),
                        ),
                        SectionTitle('Downloads', onMore: Nav.downloads),
                        for (var i = 0; i < local.length && i < 20; i++)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 16),
                            child: TrackTile(track: local[i], onPlay: () => App.player.playList(local, start: i, context: 'Downloads', route: 'downloads')),
                          ),
                      ]),
              );
            }
            if (!s.hasData) return const SliverToBoxAdapter(child: Loading());
            final shelves = s.data!;
            return SliverList.builder(
              itemCount: shelves.length,
              itemBuilder: (_, i) => ShelfRow(title: shelves[i].title, items: shelves[i].items),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

/// Grid of shortcuts: Liked Songs, recent playlists/albums and recently played.
class _Quick extends StatelessWidget {
  const _Quick({required this.pad});
  final double pad;

  @override
  Widget build(BuildContext context) {
    final lib = App.lib;
    final tiles = <Widget>[];
    if (lib.liked.isNotEmpty) {
      tiles.add(_QuickTile(art: const IconTile(Icons.favorite_rounded, size: 56, radius: 0), title: 'Liked Songs', onTap: Nav.liked));
    }
    for (final p in lib.playlists.take(3)) {
      tiles.add(_QuickTile(art: Mosaic(lib.playlistCovers(p), size: 56, radius: 0), title: p.name, onTap: () => Nav.local(p.id)));
    }
    for (final s in lib.saved.take(8 - tiles.length)) {
      tiles.add(_QuickTile(art: Art(s.item.art, size: 56, radius: 0, circle: false), title: s.item.label, onTap: () => Nav.open(s.item)));
    }
    final recent = lib.recentTracks(12);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (tiles.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 20),
          child: LayoutBuilder(builder: (c, box) {
            final cols = box.maxWidth > 900 ? 4 : 2;
            const gap = 8.0;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles.take(8)) SizedBox(width: w, child: t)]);
          }),
        ),
      if (recent.isNotEmpty) ShelfRow(title: 'Recently played', items: recent),
    ]);
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.art, required this.title, required this.onTap});
  final Widget art;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0x14FFFFFF),
          child: Row(children: [
            SizedBox(width: 56, height: 56, child: art),
            const SizedBox(width: 10),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
            const SizedBox(width: 8),
          ]),
        ),
      );
}
