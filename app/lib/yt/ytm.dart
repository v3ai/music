import 'dart:async';

import '../models.dart';
import 'innertube.dart';

/// YouTube Music: search, browse, radio and lyrics, normalized into app models.
///
/// Parsing is by *item type* (what an entry links to), not by shelf position or title,
/// so it keeps working when YouTube rearranges its pages.
class Ytm {
  Ytm({InnerTube? client}) : it = client ?? InnerTube();

  final InnerTube it;
  final _cache = <String, (DateTime, Future<dynamic>)>{};

  /// Memoize a request for [ttl]; failed requests are not cached.
  Future<T> _cached<T>(String key, Duration ttl, Future<T> Function() load) {
    final hit = _cache[key];
    if (hit != null && hit.$1.isAfter(DateTime.now())) return hit.$2 as Future<T>;
    final f = load();
    _cache[key] = (DateTime.now().add(ttl), f);
    f.then((_) {}, onError: (_) {
      _cache.remove(key);
    });
    if (_cache.length > 300) _cache.remove(_cache.keys.first);
    return f;
  }

  // ---------------------------------------------------------------- search

  static const _songsParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  Future<List<String>> suggestions(String q) => _cached('sug:$q', const Duration(minutes: 10), () async {
        final j = await it.suggestions(q);
        final out = <String>[];
        _walk(j, (k, v) {
          if (k == 'searchSuggestionRenderer') {
            final s = _text(v['suggestion']);
            if (s.isNotEmpty) out.add(s);
          }
        });
        return out;
      });

  Future<List<Track>> searchSongs(String q) => _cached('songs:$q', const Duration(minutes: 10), () async {
        final j = await it.search(q, params: _songsParams);
        return _items(j).whereType<Track>().toList();
      });

  Future<SearchResults> search(String q) => _cached('search:$q', const Duration(minutes: 10), () async {
        final general = it.search(q);
        final songsF = searchSongs(q).catchError((_) => <Track>[]);
        final j = await general;

        Item? top;
        final topTracks = <Track>[];
        _walk(j, (k, v) {
          if (k != 'musicCardShelfRenderer' || top != null) return;
          top = _cardTop(v);
          for (final c in (v['contents'] as List? ?? const [])) {
            final r = c is Map ? c['musicResponsiveListItemRenderer'] : null;
            final t = r == null ? null : _fromResponsive(r);
            if (t is Track) topTracks.add(t);
          }
        });

        final all = _items(j, skipKey: 'musicCardShelfRenderer');
        var songs = await songsF;
        // fall back to the songs mixed into the general results
        if (songs.isEmpty) songs = [...topTracks, ...all.whereType<Track>().where((t) => !t.isVideo)];
        // the top result's songs come without artists; fill from a top artist
        if (top is ArtistCard) {
          final a = top as ArtistCard;
          songs = [for (final s in songs) s.artists.isEmpty ? s.copyWith(artists: [ArtistRef(a.name, a.id)]) : s];
        }
        final seen = <String>{};
        return SearchResults(
          top: top,
          songs: [for (final s in songs) if (seen.add(s.id)) s],
          videos: all.whereType<Track>().where((t) => t.isVideo).toList(),
          albums: _dedupe(all.whereType<AlbumCard>()),
          artists: _dedupe(all.whereType<ArtistCard>().where((a) => a.id != top?.id)),
          playlists: _dedupe(all.whereType<PlaylistCard>()),
        );
      });

