import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/app.dart';
import '../../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  static final focus = FocusNode();
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  Future<SearchResults>? _results;
  List<String> _suggestions = [];
  String _filter = 'All';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _q = '';
        _results = null;
        _suggestions = [];
      });
      return;
    }
    App.ytm.suggestions(q).then((s) {
      if (mounted && _ctl.text.trim() == q) setState(() => _suggestions = s);
    }).ignore();
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(q, remember: false));
  }

  void _search(String q, {bool remember = true}) {
    q = q.trim();
    if (q.isEmpty) return;
    if (remember) App.lib.addSearch(q);
    if (q == _q && _results != null) return;
    setState(() {
      _q = q;
      _filter = 'All';
      _results = App.ytm.search(q);
    });
  }

  void _use(String q) {
    _ctl.text = q;
    _ctl.selection = TextSelection.collapsed(offset: q.length);
    _search(q);
    SearchPage.focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final pad = wide ? 24.0 : 16.0;
    return Column(children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, wide ? 20 : 12, pad, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!wide) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Search', style: titleXL)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: TextField(
                controller: _ctl,
                focusNode: SearchPage.focus,
                onChanged: _changed,
                onSubmitted: (v) => _search(v),
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.black, fontSize: 15.5, fontWeight: FontWeight.w500),
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  hintText: 'What do you want to listen to?',
                  hintStyle: const TextStyle(color: Color(0xFF6A6A6A)),
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.black),
                  suffixIcon: _ctl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.black),
                          onPressed: () {
                            _ctl.clear();
                            _changed('');
                          },
                        ),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                ),
              ),
            ),
          ]),
        ),
      ),
      Expanded(child: _body(pad)),
    ]);
  }

  Widget _body(double pad) {
    if (_results == null) {
      if (_ctl.text.trim().isNotEmpty && _suggestions.isNotEmpty) return _suggestionList(pad);
      return _recent(pad);
    }
    return FutureBuilder<SearchResults>(
      future: _results,
      builder: (c, s) {
        if (s.hasError) return ErrorMessage(onRetry: () => setState(() => _results = App.ytm.search(_q)));
        if (!s.hasData) return const Loading();
        final r = s.data!;
        if (r.isEmpty) return Message(icon: Icons.search_off_rounded, title: 'No results for “$_q”', text: 'Check the spelling, or try different words.');
        return _resultsView(r, pad);
      },
    );
  }

  Widget _suggestionList(double pad) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad - 8),
        children: [
          for (final s in _suggestions)
            ListTile(
              leading: const Icon(Icons.search_rounded, color: C.sub),
              title: Text(s),
              onTap: () => _use(s),
              trailing: IconButton(
                icon: const Icon(Icons.north_west_rounded, size: 18, color: C.sub),
                onPressed: () {
                  _ctl.text = '$s ';
                  _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
                  _changed(_ctl.text);
                },
              ),
            ),
        ],
      );

  Widget _recent(double pad) => Watch(
        player: false,
        builder: (_) {
          final rs = App.lib.recentSearches;
          if (rs.isEmpty) {
            return const Message(icon: Icons.search_rounded, title: 'Play what you love', text: 'Search for artists, songs, albums and playlists.');
          }
          return ListView(padding: EdgeInsets.symmetric(horizontal: pad - 8), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
              child: Row(children: [
                const Expanded(child: Text('Recent searches', style: titleM)),
                TextButton(onPressed: App.lib.clearSearches, child: const Text('Clear', style: TextStyle(color: C.sub))),
              ]),
            ),
            for (final q in rs)
              ListTile(
                leading: const Icon(Icons.history_rounded, color: C.sub),
                title: Text(q),
                onTap: () => _use(q),
                trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: C.sub), onPressed: () => App.lib.removeSearch(q)),
              ),
          ]);
        },
      );

  Widget _resultsView(SearchResults r, double pad) {
    final wide = isWide(context);
    final filters = [
      'All',
      if (r.songs.isNotEmpty) 'Songs',
      if (r.artists.isNotEmpty || r.top is ArtistCard) 'Artists',
      if (r.albums.isNotEmpty) 'Albums',
      if (r.playlists.isNotEmpty) 'Playlists',
      if (r.videos.isNotEmpty) 'Videos',
    ];
    void playSongs(int i) {
      App.lib.addSearch(_q);
      App.player.playList(r.songs, start: i, context: '“$_q” in Search', route: 'search');
    }

    final chips = SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: pad), children: [
        for (final f in filters) Padding(padding: const EdgeInsets.only(right: 8, top: 4, bottom: 8), child: Pill(f, selected: _filter == f, onTap: () => setState(() => _filter = f))),
      ]),
    );

    Widget songsList(List<Track> songs, {int max = 1 << 30, bool art = true}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? pad - 12 : pad),
          child: Column(children: [
            for (var i = 0; i < songs.length && i < max; i++) TrackTile(track: songs[i], onPlay: () => playSongs(r.songs.indexOf(songs[i]).clamp(0, 1 << 30)), showAlbum: wide),
          ]),
        );

    Widget grid(List<Item> items) => Padding(
          padding: EdgeInsets.symmetric(horizontal: pad - 6),
          child: LayoutBuilder(builder: (c, box) {
            final cols = (box.maxWidth / (wide ? 196 : 170)).floor().clamp(2, 8);
            final w = box.maxWidth / cols;
            return Wrap(children: [for (final i in items) ItemCard(i, width: w)]);
          }),
        );

    final List<Widget> children;
    switch (_filter) {
      case 'Songs':
        children = [songsList(r.songs)];
      case 'Artists':
        children = [grid([if (r.top is ArtistCard) r.top!, ...r.artists])];
      case 'Albums':
        children = [grid(r.albums)];
      case 'Playlists':
        children = [grid(r.playlists)];
      case 'Videos':
        children = [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? pad - 12 : pad),
            child: Column(children: [for (final v in r.videos) TrackTile(track: v, onPlay: () => App.player.playTrack(v, context: '“$_q” in Search'))]),
          )
        ];
      default:
        final top = r.top;
        final topWidget = top == null ? null : _TopResult(top, onPlay: () => top is Track ? App.player.playTrack(top) : playItem(top));
        final songsTitle = SectionTitle('Songs', onMore: r.songs.length > 4 ? () => setState(() => _filter = 'Songs') : null);
        children = [
          if (wide && topWidget != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    flex: 4,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionTitle('Top result', padding: EdgeInsets.fromLTRB(0, 8, 0, 10)),
                      Expanded(child: topWidget),
                    ]),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 6,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SectionTitle('Songs', padding: const EdgeInsets.fromLTRB(0, 8, 0, 10), onMore: r.songs.length > 4 ? () => setState(() => _filter = 'Songs') : null),
                      for (var i = 0; i < r.songs.length && i < 4; i++) TrackTile(track: r.songs[i], onPlay: () => playSongs(i)),
                    ]),
                  ),
                ]),
              ),
            )
          else ...[
            if (topWidget != null) ...[const SectionTitle('Top result'), Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: topWidget)],
            if (r.songs.isNotEmpty) ...[const SizedBox(height: 16), songsTitle, songsList(r.songs, max: 5)],
          ],
          const SizedBox(height: 20),
          if (r.artists.isNotEmpty) ShelfRow(title: 'Artists', items: r.artists),
          if (r.albums.isNotEmpty) ShelfRow(title: 'Albums', items: r.albums),
          if (r.playlists.isNotEmpty) ShelfRow(title: 'Playlists', items: r.playlists),
          if (r.videos.isNotEmpty) ShelfRow(title: 'Videos', items: r.videos),
        ];
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [chips, ...children]);
  }
}

