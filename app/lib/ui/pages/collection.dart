import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../core/library.dart';
import '../../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Where a list of songs comes from.
sealed class CollectionSource {
  const CollectionSource();
  const factory CollectionSource.remote(String id, [PlaylistCard? preview]) = RemoteSource;
  const factory CollectionSource.local(String id) = LocalSource;
  const factory CollectionSource.liked() = LikedSource;
  const factory CollectionSource.downloads() = DownloadsSource;
}

class RemoteSource extends CollectionSource {
  const RemoteSource(this.id, [this.preview]);
  final String id;
  final PlaylistCard? preview;
}

class LocalSource extends CollectionSource {
  const LocalSource(this.id);
  final String id;
}

class LikedSource extends CollectionSource {
  const LikedSource();
}

class DownloadsSource extends CollectionSource {
  const DownloadsSource();
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.source});
  final CollectionSource source;

  @override
  Widget build(BuildContext context) => switch (source) {
        RemoteSource s => Loader<Playlist>(
            load: () => App.ytm.playlist(s.id),
            loading: s.preview == null
                ? null
                : PageScaffold(slivers: [
                    SliverToBoxAdapter(child: CollectionHeader(art: (z) => Art(s.preview!.art, size: z, px: 800, shadow: true), kind: 'Playlist', title: s.preview!.title)),
                    const SliverToBoxAdapter(child: Loading()),
                  ]),
            builder: (c, p) => _Remote(p),
          ),
        LocalSource s => Watch(player: false, builder: (_) => _Local(s.id)),
        LikedSource _ => Watch(player: false, builder: (_) => const _Liked()),
        DownloadsSource _ => Watch(player: false, builder: (_) => const _Downloads()),
      };
}

String _count(List<Track> ts) {
  final secs = ts.fold<int>(0, (s, t) => s + (t.duration ?? 0));
  return '${ts.length} song${ts.length == 1 ? '' : 's'}${secs > 0 ? ', ${fmtLong(secs)}' : ''}';
}

class _Remote extends StatelessWidget {
  const _Remote(this.p);
  final Playlist p;
  @override
  Widget build(BuildContext context) {
    final route = 'playlist:${p.id}';
    return Watch(
      player: false,
      builder: (context) => PageScaffold(slivers: [
        SliverToBoxAdapter(
          child: CollectionHeader(
            art: (s) => Art(p.art, size: s, px: 800, shadow: true),
            kind: 'Playlist',
            title: p.title,
            description: p.description,
            meta: Text([if (p.author != null) p.author!, _count(p.tracks)].join(' • '), style: subtle.copyWith(fontSize: 14)),
          ),
        ),
        SliverToBoxAdapter(
          child: CollectionActions(
            tracks: p.tracks,
            context_: p.title,
            route: route,
            saved: App.lib.isSaved('playlist', p.id),
            onSave: () {
              final on = App.lib.toggleSave('playlist', PlaylistCard(id: p.id, title: p.title, author: p.author, art: p.art));
              Nav.toast(on ? 'Saved to Your Library' : 'Removed from Your Library');
            },
            onMore: (pos) => showActions(context, position: pos, actions: [
              MenuAction(Icons.queue_music_rounded, 'Add to queue', () {
                App.player.addToQueue(p.tracks);
                Nav.toast('Added to queue');
              }),
              MenuAction(Icons.playlist_add_rounded, 'Add to playlist', () => showAddToPlaylist(context, p.tracks)),
              MenuAction(Icons.copy_rounded, 'Copy to Your Library', () {
                final l = App.lib.createPlaylist(p.title, p.tracks);
                Nav.toast('Created “${l.name}”');
              }),
            ]),
          ),
        ),
        if (p.tracks.isEmpty) const SliverToBoxAdapter(child: Message(icon: Icons.queue_music_rounded, title: 'This playlist is empty')),
        TrackSliver(tracks: p.tracks, context_: p.title, route: route, album: true),
      ]),
    );
  }
}