  Item? _cardTop(Map v) {
    final run = nav(v, ['title', 'runs', 0]);
    if (run is! Map) return null;
    final name = run['text'] as String? ?? '';
    final art = _thumb(v);
    final ne = run['navigationEndpoint'];
    final browse = nav(ne, ['browseEndpoint']);
    final subtitle = (nav(v, ['subtitle', 'runs']) as List?) ?? const [];
    if (browse != null) {
      final id = browse['browseId'] as String? ?? '';
      switch (_pageType(browse)) {
        case 'MUSIC_PAGE_TYPE_ARTIST':
          return ArtistCard(id: id, name: name, art: art);
        case 'MUSIC_PAGE_TYPE_ALBUM':
          final p = _parseRuns(subtitle);
          return AlbumCard(id: id, title: name, artists: p.artists, year: p.year, type: p.type ?? 'Album', art: art);
        case 'MUSIC_PAGE_TYPE_PLAYLIST':
          return PlaylistCard(id: _stripVL(id), title: name, author: _parseRuns(subtitle).artists.firstOrNull?.name, art: art);
      }
      return null;
    }
    final vid = nav(ne, ['watchEndpoint', 'videoId']);
    if (vid is String) {
      final p = _parseRuns(subtitle);
      final vt = nav(ne, ['watchEndpoint', ..._videoTypePath]);
      return Track(
        id: vid,
        title: name,
        artists: p.artists,
        album: p.album,
        duration: p.duration,
        art: _normArt(art, vid),
        isVideo: _isVideo(vt),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------- pages

  Future<Album> album(String id) => _cached('album:$id', const Duration(hours: 6), () async {
        final j = await it.browse(id);
        final h = _find(j, 'musicResponsiveHeaderRenderer') ?? const {};
        final title = _text(h['title']);
        final sub = _parseRuns((nav(h, ['subtitle', 'runs']) as List?) ?? const []);
        var artists = _parseRuns((nav(h, ['straplineTextOne', 'runs']) as List?) ?? const []).artists;
        if (artists.isEmpty) artists = sub.artists;
        final art = _thumb(h);
        final ref = AlbumRef(title, id);

        final tracks = <Track>[];
        final shelf = _find(j, 'musicShelfRenderer');
        for (final c in (shelf?['contents'] as List? ?? const [])) {
          final r = c is Map ? c['musicResponsiveListItemRenderer'] : null;
          if (r == null) continue;
          final t = _fromResponsive(r);
          if (t is! Track) continue;
          tracks.add(Track(
            id: t.id,
            title: t.title,
            artists: t.artists.isEmpty ? artists : t.artists,
            album: ref,
            duration: t.duration,
            art: art,
            explicit: t.explicit,
          ));
        }

        final versions = <AlbumCard>[];
        _walk(j, (k, v) {
          if (k != 'musicCarouselShelfRenderer') return;
          final t = _text(nav(v, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title'])).toLowerCase();
          if (t.contains('version')) versions.addAll(_carouselItems(v).whereType<AlbumCard>());
        });

        return Album(
          id: id,
          title: title,
          type: sub.type ?? 'Album',
          artists: artists,
          year: sub.year,
          art: art,
          tracks: tracks,
          otherVersions: versions,
        );
      });

  Future<Artist> artist(String id) => _cached('artist:$id', const Duration(hours: 6), () async {
        final j = await it.browse(id);
        final h = (nav(j, ['header', 'musicImmersiveHeaderRenderer']) ??
            nav(j, ['header', 'musicVisualHeaderRenderer']) ??
            _find(j, 'musicResponsiveHeaderRenderer') ??
            const {}) as Map;
        final name = _text(h['title']);
        final self = ArtistRef(name, id);
        var songs = <Track>[];
        String? songsPlaylist;
        final albums = <AlbumCard>[], singles = <AlbumCard>[], videos = <Track>[], related = <ArtistCard>[];
        final more = <Shelf>[];

        _walk(j, (k, v) {
          if (k == 'musicShelfRenderer' && songs.isEmpty) {
            songs = _shelfItems(v).whereType<Track>().map((t) => t.artists.isEmpty ? t.copyWith(artists: [self]) : t).toList();
            final b = nav(v, ['bottomEndpoint', 'browseEndpoint', 'browseId']) ?? nav(v, ['title', 'runs', 0, 'navigationEndpoint', 'browseEndpoint', 'browseId']);
            if (b is String) songsPlaylist = _stripVL(b);
          } else if (k == 'musicCarouselShelfRenderer') {
            final title = _text(nav(v, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title']));
            final items = _carouselItems(v, defaultArtists: [self]);
            final lower = title.toLowerCase();
            if (items.isEmpty) return;
            if (items.every((i) => i is AlbumCard)) {
              (lower.contains('single') || lower.contains('ep') ? singles : albums).addAll(items.cast<AlbumCard>());
            } else if (items.every((i) => i is ArtistCard)) {
              related.addAll(items.cast<ArtistCard>());
            } else if (lower == 'videos') {
              videos.addAll(items.whereType<Track>());
            } else {
              more.add(Shelf(title, items));
            }
          }
        });

        final banner = _thumb(h);
        return Artist(
          id: id,
          name: name,
          art: banner,
          description: _text(h['description']).trim().isEmpty ? null : _text(h['description']).trim(),
          listeners: _text(h['monthlyListenerCount']).isEmpty
              ? (_text(nav(h, ['subscriptionButton', 'subscribeButtonRenderer', 'subscriberCountText'])).isEmpty
                  ? null
                  : '${_text(nav(h, ['subscriptionButton', 'subscribeButtonRenderer', 'subscriberCountText']))} subscribers')
              : _text(h['monthlyListenerCount']),
          songs: songs,
          songsPlaylistId: songsPlaylist,
          albums: albums,
          singles: singles,
          videos: videos,
          related: related,
          more: more,
        );
      });

  Future<Playlist> playlist(String id, {int maxTracks = 1000}) =>
      _cached('pl:$id', const Duration(hours: 1), () async {
        final j = await it.browse('VL$id');
        final h = _find(j, 'musicResponsiveHeaderRenderer') ?? _find(j, 'musicDetailHeaderRenderer') ?? const {};
        final title = _text(h['title']);
        final author = _text(h['straplineTextOne']).isNotEmpty
            ? _text(h['straplineTextOne'])
            : _parseRuns((nav(h, ['subtitle', 'runs']) as List?) ?? const []).artists.firstOrNull?.name;
        final desc = _text(nav(h, ['description', 'musicDescriptionShelfRenderer', 'description'])).isNotEmpty
            ? _text(nav(h, ['description', 'musicDescriptionShelfRenderer', 'description']))
            : _text(h['description']);

        final tracks = <Track>[];
        final shelf = _find(j, 'musicPlaylistShelfRenderer') ?? _find(j, 'musicShelfRenderer');
        var contents = (shelf?['contents'] as List?) ?? const [];
        String? token = nav(shelf, ['continuations', 0, 'nextContinuationData', 'continuation']);
        for (var page = 0; page < 25; page++) {
          for (final c in contents) {
            if (c is! Map) continue;
            final r = c['musicResponsiveListItemRenderer'];
            if (r != null) {
              final t = _fromResponsive(r);
              if (t is Track) tracks.add(t);
            }
            final ct = nav(c, ['continuationItemRenderer', 'continuationEndpoint', 'continuationCommand', 'token']);
            if (ct is String) token = ct;
          }
          if (token == null || tracks.length >= maxTracks) break;
          final next = await it.continuationCommand('browse', token).catchError((_) => <String, dynamic>{});
          token = null;
          contents = (nav(next, ['onResponseReceivedActions', 0, 'appendContinuationItemsAction', 'continuationItems']) as List?) ??
              (nav(next, ['continuationContents', 'musicPlaylistShelfContinuation', 'contents']) as List?) ??
              const [];
          token = nav(next, ['continuationContents', 'musicPlaylistShelfContinuation', 'continuations', 0, 'nextContinuationData', 'continuation']);
          if (contents.isEmpty) break;
        }

        return Playlist(id: id, title: title, author: author, description: desc.isEmpty ? null : desc, art: _thumb(h), tracks: tracks);
      });

  Future<List<Shelf>> home() => _cached('home', const Duration(minutes: 30), () async {
        var j = await it.browse('FEmusic_home');
        final shelves = <Shelf>[];
        void collect(Map j) {
          _walk(j, (k, v) {
            if (k != 'musicCarouselShelfRenderer') return;
            final title = _text(nav(v, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title']));
            final items = _carouselItems(v);
            if (title.isNotEmpty && items.isNotEmpty) shelves.add(Shelf(title, items));
          });
        }

        collect(j);
        String? token = nav(j, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'continuations', 0, 'nextContinuationData', 'continuation']);
        for (var i = 0; i < 3 && token != null && shelves.length < 12; i++) {
          try {
            j = await it.continuation(token);
          } catch (_) {
            break;
          }
          collect(j);
          token = nav(j, ['continuationContents', 'sectionListContinuation', 'continuations', 0, 'nextContinuationData', 'continuation']);
        }
        return shelves;
      });

  // ---------------------------------------------------------------- watch / radio / lyrics

  /// Songs to play after [videoId] (YouTube Music's "radio" for it). The first item is the song itself.
  Future<List<Track>> radio(String videoId, {String? playlistId}) async {
    final w = await _watch(videoId, playlistId: playlistId);
    return w.$1;
  }

  Future<(List<Track>, String?)> _watch(String videoId, {String? playlistId}) =>
      _cached('watch:$videoId:$playlistId', const Duration(minutes: 30), () async {
        final j = await it.next(videoId: videoId, playlistId: playlistId);
        final tabs = (nav(j, ['contents', 'singleColumnMusicWatchNextResultsRenderer', 'tabbedRenderer', 'watchNextTabbedResultsRenderer', 'tabs']) as List?) ?? const [];
        final tracks = <Track>[];
        String? lyricsId;
        for (final t in tabs) {
          final b = nav(t, ['tabRenderer', 'endpoint', 'browseEndpoint']);
          if (b is Map && _pageType(b) == 'MUSIC_PAGE_TYPE_TRACK_LYRICS') lyricsId = b['browseId'];
        }
        final panel = nav(tabs, [0, 'tabRenderer', 'content', 'musicQueueRenderer', 'content', 'playlistPanelRenderer', 'contents']) as List? ?? const [];
        for (var c in panel) {
          if (c is! Map) continue;
          c = nav(c, ['playlistPanelVideoWrapperRenderer', 'primaryRenderer']) ?? c;
          final v = c['playlistPanelVideoRenderer'];
          if (v is! Map || v['videoId'] == null) continue;
          final p = _parseRuns((nav(v, ['longBylineText', 'runs']) as List?) ?? const []);
          final vt = nav(v, ['navigationEndpoint', 'watchEndpoint', ..._videoTypePath]);
          tracks.add(Track(
            id: v['videoId'],
            title: _text(v['title']),
            artists: p.artists,
            album: p.album,
            duration: _parseDuration(_text(v['lengthText'])),
            art: _normArt(_bestThumb(nav(v, ['thumbnail', 'thumbnails'])), v['videoId']),
            isVideo: _isVideo(vt),
          ));
        }
        return (tracks, lyricsId);
      });

  Future<Lyrics?> lyrics(String videoId) => _cached('lyr:$videoId', const Duration(hours: 12), () async {
        final w = await _watch(videoId);
        if (w.$2 == null) return null;
        final j = await it.browse(w.$2!);
        final d = _find(j, 'musicDescriptionShelfRenderer');
        if (d == null) return null;
        final text = _text(d['description']);
        if (text.trim().isEmpty) return null;
        final src = _text(d['footer']);
        return Lyrics(text, src.isEmpty ? null : src.replaceFirst(RegExp(r'^Source:\s*'), ''));
      });

  // ---------------------------------------------------------------- album art for videos

  static final _noise = RegExp(
      r'\s*[\(\[][^\)\]]*(official|video|lyric|audio|visuali[sz]er|\bhd\b|\b4k\b|\bhq\b|\bmv\b|clip|remaster|explicit|clean|performance|color coded|letra|legendado)[^\)\]]*[\)\]]',
      caseSensitive: false);
  static final _feat = RegExp(r'\s+[\(\[]?(ft|feat|featuring)\.?\s.*$', caseSensitive: false);
  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  static String _cleanTitle(String t) =>
      t.replaceAll(_noise, '').replaceAll(_feat, '').trim().replaceAll(RegExp(r'''^[\s\-|–—"']+|[\s\-|–—"']+$'''), '');

  static bool isVideoArt(String? url) => url == null || url.contains('i.ytimg.com');

  /// For a music video, find the album version of the song so it can show the real cover.
  Future<Track?> matchSong(Track video) => _cached('match:${video.id}', const Duration(days: 7), () async {
        var names = [for (final a in video.artists) if (a.name.isNotEmpty) a.name];
        var t = _cleanTitle(video.title);
        for (final sep in const [' - ', ' – ', ' — ', ' | ']) {
          final i = t.indexOf(sep);
          if (i < 0) continue;
          final left = t.substring(0, i), right = t.substring(i + sep.length);
          if (names.isEmpty || names.any((n) => _norm(left).contains(_norm(n)) || _norm(n).contains(_norm(left)))) {
            if (names.isEmpty) names = [left.trim()];
            t = _cleanTitle(right);
          }
          break;
        }
        if (t.isEmpty) return null;
        final nt = _norm(t), who = _norm(names.join(' '));
        final results = await searchSongs('${names.isNotEmpty ? names.first : ''} $t'.trim());
        for (final s in results.take(6)) {
          final st = _norm(_cleanTitle(s.title));
          final shorter = st.length < nt.length ? st.length : nt.length;
          final longer = st.length > nt.length ? st.length : nt.length;
          final titleOk = st == nt ||
              (shorter >= 4 && (st.startsWith(nt) || nt.startsWith(st)) && shorter / longer > 0.6);
          final artistOk = who.isEmpty ||
              s.artists.any((a) {
                final n = _norm(a.name);
                return n.isNotEmpty && (who.contains(n) || n.contains(who));
              });
          if (titleOk && artistOk && s.art != null && !isVideoArt(s.art)) return s;
        }
        return null;
      });

  // ---------------------------------------------------------------- item parsing

  static const _videoTypePath = ['watchEndpointMusicSupportedConfigs', 'watchEndpointMusicConfig', 'musicVideoType'];

  static bool _isVideo(dynamic vt) => vt is String && vt != 'MUSIC_VIDEO_TYPE_ATV';

  static String? _pageType(dynamic browseEndpoint) =>
      nav(browseEndpoint, ['browseEndpointContextSupportedConfigs', 'browseEndpointContextMusicConfig', 'pageType']);

  static String _stripVL(String id) => id.startsWith('VL') ? id.substring(2) : id;

  /// All list/grid items in a response, in order, skipping anything under [skipKey].
  List<Item> _items(Map j, {String? skipKey}) {
    final out = <Item>[];
    _walk(j, (k, v) {
      if (k == 'musicResponsiveListItemRenderer') {
        final i = _fromResponsive(v);
        if (i != null) out.add(i);
      } else if (k == 'musicTwoRowItemRenderer') {
        final i = _fromTwoRow(v);
        if (i != null) out.add(i);
      }
    }, skip: skipKey);
    return out;
  }

  List<Item> _shelfItems(Map shelf) => [
        for (final c in (shelf['contents'] as List? ?? const []))
          if (c is Map && c['musicResponsiveListItemRenderer'] != null) _fromResponsive(c['musicResponsiveListItemRenderer']),
      ].whereType<Item>().toList();

  List<Item> _carouselItems(Map shelf, {List<ArtistRef>? defaultArtists}) {
    final out = <Item>[];
    for (final c in (shelf['contents'] as List? ?? const [])) {
      if (c is! Map) continue;
      Item? i;
      if (c['musicTwoRowItemRenderer'] != null) i = _fromTwoRow(c['musicTwoRowItemRenderer']);
      if (c['musicResponsiveListItemRenderer'] != null) i = _fromResponsive(c['musicResponsiveListItemRenderer']);
      if (i == null) continue;
      if (defaultArtists != null) {
        if (i is AlbumCard && i.artists.isEmpty) {
          i = AlbumCard(id: i.id, title: i.title, artists: defaultArtists, year: i.year, type: i.type, art: i.art);
        } else if (i is Track && i.artists.isEmpty) {
          i = i.copyWith(artists: defaultArtists);
        }
      }
      out.add(i);
    }
    return out;
  }

  Item? _fromResponsive(Map r) {
    final cols = [
      for (final c in (r['flexColumns'] as List? ?? const []))
        (nav(c, ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']) as List?) ?? const [],
    ];
    if (cols.isEmpty) return null;
    final title = cols[0].map((x) => x['text'] ?? '').join();
    final play = nav(r, ['overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer', 'playNavigationEndpoint']);
    final videoId = nav(r, ['playlistItemData', 'videoId']) ??
        nav(play, ['watchEndpoint', 'videoId']) ??
        nav(cols[0], [0, 'navigationEndpoint', 'watchEndpoint', 'videoId']);
    final browse = nav(r, ['navigationEndpoint', 'browseEndpoint']);
    final art = _thumb(r);

    if (videoId is String && browse == null) {
      final vt = nav(play, ['watchEndpoint', ..._videoTypePath]) ??
          nav(cols[0], [0, 'navigationEndpoint', 'watchEndpoint', ..._videoTypePath]);
      if (vt == 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE') return null;
      final p = _parseRuns(cols.length > 1 ? cols[1] : const []);
      AlbumRef? album = p.album;
      for (final col in cols.skip(2)) {
        for (final run in col) {
          final id = nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
          if (album == null && id is String && id.startsWith('MPRE')) album = AlbumRef(run['text'], id);
        }
      }
      final fixed = _text(nav(r, ['fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text']));
      return Track(
        id: videoId,
        title: title,
        artists: p.artists,
        album: album,
        duration: _parseDuration(fixed) ?? p.duration,
        art: _normArt(art, videoId),
        explicit: _explicit(r),
        isVideo: _isVideo(vt),
      );
    }
    if (browse is Map) {
      final id = browse['browseId'] as String? ?? '';
      final p = _parseRuns(cols.length > 1 ? cols[1] : const []);
      switch (_pageType(browse)) {
        case 'MUSIC_PAGE_TYPE_ALBUM':
          return AlbumCard(id: id, title: title, artists: p.artists, year: p.year, type: p.type ?? 'Album', art: art);
        case 'MUSIC_PAGE_TYPE_ARTIST':
          return ArtistCard(id: id, name: title, art: art);
        case 'MUSIC_PAGE_TYPE_PLAYLIST':
          return PlaylistCard(id: _stripVL(id), title: title, author: p.artists.firstOrNull?.name, count: p.extra, art: art);
      }
    }
    return null;
  }

  Item? _fromTwoRow(Map r) {
    final title = _text(r['title']);
    final ne = r['navigationEndpoint'];
    final art = _thumb(r);
    final sub = (nav(r, ['subtitle', 'runs']) as List?) ?? const [];
    final vid = nav(ne, ['watchEndpoint', 'videoId']);
    if (vid is String) {
      final vt = nav(ne, ['watchEndpoint', ..._videoTypePath]);
      if (vt == 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE') return null;
      final p = _parseRuns(sub);
      return Track(id: vid, title: title, artists: p.artists, album: p.album, duration: p.duration, art: _normArt(art, vid), isVideo: _isVideo(vt), explicit: _explicit(r));
    }
    final browse = nav(ne, ['browseEndpoint']);
    if (browse is Map) {
      final id = browse['browseId'] as String? ?? '';
      final p = _parseRuns(sub);
      switch (_pageType(browse)) {
        case 'MUSIC_PAGE_TYPE_ALBUM':
          return AlbumCard(id: id, title: title, artists: p.artists, year: p.year, type: p.type ?? 'Album', art: art);
        case 'MUSIC_PAGE_TYPE_ARTIST':
          return ArtistCard(id: id, name: title, art: art);
        case 'MUSIC_PAGE_TYPE_PLAYLIST':
          return PlaylistCard(id: _stripVL(id), title: title, author: p.artists.firstOrNull?.name, count: p.extra, art: art);
      }
    }
    final pid = nav(ne, ['watchPlaylistEndpoint', 'playlistId']);
    if (pid is String && (pid.startsWith('PL') || pid.startsWith('RDCLAK') || pid.startsWith('OLAK'))) {
      return PlaylistCard(id: pid, title: title, author: _parseRuns(sub).artists.firstOrNull?.name, art: art);
    }
    return null;
  }

  static const _typeWords = {'Song', 'Video', 'Album', 'Single', 'EP', 'Playlist', 'Artist', 'Episode', 'Podcast', 'Profile', 'Station'};
  static final _durRe = RegExp(r'^(\d+:)*\d+:\d+$');
  static final _yearRe = RegExp(r'^\d{4}$');
  static final _countRe = RegExp(r'\b(views?|plays?|songs?|tracks?|subscribers?|monthly audience|listeners?|episodes?)\b', caseSensitive: false);

  static _Runs _parseRuns(List runs) {
    final out = _Runs();
    var start = 0;
    if (runs.isNotEmpty && runs[0] is Map && runs[0]['navigationEndpoint'] == null && _typeWords.contains(runs[0]['text'])) {
      out.type = runs[0]['text'];
      start = runs.length > 1 && (runs[1]['text'] as String?)?.trim() == '•' ? 2 : 1;
    }
    for (var i = start; i < runs.length; i++) {
      final run = runs[i];
      if (run is! Map) continue;
      final text = (run['text'] as String? ?? '');
      final trimmed = text.trim();
      if (trimmed.isEmpty || trimmed == '•' || trimmed == '&' || trimmed == ',' || trimmed == 'and') continue;
      final id = nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
      if (id is String) {
        if (id.startsWith('MPRE') || id.contains('release_detail')) {
          out.album = AlbumRef(text, id);
        } else if (id.startsWith('UC') || id.startsWith('FEmusic_library_privately_owned_artist')) {
          out.artists.add(ArtistRef(text, id));
        }
        continue;
      }
      if (_durRe.hasMatch(trimmed)) {
        out.duration = _parseDuration(trimmed);
      } else if (_yearRe.hasMatch(trimmed)) {
        out.year = trimmed;
      } else if (_countRe.hasMatch(trimmed)) {
        out.extra = trimmed;
      } else if (out.album == null && run['navigationEndpoint'] == null) {
        // plain text name (artist without a channel), possibly "A, B & C"
        for (final n in trimmed.split(RegExp(r'\s*(?:,|&)\s*'))) {
          if (n.isNotEmpty) out.artists.add(ArtistRef(n));
        }
      }
    }
    return out;
  }

  static int? _parseDuration(String? s) {
    if (s == null || !_durRe.hasMatch(s.trim())) return null;
    var total = 0;
    for (final p in s.trim().split(':')) {
      total = total * 60 + int.parse(p);
    }
    return total;
  }

  static bool _explicit(Map r) {
    final badges = (r['badges'] as List? ?? const []) + (r['subtitleBadges'] as List? ?? const []);
    return badges.any((b) => nav(b, ['musicInlineBadgeRenderer', 'icon', 'iconType']) == 'MUSIC_EXPLICIT_BADGE');
  }

  static String? _bestThumb(dynamic list) {
    if (list is! List || list.isEmpty) return null;
    Map best = list.first;
    for (final t in list) {
      if (t is Map && ((t['width'] ?? 0) as num) >= ((best['width'] ?? 0) as num)) best = t;
    }
    var url = best['url'] as String?;
    if (url != null && url.startsWith('//')) url = 'https:$url';
    return url;
  }

  static String? _thumb(Map r) => _bestThumb(
        nav(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            nav(r, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            nav(r, ['thumbnail', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            nav(r, ['thumbnailRenderer', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            nav(r, ['thumbnail', 'thumbnails']),
      );

  /// Video thumbnails: use a clean 16:9 frame without letterbox bars.
  static String? _normArt(String? url, String videoId) {
    if (url == null) return null;
    if (url.contains('i.ytimg.com/vi/')) return 'https://i.ytimg.com/vi/$videoId/hq720.jpg';
    return url;
  }

  static String _text(dynamic o) {
    if (o is! Map) return '';
    final runs = o['runs'];
    if (runs is List) return runs.map((r) => r is Map ? (r['text'] ?? '') : '').join();
    return (o['simpleText'] as String?) ?? '';
  }

  static Map? _find(dynamic o, String key) {
    Map? found;
    _walk(o, (k, v) {
      if (found == null && k == key) found = v;
    });
    return found;
  }

  /// Depth-first visit of every (key, value) where value is a Map. Does not descend into
  /// item renderers (their insides are handled by the item parsers) or into [skip].
  static void _walk(dynamic o, void Function(String key, Map value) visit, {String? skip}) {
    if (o is Map) {
      for (final e in o.entries) {
        final v = e.value;
        if (e.key == skip) continue;
        if (v is Map) {
          visit(e.key, v);
          if (e.key == 'musicResponsiveListItemRenderer' || e.key == 'musicTwoRowItemRenderer') continue;
        }
        if (v is Map || v is List) _walk(v, visit, skip: skip);
      }
    } else if (o is List) {
      for (final v in o) {
        _walk(v, visit, skip: skip);
      }
    }
  }

  static List<T> _dedupe<T extends Item>(Iterable<T> items) {
    final seen = <String>{};
    return [for (final i in items) if (seen.add(i.id)) i];
  }

  void close() => it.close();
}

class _Runs {
  String? type;
  final artists = <ArtistRef>[];
  AlbumRef? album;
  int? duration;
  String? year;
  String? extra;
}