class _TopResult extends StatelessWidget {
  const _TopResult(this.item, {required this.onPlay});
  final Item item;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) {
    final i = item;
    final kind = switch (i) {
      ArtistCard _ => 'Artist',
      AlbumCard a => a.type,
      PlaylistCard _ => 'Playlist',
      Track t => t.isVideo ? 'Video' : 'Song',
    };
    final who = switch (i) {
      AlbumCard a => a.artists.map((x) => x.name).join(', '),
      PlaylistCard p => p.author ?? '',
      Track t => t.artistNames,
      _ => '',
    };
    return Material(
      color: const Color(0xFF181818),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: const Color(0x14FFFFFF),
        onTap: () => Nav.open(i),
        onLongPress: i is Track ? () => showTrackMenu(context, i) : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (i is Track) TrackArt(i, size: 96, radius: 6, px: 240) else Art(i.art, size: 96, radius: 6, circle: i is ArtistCard, px: 240, shadow: true),
                const SizedBox(height: 18),
                Text(i.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleXL.copyWith(fontSize: 28)),
                const SizedBox(height: 6),
                Row(children: [
                  if (who.isNotEmpty) Flexible(child: Text('$who  ', maxLines: 1, overflow: TextOverflow.ellipsis, style: subtle)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(999)),
                    child: Text(kind, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
            PlayCircle(playing: false, onTap: onPlay, size: 48),
          ]),
        ),
      ),
    );
  }
}