class _Local extends StatelessWidget {
  const _Local(this.id);
  final String id;
  @override
  Widget build(BuildContext context) {
    final lib = App.lib;
    final p = lib.playlist(id);
    if (p == null) return const PageScaffold(slivers: [SliverToBoxAdapter(child: Message(icon: Icons.delete_outline_rounded, title: 'This playlist was deleted'))]);
    final tracks = lib.tracksFor(p.trackIds);
    final route = 'local:$id';
    return PageScaffold(slivers: [
      SliverToBoxAdapter(
        child: CollectionHeader(
          art: (s) => Mosaic(lib.playlistCovers(p), size: s),
          kind: 'Playlist',
          title: p.name,
          description: p.description,
          meta: Text(_count(tracks), style: subtle.copyWith(fontSize: 14)),
        ),
      ),
      SliverToBoxAdapter(
        child: CollectionActions(
          tracks: tracks,
          context_: p.name,
          route: route,
          onMore: (pos) => showActions(context, position: pos, actions: [
            MenuAction(Icons.edit_outlined, 'Rename', () async {
              final n = await promptText(context, title: 'Rename playlist', initial: p.name);
              if (n != null) lib.renamePlaylist(p.id, n);
            }),
            MenuAction(Icons.notes_rounded, 'Edit description', () async {
              final d = await promptText(context, title: 'Description', initial: p.description, hint: 'Add an optional description');
              if (d != null) lib.renamePlaylist(p.id, p.name, d);
            }),
            if (tracks.isNotEmpty)
              MenuAction(Icons.queue_music_rounded, 'Add to queue', () {
                App.player.addToQueue(tracks);
                Nav.toast('Added to queue');
              }),
            MenuAction(Icons.delete_outline_rounded, 'Delete playlist', () async {
              if (await confirm(context, title: 'Delete “${p.name}”?', text: 'This can’t be undone.')) {
                lib.deletePlaylist(p.id);
                if (context.mounted) Navigator.of(context).maybePop();
                Nav.toast('Playlist deleted');
              }
            }),
          ]),
        ),
      ),
      if (tracks.isEmpty)
        SliverToBoxAdapter(
          child: Message(
            icon: Icons.queue_music_rounded,
            title: 'Let’s find something for your playlist',
            text: 'Use “Add to playlist” on any song.',
            action: 'Search',
            onAction: () => Nav.switchTab('search'),
          ),
        )
      else if (isWide(context))
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverReorderableList(
            itemCount: tracks.length,
            onReorderItem: (a, b) => lib.reorderPlaylist(p.id, a, b),
            itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
              key: ValueKey(tracks[i].id),
              index: i,
              child: TrackTile(
                track: tracks[i],
                number: i + 1,
                showAlbum: true,
                playlistId: p.id,
                onPlay: () => App.player.playList(tracks, start: i, shuffled: false, context: p.name, route: route),
              ),
            ),
          ),
        )
      else
        TrackSliver(tracks: tracks, context_: p.name, route: route, playlistId: p.id),
    ]);
  }
}

class _Liked extends StatelessWidget {
  const _Liked();
  @override
  Widget build(BuildContext context) {
    final tracks = App.lib.likedTracks;
    return PageScaffold(slivers: [
      SliverToBoxAdapter(
        child: CollectionHeader(
          art: (s) => IconTile(Icons.favorite_rounded, size: s),
          kind: 'Playlist',
          title: 'Liked Songs',
          meta: Text(_count(tracks), style: subtle.copyWith(fontSize: 14)),
        ),
      ),
      SliverToBoxAdapter(child: CollectionActions(tracks: tracks, context_: 'Liked Songs', route: 'liked')),
      if (tracks.isEmpty)
        const SliverToBoxAdapter(child: Message(icon: Icons.favorite_border_rounded, title: 'Songs you like will appear here', text: 'Save songs by tapping the heart.')),
      TrackSliver(tracks: tracks, context_: 'Liked Songs', route: 'liked'),
    ]);
  }
}

class _Downloads extends StatelessWidget {
  const _Downloads();
  @override
  Widget build(BuildContext context) {
    final lib = App.lib;
    final tracks = lib.downloadedTracks;
    final done = tracks.where((t) => lib.isDownloaded(t.id)).toList();
    final size = lib.downloads.values.fold<int>(0, (s, d) => s + (d.size ?? 0));
    final failed = lib.downloads.entries.where((e) => e.value.status == DlStatus.error).map((e) => e.key).toList();
    return PageScaffold(slivers: [
      SliverToBoxAdapter(
        child: CollectionHeader(
          art: (s) => IconTile(Icons.arrow_downward_rounded, size: s),
          kind: 'On this device',
          title: 'Downloads',
          meta: Text('${done.length} song${done.length == 1 ? '' : 's'} • ${fmtBytes(size)}', style: subtle.copyWith(fontSize: 14)),
        ),
      ),
      SliverToBoxAdapter(
        child: CollectionActions(
          tracks: done,
          context_: 'Downloads',
          route: 'downloads',
          showDownload: false,
          onMore: failed.isEmpty
              ? null
              : (pos) => showActions(context, position: pos, actions: [
                    MenuAction(Icons.refresh_rounded, 'Retry failed downloads', () => App.downloads.add(lib.tracksFor(failed))),
                  ]),
        ),
      ),
      if (tracks.isEmpty)
        const SliverToBoxAdapter(
          child: Message(icon: Icons.download_for_offline_outlined, title: 'No downloads yet', text: 'Download songs, albums and playlists to play them without a connection.'),
        ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: isWide(context) ? 12 : 16),
        sliver: SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (_, i) {
            final t = tracks[i];
            return TrackTile(
              track: t,
              showAlbum: true,
              onPlay: () {
                if (!lib.isDownloaded(t.id)) return;
                App.player.playList(done, start: done.indexOf(t), shuffled: false, context: 'Downloads', route: 'downloads');
              },
            );
          },
        ),
      ),
    ]);
  }
}
