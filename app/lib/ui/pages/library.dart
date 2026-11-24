import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../core/library.dart';
import '../../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final pad = wide ? 24.0 : 16.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, wide ? 20 : 12, 8, 8),
          child: Row(children: [
            const Expanded(child: Text('Your Library', style: titleXL)),
            IconBtn(Icons.add_rounded, size: 28, tooltip: 'Create playlist', onTap: () => createPlaylistFlow(context)),
            IconBtn(Icons.settings_outlined, tooltip: 'Settings', onTap: Nav.settings),
          ]),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: pad), children: [
          if (_filter != null) Padding(padding: const EdgeInsets.only(right: 8, bottom: 8, top: 4), child: Pill('✕', onTap: () => setState(() => _filter = null))),
          for (final f in const ['Playlists', 'Albums', 'Artists', 'Downloaded'])
            if (_filter == null || _filter == f)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8, top: 4),
                child: Pill(f, selected: _filter == f, onTap: () => setState(() => _filter = _filter == f ? null : f)),
              ),
        ]),
      ),
      Expanded(child: Watch(player: false, builder: (_) => LibraryList(filter: _filter, padding: EdgeInsets.symmetric(horizontal: pad - 8)))),
    ]);
  }
}

Future<void> createPlaylistFlow(BuildContext context) async {
  final name = await promptText(context, title: 'New playlist', hint: 'My playlist #${App.lib.playlists.length + 1}', ok: 'Create');
  if (name == null) return;
  final p = App.lib.createPlaylist(name);
  Nav.local(p.id);
}

/// Liked Songs, Downloads, your playlists and saved albums / artists / playlists.
class LibraryList extends StatelessWidget {
  const LibraryList({super.key, this.filter, this.compact = false, this.padding = EdgeInsets.zero});
  final String? filter;
  final bool compact;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final lib = App.lib;
    final rows = <Widget>[];
    final size = compact ? 48.0 : 64.0;
    final route = ModalRoute.of(context)?.settings.name;
    bool show(String kind) => filter == null || filter == kind;

    if (show('Playlists')) {
      rows.add(_Row(
        art: IconTile(Icons.favorite_rounded, size: size),
        title: 'Liked Songs',
        subtitle: 'Playlist • ${songs(lib.liked.length)}',
        pinned: true,
        onTap: Nav.liked,
      ));
    }
    if (show('Playlists') || show('Downloaded')) {
      final n = lib.downloads.values.where((d) => d.status == DlStatus.done).length;
      final busy = lib.downloads.values.where((d) => d.status == DlStatus.queued || d.status == DlStatus.downloading).length;
      rows.add(_Row(
        art: IconTile(Icons.arrow_downward_rounded, size: size),
        title: 'Downloads',
        subtitle: busy > 0 ? 'Downloading $busy…' : 'On this device • ${songs(n)}',
        pinned: true,
        onTap: Nav.downloads,
      ));
    }
    if (show('Playlists')) {
      for (final p in lib.playlists) {
        rows.add(_Row(
          art: Mosaic(lib.playlistCovers(p), size: size),
          title: p.name,
          subtitle: 'Playlist • ${songs(p.trackIds.length)}',
          onTap: () => Nav.local(p.id),
          selected: route == 'local:${p.id}',
        ));
      }
    }
    for (final s in lib.saved) {
      final kind = switch (s.kind) { 'album' => 'Albums', 'artist' => 'Artists', _ => 'Playlists' };
      if (filter == 'Downloaded' || !show(kind)) continue;
      final i = s.item;
      rows.add(_Row(
        art: Art(i.art, size: size, circle: i is ArtistCard, px: 160),
        title: i.label,
        subtitle: switch (i) {
          AlbumCard a => '${a.type} • ${a.artists.map((x) => x.name).join(', ')}',
          ArtistCard _ => 'Artist',
          PlaylistCard p => 'Playlist${p.author == null ? '' : ' • ${p.author}'}',
          Track _ => '',
        },
        onTap: () => Nav.open(i),
        onLongPress: () => showActions(context, actions: [
          MenuAction(Icons.remove_circle_outline_rounded, 'Remove from Your Library', () => lib.toggleSave(s.kind, i, false)),
        ]),
      ));
    }
    if (filter == 'Downloaded') {
      for (final t in lib.downloadedTracks.take(200)) {
        rows.add(_Row(
          art: TrackArt(t, size: size),
          title: t.title,
          subtitle: 'Song • ${t.artistNames}',
          onTap: () {
            final done = lib.downloadedTracks.where((x) => lib.isDownloaded(x.id)).toList();
            if (lib.isDownloaded(t.id)) App.player.playList(done, start: done.indexOf(t), context: 'Downloads', route: 'downloads');
          },
        ));
      }
    }
    if (!compact && lib.playlists.isEmpty && lib.saved.isEmpty && filter == null) {
      rows.add(const Padding(
        padding: EdgeInsets.fromLTRB(8, 24, 8, 0),
        child: Text('Playlists you create, and albums, artists and playlists you save, will show up here.', style: subtle),
      ));
    }
    return ListView(padding: padding.copyWith(bottom: 24), children: rows);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.art, required this.title, required this.subtitle, required this.onTap, this.onLongPress, this.pinned = false, this.selected = false});
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool pinned;
  final bool selected;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0x1AFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color(0x12FFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              art,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (pinned) const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.push_pin_rounded, size: 13, color: Colors.white)),
                    Expanded(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtle)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      );
}
