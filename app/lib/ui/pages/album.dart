import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key, required this.id, this.preview});
  final String id;
  final AlbumCard? preview;

  @override
  Widget build(BuildContext context) {
    return Loader<Album>(
      load: () => App.ytm.album(id),
      loading: preview == null
          ? null
          : PageScaffold(slivers: [
              SliverToBoxAdapter(
                child: CollectionHeader(
                  art: (s) => Art(preview!.art, size: s, radius: 4, px: 800, shadow: true),
                  kind: preview!.type,
                  title: preview!.title,
                ),
              ),
              const SliverToBoxAdapter(child: Loading()),
            ]),
      builder: (context, a) {
        final route = 'album:${a.id}';
        final albumArtists = a.artists.map((x) => x.name).toSet();
        final mixedArtists = a.tracks.any((t) => !t.artists.every((x) => albumArtists.contains(x.name)));
        return Watch(
          player: false,
          builder: (context) => PageScaffold(slivers: [
            SliverToBoxAdapter(
              child: CollectionHeader(
                art: (s) => Art(a.art, size: s, radius: 4, px: 800, shadow: true),
                kind: a.type,
                title: a.title,
                meta: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  ArtistLinks(a.artists, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: C.text)),
                  Text(
                    [if (a.year != null) a.year!, '${a.tracks.length} song${a.tracks.length == 1 ? '' : 's'}', if (a.duration > 0) fmtLong(a.duration)].map((s) => ' • $s').join(),
                    style: subtle.copyWith(fontSize: 14),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: CollectionActions(
                tracks: a.tracks,
                context_: a.title,
                route: route,
                saved: App.lib.isSaved('album', a.id),
                onSave: () {
                  final on = App.lib.toggleSave('album', a.card);
                  Nav.toast(on ? 'Saved to Your Library' : 'Removed from Your Library');
                },
                onMore: (pos) => showActions(context, position: pos, header: sheetHeader(Art(a.art, size: 48), a.title, a.artists.map((x) => x.name).join(', ')), actions: [
                  MenuAction(Icons.queue_music_rounded, 'Add to queue', () {
                    App.player.addToQueue(a.tracks);
                    Nav.toast('Added to queue');
                  }),
                  MenuAction(Icons.playlist_add_rounded, 'Add to playlist', () => showAddToPlaylist(context, a.tracks)),
                  for (final ar in a.artists.where((x) => x.id != null)) MenuAction(Icons.person_outline_rounded, 'Go to ${ar.name}', () => Nav.artist(ar.id!)),
                ]),
              ),
            ),
            TrackSliver(tracks: a.tracks, context_: a.title, route: route, numbered: true, art: false, album: false, artist: mixedArtists || isWide(context)),
            if (a.otherVersions.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 28), child: ShelfRow(title: 'Other versions', items: a.otherVersions))),
          ]),
        );
      },
    );
  }
}
