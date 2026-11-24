import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../core/images.dart';
import '../../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key, required this.id, this.preview});
  final String id;
  final ArtistCard? preview;

  @override
  Widget build(BuildContext context) => Loader<Artist>(
        load: () => App.ytm.artist(id),
        loading: preview == null ? null : PageScaffold(slivers: [SliverToBoxAdapter(child: _Hero(name: preview!.name, art: preview!.art)), const SliverToBoxAdapter(child: Loading())]),
        builder: (context, a) => _ArtistBody(a),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, this.art, this.listeners});
  final String name;
  final String? art;
  final String? listeners;
  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final h = wide ? 340.0 : MediaQuery.sizeOf(context).width * .9;
    // ask for a big, wide crop of the artist banner
    final url = art?.replaceFirst(RegExp(r'=[ws]\d+[^/=]*$'), '=w1440-h600-p-l90-rj');
    return SizedBox(
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        if (url != null) Image(image: NetArt(url), fit: BoxFit.cover, alignment: const Alignment(0, -.4), errorBuilder: (_, _, _) => const ColoredBox(color: C.raised)) else const ColoredBox(color: C.raised),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0xCC000000), C.bg], stops: [0, .35, .85, 1]),
          ),
        ),
        Positioned(
          left: wide ? 24 : 16,
          right: 16,
          bottom: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleXL.copyWith(fontSize: wide ? (name.length > 18 ? 56 : 80) : 40, letterSpacing: -2, height: 1)),
            if (listeners != null) ...[const SizedBox(height: 10), Text(listeners!, style: const TextStyle(fontSize: 14, color: C.text))],
          ]),
        ),
      ]),
    );
  }
}

class _ArtistBody extends StatefulWidget {
  const _ArtistBody(this.a);
  final Artist a;
  @override
  State<_ArtistBody> createState() => _ArtistBodyState();
}

class _ArtistBodyState extends State<_ArtistBody> {
  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final route = 'artist:${a.id}';
    final wide = isWide(context);
    return Watch(
      player: false,
      builder: (context) => PageScaffold(slivers: [
        SliverToBoxAdapter(child: _Hero(name: a.name, art: a.art, listeners: a.listeners)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CollectionActions(
              tracks: a.songs,
              context_: a.name,
              route: route,
              showDownload: false,
              saved: App.lib.isSaved('artist', a.id),
              onSave: () {
                final on = App.lib.toggleSave('artist', a.card);
                Nav.toast(on ? 'Following ${a.name}' : 'Unfollowed ${a.name}');
              },
              onMore: (pos) => showActions(context, position: pos, header: sheetHeader(Art(a.art, size: 48, circle: true), a.name, 'Artist'), actions: [
                if (a.songs.isNotEmpty) MenuAction(Icons.sensors_rounded, 'Go to artist radio', () => App.player.startRadio(a.songs.first)),
                if (a.songsPlaylistId != null) MenuAction(Icons.library_music_outlined, 'All songs', () => Nav.playlist(a.songsPlaylistId!)),
              ]),
            ),
          ),
        ),
        if (a.songs.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle('Popular', onMore: a.songsPlaylistId == null ? null : () => Nav.playlist(a.songsPlaylistId!))),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 16),
            sliver: SliverList.builder(
              itemCount: a.songs.length,
              itemBuilder: (_, i) => TrackTile(
                track: a.songs[i],
                number: i + 1,
                showArtist: a.songs[i].artists.length > 1,
                showAlbum: true,
                onPlay: () => App.player.playList(a.songs, start: i, shuffled: false, context: a.name, route: route),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        if (a.albums.isNotEmpty) SliverToBoxAdapter(child: ShelfRow(title: 'Albums', items: a.albums)),
        if (a.singles.isNotEmpty) SliverToBoxAdapter(child: ShelfRow(title: 'Singles and EPs', items: a.singles)),
        if (a.videos.isNotEmpty) SliverToBoxAdapter(child: ShelfRow(title: 'Videos', items: a.videos)),
        for (final s in a.more) SliverToBoxAdapter(child: ShelfRow(title: s.title, items: s.items)),
        if (a.related.isNotEmpty) SliverToBoxAdapter(child: ShelfRow(title: 'Fans also like', items: a.related)),
        if (a.description != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 8, wide ? 24 : 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('About', style: titleL),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _Expandable(a.description!),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable(this.text);
  final String text;
  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.text, maxLines: _open ? null : 4, overflow: _open ? null : TextOverflow.ellipsis, style: const TextStyle(color: C.sub, fontSize: 14.5, height: 1.5)),
          const SizedBox(height: 6),
          Text(_open ? 'Show less' : 'Show more', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}
