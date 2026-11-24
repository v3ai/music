import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../core/library.dart';
import '../../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Big artwork + title header used by albums and playlists.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({super.key, required this.art, required this.kind, required this.title, this.meta, this.description});
  final Widget Function(double size) art;
  final String kind;
  final String title;
  final Widget? meta;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final top = MediaQuery.paddingOf(context).top;
    final content = wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            art(220),
            const SizedBox(width: 24),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: titleXL.copyWith(fontSize: title.length > 30 ? 34 : 52, height: 1.05, letterSpacing: -1.2)),
                if (description != null && description!.isNotEmpty) ...[const SizedBox(height: 10), Text(description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: subtle)],
                if (meta != null) ...[const SizedBox(height: 10), meta!],
              ]),
            ),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: art(MediaQuery.sizeOf(context).width * .62)),
            const SizedBox(height: 20),
            Text(title, style: titleXL.copyWith(fontSize: 24)),
            if (description != null && description!.isNotEmpty) ...[const SizedBox(height: 6), Text(description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: subtle)],
            if (meta != null) ...[const SizedBox(height: 8), meta!],
          ]);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A3A), Color(0xFF121212), C.bg], stops: [0, .75, 1]),
      ),
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, top + (wide ? 56 : 52), wide ? 24 : 16, 16),
      child: content,
    );
  }
}

/// Play / shuffle / save / download / more.
class CollectionActions extends StatelessWidget {
  const CollectionActions({
    super.key,
    required this.tracks,
    required this.context_,
    required this.route,
    this.saved,
    this.onSave,
    this.onMore,
    this.showDownload = true,
  });
  final List<Track> tracks;
  final String context_;
  final String route;
  final bool? saved;
  final VoidCallback? onSave;
  final void Function(Offset?)? onMore;
  final bool showDownload;

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final p = App.player;
      final mine = p.contextRoute == route && p.current != null;
      final lib = App.lib;
      final states = tracks.map((t) => lib.download(t.id)?.status).toList();
      final allDone = tracks.isNotEmpty && states.every((s) => s == DlStatus.done);
      final anyActive = states.any((s) => s == DlStatus.queued || s == DlStatus.downloading);
      final done = states.where((s) => s == DlStatus.done).length;
      return Padding(
        padding: EdgeInsets.fromLTRB(isWide(context) ? 24 : 16, 4, isWide(context) ? 16 : 8, 8),
        child: Row(children: [
          if (saved != null)
            IconBtn(saved! ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                size: 30, color: saved! ? Colors.white : C.sub, tooltip: saved! ? 'Remove from Your Library' : 'Save to Your Library', onTap: onSave),
          if (showDownload && tracks.isNotEmpty)
            anyActive
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(value: tracks.isEmpty ? 0 : done / tracks.length, strokeWidth: 2.5, backgroundColor: C.hover)),
                  )
                : IconBtn(allDone ? Icons.download_for_offline_rounded : Icons.download_for_offline_outlined,
                    size: 30,
                    color: allDone ? Colors.white : C.sub,
                    tooltip: allDone ? 'Remove download' : 'Download',
                    onTap: () async {
                      if (allDone) {
                        if (!await confirm(context, title: 'Remove download?', text: 'You won’t be able to play these songs offline.', ok: 'Remove')) return;
                        for (final t in tracks) {
                          App.downloads.remove(t.id);
                        }
                      } else {
                        App.downloads.add(tracks);
                      }
                    }),
          if (onMore != null) Builder(builder: (bc) => IconBtn(Icons.more_horiz_rounded, size: 28, tooltip: 'More options', onTap: () {
                final box = bc.findRenderObject() as RenderBox?;
                onMore!(box?.localToGlobal(box.size.bottomLeft(Offset.zero)));
              })),
          const Spacer(),
          IconBtn(Icons.shuffle_rounded, size: 26, active: p.shuffle, dot: p.shuffle, tooltip: 'Shuffle', onTap: tracks.isEmpty
              ? null
              : () {
                  if (mine) {
                    p.toggleShuffle();
                  } else {
                    p.playList(tracks, shuffled: true, context: context_, route: route);
                  }
                }),
          const SizedBox(width: 8),
          PlayCircle(
            playing: mine && p.playing,
            onTap: () {
              if (tracks.isEmpty) return;
              if (mine) {
                p.toggle();
              } else {
                p.playList(tracks, shuffled: false, context: context_, route: route);
              }
            },
          ),
        ]),
      );
    });
  }
}

/// A plain list of tracks (as slivers) that plays within [tracks].
class TrackSliver extends StatelessWidget {
  const TrackSliver({super.key, required this.tracks, required this.context_, required this.route, this.numbered = false, this.art = true, this.album = true, this.artist = true, this.playlistId});
  final List<Track> tracks;
  final String context_;
  final String route;
  final bool numbered, art, album, artist;
  final String? playlistId;
  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 16),
      sliver: SliverList.builder(
        itemCount: tracks.length,
        itemBuilder: (_, i) => TrackTile(
          track: tracks[i],
          number: numbered ? i + 1 : null,
          showArt: art,
          showAlbum: album,
          showArtist: artist,
          playlistId: playlistId,
          onPlay: () => App.player.playList(tracks, start: i, shuffled: false, context: context_, route: route),
        ),
      ),
    );
  }
}

/// Scroll view with the back button floating over the header.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.slivers, this.title});
  final List<Widget> slivers;
  final String? title;
  @override
  Widget build(BuildContext context) => Stack(children: [
        CustomScrollView(slivers: [...slivers, const SliverToBoxAdapter(child: SizedBox(height: 32))]),
        Positioned(left: 0, right: 0, top: 0, child: PageTop(title: null)),
      ]);
}
