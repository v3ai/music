import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models.dart';
import 'tabs.dart';

// Guitar tabs and chord sheets from Ultimate Guitar.

class UgVersion {
  final String url;
  final String type; // Tabs | Chords | Bass Tabs | Ukulele Chords
  final int version;
  final double rating;
  final int votes;
  final String artist;
  final String song;
  const UgVersion(this.url, this.type, this.version, this.rating, this.votes, this.artist, this.song);

  bool get isChords => type.contains('Chords');

  /// Short name for menus: "Tab", "Chords", "Bass tab", "Ukulele chords".
  String get kind => switch (type) {
    'Tabs' => 'Tab',
    'Bass Tabs' => 'Bass tab',
    'Ukulele Chords' => 'Ukulele chords',
    _ => type,
  };

  String get label => '$kind${version > 1 ? ' v$version' : ''} · ★ ${rating.toStringAsFixed(1)} ($votes)';

  /// Well-rated with plenty of votes beats a perfect score from two people.
  double get score => rating * math.log(votes + 2);

  Map<String, dynamic> toJson() => {'url': url, 'type': type, 'version': version, 'rating': rating, 'votes': votes, 'artist': artist, 'song': song};
  factory UgVersion.fromJson(Map j) => UgVersion(j['url'], j['type'], j['version'], (j['rating'] as num).toDouble(), j['votes'], j['artist'], j['song']);
}

/// One chord shape. [frets] runs from the lowest string to the highest; -1 = don't play.
class ChordShape {
  final String name;
  final List<int> frets;
  final List<int> fingers;
  final int baseFret; // 0 = open position
  const ChordShape(this.name, this.frets, this.fingers, this.baseFret);
}

class UgSheet {
  final UgVersion version;
  final String content; // UG markup: [tab]...[/tab], [ch]G[/ch]
  final int capo;
  final String? tuning; // e.g. "E A D G B E"
  final String? key;
  final List<ChordShape> chords;
  const UgSheet(this.version, this.content, this.capo, this.tuning, this.key, this.chords);
}

class UltimateGuitar {
  UltimateGuitar(this.cacheDir);
  final Directory cacheDir;

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const _types = {'Tabs', 'Chords', 'Bass Tabs', 'Ukulele Chords'};

  final _http = http.Client();
  final _versions = <String, Future<List<UgVersion>>>{};
  final _sheets = <String, Future<UgSheet>>{};

  /// Every tab and chord sheet for [t], best first within each kind.
  Future<List<UgVersion>> versions(Track t) => _versions.putIfAbsent(t.id, () {
    final f = _find(t);
    f.then(
      (_) {},
      onError: (_) {
        _versions.remove(t.id);
      },
    );
    return f;
  });

  Future<UgSheet> sheet(UgVersion v) => _sheets.putIfAbsent(v.url, () {
    final f = _sheet(v);
    f.then(
      (_) {},
      onError: (_) {
        _sheets.remove(v.url);
      },
    );
    return f;
  });

  /// What to show first: the best guitar tab, or the best chord sheet if there's no
  /// well-voted tab (most pop songs are played from chords).
  static UgVersion? best(List<UgVersion> all) {
    UgVersion? top(String type) {
      final l = all.where((v) => v.type == type).toList()..sort((a, b) => b.score.compareTo(a.score));
      return l.firstOrNull;
    }

    final tab = top('Tabs'), chords = top('Chords');
    if (tab != null && (chords == null || tab.score >= chords.score * .5)) return tab;
    return chords ?? tab ?? top('Bass Tabs') ?? top('Ukulele Chords');
  }

  // ------------------------------------------------------------------ fetching

  File _file(String name) => File('${cacheDir.path}/$name');

  Future<Map> _store(String url) async {
    final r = await _http.get(Uri.parse(url), headers: {'user-agent': _ua, 'accept-language': 'en-US,en;q=0.9'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw HttpException('ultimate-guitar ${r.statusCode}');
    final m = RegExp(r'class="js-store" data-content="([^"]*)"').firstMatch(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (m == null) throw const FormatException('ultimate-guitar page changed');
    final j = jsonDecode(_unescape(m.group(1)!)) as Map;
    return (j['store']?['page']?['data'] as Map?) ?? const {};
  }

  Future<List<UgVersion>> _search(String query) async {
    final url = 'https://www.ultimate-guitar.com/search.php?search_type=title&value=${Uri.encodeQueryComponent(query)}';
    final data = await _store(url);
    return [
      for (final r in (data['results'] as List? ?? const []))
        if (r is Map && _types.contains(r['type']) && (r['tab_access_type'] ?? 'public') == 'public' && r['tab_url'] is String)
          UgVersion(
            r['tab_url'],
            r['type'],
            (r['version'] as num?)?.toInt() ?? 1,
            (r['rating'] as num?)?.toDouble() ?? 0,
            (r['votes'] as num?)?.toInt() ?? 0,
            '${r['artist_name'] ?? ''}',
            '${r['song_name'] ?? ''}',
          ),
    ];
  }

  Future<List<UgVersion>> _find(Track t) async {
    final cache = _file('ug-search-${t.id}.json');
    try {
      if (await cache.exists() && DateTime.now().difference(await cache.lastModified()) < const Duration(days: 7)) {
        return [for (final v in jsonDecode(await cache.readAsString()) as List) UgVersion.fromJson(v as Map)];
      }
    } catch (_) {}

    final title = Tabs.cleanTitle(t.title);
    final artist = t.artists.isEmpty ? '' : t.artists.first.name;
    var found = _matching(t, title, await _search('$artist $title'.trim()));
    if (found.isEmpty && artist.isNotEmpty) found = _matching(t, title, await _search(title));
    found.sort((a, b) {
      const order = ['Tabs', 'Chords', 'Bass Tabs', 'Ukulele Chords'];
      final o = order.indexOf(a.type).compareTo(order.indexOf(b.type));
      return o != 0 ? o : b.score.compareTo(a.score);
    });
    try {
      await cache.parent.create(recursive: true);
      await cache.writeAsString(jsonEncode([for (final v in found) v.toJson()]));
    } catch (_) {}
    return found;
  }

  List<UgVersion> _matching(Track t, String title, List<UgVersion> results) {
    final want = Tabs.norm(title);
    final artists = [for (final a in t.artists) Tabs.norm(a.name)].where((a) => a.isNotEmpty).toList();
    return [
      for (final v in results)
        if (_titleMatches(want, Tabs.norm(Tabs.cleanTitle(v.song))) && _artistMatches(artists, Tabs.norm(v.artist))) v,
    ];
  }

  static bool _titleMatches(String want, String got) => want.isNotEmpty && got.isNotEmpty && (got == want || got.startsWith(want) || want.startsWith(got));

  static bool _artistMatches(List<String> artists, String got) => artists.isEmpty || artists.any((a) => a == got || got.contains(a) || a.contains(got));

  Future<UgSheet> _sheet(UgVersion v) async {
    final cache = _file('ug-tab-${Tabs.norm(v.url).hashCode.toUnsigned(32)}.json');
    Map? data;
    try {
      if (await cache.exists()) data = jsonDecode(await cache.readAsString()) as Map;
    } catch (_) {}
    if (data == null) {
      final page = await _store(v.url);
      final view = page['tab_view'] as Map? ?? const {};
      data = {'content': view['wiki_tab']?['content'] ?? '', 'meta': view['meta'] ?? const {}, 'applicature': view['applicature'] ?? const {}};
      try {
        await cache.parent.create(recursive: true);
        await cache.writeAsString(jsonEncode(data));
      } catch (_) {}
    }
    final meta = (data['meta'] is Map ? data['meta'] : const {}) as Map;
    final chords = <ChordShape>[];
    final app = data['applicature'];
    if (app is Map) {
      for (final e in app.entries) {
        final shapes = e.value;
        if (shapes is! List || shapes.isEmpty || shapes.first is! Map) continue;
        final s = shapes.first as Map;
        final frets = [for (final f in (s['frets'] as List? ?? const [])) (f as num).toInt()];
        final fingers = [for (final f in (s['fingers'] as List? ?? const [])) (f as num).toInt()];
        if (frets.isEmpty) continue;
        // UG lists the highest string first
        chords.add(ChordShape('${e.key}', frets.reversed.toList(), fingers.reversed.toList(), (s['fret'] as num?)?.toInt() ?? 0));
      }
    }
    final tuning = meta['tuning'] is Map ? meta['tuning']['value'] as String? : null;
    return UgSheet(v, '${data['content']}', (meta['capo'] as num?)?.toInt() ?? 0, tuning, (meta['tonality'] as String?), chords);
  }

  static String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|quot|amp|lt|gt|apos|#039);'), (m) {
    final e = m.group(1)!;
    if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
    if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
    return const {'quot': '"', 'amp': '&', 'lt': '<', 'gt': '>', 'apos': "'"}[e]!;
  });

  void close() => _http.close();
}
