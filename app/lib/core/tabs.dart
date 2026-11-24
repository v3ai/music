import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models.dart';

// Guitar and bass tablature from Songsterr, matched to the playing song and timed
// against the recording so the tab can follow along.

class TabPartInfo {
  final int index;
  final String name; // e.g. "Jonny Greenwood | Lead Guitar"
  final String instrument; // e.g. "Distortion Guitar"
  final String kind; // guitar | bass | vocals | other
  final List<int> tuning; // MIDI note per string, highest string first
  final int views;
  const TabPartInfo(this.index, this.name, this.instrument, this.kind, this.tuning, this.views);

  /// Short label like "Lead Guitar" (the part of the name after the last "|").
  String get label {
    final parts = name.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? instrument : parts.last;
  }

  String get tuningName => tuning.reversed.map(noteName).join(' ');
}

String noteName(int midi) => const ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][midi % 12];

class TabSong {
  final int songId;
  final int revisionId;
  final String image;
  final String artist;
  final String title;
  final List<TabPartInfo> parts; // playable string parts only
  final int defaultPart;
  final List<VideoSync> syncs;
  const TabSong(this.songId, this.revisionId, this.image, this.artist, this.title, this.parts, this.defaultPart, this.syncs);

  String get url => 'https://www.songsterr.com/a/wsa/song-s${songId}t$defaultPart';
}

/// Start time (seconds) of each played measure in one YouTube video of the song.
class VideoSync {
  final String videoId;
  final String? feature; // null = the original recording
  final List<double> points;
  const VideoSync(this.videoId, this.feature, this.points);
}

class TabNote {
  final int string; // 0 = highest string
  final int fret;
  final bool tie, ghost, dead, hp, slide, bend, harmonic;
  const TabNote(this.string, this.fret, {this.tie = false, this.ghost = false, this.dead = false, this.hp = false, this.slide = false, this.bend = false, this.harmonic = false});
}

class TabBeat {
  final double length; // in whole notes
  final List<TabNote> notes; // empty = rest
  const TabBeat(this.length, this.notes);
}

class TabMeasure {
  final String? marker;
  final int sigNum, sigDen;
  final bool sigChanged;
  final List<TabBeat> beats;
  final bool repeatStart;
  final int repeatClose; // times to play, 0 = no repeat
  final List<int> endings; // alternate-ending passes this measure belongs to
  const TabMeasure(this.marker, this.sigNum, this.sigDen, this.sigChanged, this.beats, this.repeatStart, this.repeatClose, this.endings);
  double get length => sigNum / sigDen;
  bool get empty => beats.every((b) => b.notes.isEmpty);
}

class TabPart {
  final TabPartInfo info;
  final List<TabMeasure> measures;
  final List<int> order; // measure index for each played measure (repeats expanded)
  final List<double> wholeSecs; // seconds per whole note at each measure
  const TabPart(this.info, this.measures, this.order, this.wholeSecs);
  int get strings => info.tuning.length;
}

/// Maps playback time to (played measure, fraction through it) and back.
class TabClock {
  final List<double> starts; // per played measure
  final List<double> ends;
  final bool synced; // timed from a real recording rather than the written tempo
  TabClock(this.starts, this.ends, this.synced);

  /// Index into [TabPart.order] of the measure playing at [t] seconds, or -1 before the first.
  int indexAt(double t) {
    if (starts.isEmpty || t < starts.first) return -1;
    var lo = 0, hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  double fraction(int i, double t) {
    final len = ends[i] - starts[i];
    return len <= 0 ? 0 : ((t - starts[i]) / len).clamp(0.0, 1.0);
  }
}

class Tabs {
  Tabs(this.cacheDir);
  final Directory cacheDir;

  static const _api = 'https://www.songsterr.com/api';
  static const _cdn = 'https://dqsljvtekg760.cloudfront.net';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final _http = http.Client();
  final _songs = <String, Future<TabSong?>>{};
  final _parts = <String, Future<TabPart>>{};

  /// User's sync nudge per track, in seconds (+ = tab later).
  final offsets = <String, double>{};

  Future<TabSong?> find(Track t) => _songs.putIfAbsent(t.id, () {
        final f = _find(t);
        f.then((v) {
          if (v == null) _expire(t.id);
        }, onError: (_) {
          _songs.remove(t.id);
        });
        return f;
      });

  // a miss may get a tab later; ask again after a while
  void _expire(String id) => Timer(const Duration(minutes: 30), () => _songs.remove(id));

  Future<TabPart> part(TabSong s, TabPartInfo p) => _parts.putIfAbsent('${s.songId}/${s.revisionId}/${p.index}', () {
        final f = _part(s, p);
        f.then((_) {}, onError: (_) {
          _parts.remove('${s.songId}/${s.revisionId}/${p.index}');
        });
        return f;
      });

  /// The part to show first: the most-played guitar part, unless it's mostly rests
  /// (a short solo), in which case the fullest of the top guitar parts.
  Future<TabPart> defaultPart(TabSong s) async {
    final first = s.parts.firstWhere((p) => p.index == s.defaultPart, orElse: () => s.parts.first);
    final p = await part(s, first);
    if (_notes(p) >= 200) return p;
    final kind = s.parts.any((x) => x.kind == 'guitar') ? 'guitar' : first.kind;
    if (kind == 'vocals') return p;
    final others = s.parts.where((x) => x.kind == kind && x.index != first.index).toList()..sort((a, b) => b.views.compareTo(a.views));
    var best = p;
    for (final o in others.take(3)) {
      try {
        final q = await part(s, o);
        if (_notes(q) > _notes(best) * 1.5) best = q;
      } catch (_) {}
    }
    return best;
  }

  static int _notes(TabPart p) => p.measures.fold(0, (a, m) => a + m.beats.fold(0, (b, x) => b + x.notes.length));

  // ------------------------------------------------------------------ fetching

  Future<dynamic> _json(String url, {String? cacheAs, Duration maxAge = const Duration(days: 7)}) async {
    final file = cacheAs == null ? null : File('${cacheDir.path}/$cacheAs');
    if (file != null && await file.exists() && DateTime.now().difference(await file.lastModified()) < maxAge) {
      try {
        return jsonDecode(await file.readAsString());
      } catch (_) {}
    }
    try {
      final r = await _http.get(Uri.parse(url), headers: {'user-agent': _ua}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw HttpException('tabs ${r.statusCode}');
      var bytes = r.bodyBytes;
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) bytes = gzip.decode(bytes) as dynamic;
      final text = utf8.decode(bytes);
      final j = jsonDecode(text);
      if (file != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(text);
      }
      return j;
    } catch (e) {
      // offline: an old copy is better than nothing
      if (file != null && await file.exists()) return jsonDecode(await file.readAsString());
      rethrow;
    }
  }

  Future<TabSong?> _find(Track t) async {
    final title = cleanTitle(t.title);
    final artist = t.artists.isEmpty ? '' : t.artists.first.name;
    final q = Uri.encodeQueryComponent('$artist $title'.trim());
    final results = await _json('$_api/songs?pattern=$q&size=20') as List;
    Map? best;
    var bestScore = 0.0;
    for (final r in results) {
      if (r is! Map || r['hasPlayer'] == false || r['isJunk'] == true) continue;
      final s = _score(t, title, r);
      if (s > bestScore) {
        best = r;
        bestScore = s;
      }
    }
    if (best == null || bestScore < 3) return null;
    final id = best['songId'] as int;

    final meta = await _json('$_api/meta/$id', cacheAs: 'meta-$id.json', maxAge: const Duration(days: 3)) as Map;
    final rev = meta['revisionId'] as int;
    final parts = <TabPartInfo>[];
    final tracks = (meta['tracks'] as List?) ?? const [];
    for (var i = 0; i < tracks.length; i++) {
      final tr = tracks[i] as Map;
      final tuning = (tr['tuning'] as List?)?.cast<num>().map((n) => n.toInt()).toList();
      if (tuning == null || tuning.isEmpty) continue; // drums
      final searchTracks = best['tracks'] as List?;
      final fromSearch = searchTracks != null && i < searchTracks.length ? searchTracks[i] as Map : const {};
      final hash = '${tr['hash'] ?? fromSearch['hash'] ?? ''}';
      final inst = '${tr['instrument'] ?? ''}';
      final nm = '${tr['name'] ?? ''}'.toLowerCase();
      final vocal = hash.startsWith('vocal') || nm.contains('vocal') || nm.contains('voice') || nm.contains('melody');
      final kind = vocal
          ? 'vocals'
          : inst.contains('Guitar')
              ? 'guitar'
              : inst.contains('Bass')
                  ? 'bass'
                  : hash.startsWith('guitar')
                      ? 'guitar'
                      : hash.startsWith('bass')
                          ? 'bass'
                          : 'other';
      parts.add(TabPartInfo(i, '${tr['name'] ?? inst}', inst, kind, tuning, (tr['views'] as num? ?? fromSearch['views'] as num?)?.toInt() ?? 0));
    }
    if (parts.isEmpty) return null;
    final pref = (meta['popularTrackGuitar'] ?? meta['defaultTrack']) as int?;
    final def = parts.any((p) => p.index == pref && p.kind != 'vocals')
        ? pref!
        : (parts.firstWhere((p) => p.kind == 'guitar', orElse: () => parts.first)).index;

    var syncs = <VideoSync>[];
    try {
      final vp = await _json('$_api/video-points/$id/$rev/list', cacheAs: 'sync-$id-$rev.json', maxAge: const Duration(days: 30)) as List;
      syncs = [
        for (final v in vp)
          if (v is Map && v['status'] == 'done' && v['points'] is List && (v['points'] as List).isNotEmpty)
            VideoSync('${v['videoId']}', v['feature'] as String?, [for (final p in v['points'] as List) (p as num).toDouble()]),
      ];
    } catch (_) {}

    return TabSong(id, rev, '${meta['image']}', '${meta['artist'] ?? best['artist']}', '${meta['title'] ?? best['title']}', parts, def, syncs);
  }

  static final _noise = RegExp(
      r'\s*[\(\[][^\)\]]*(feat\.?|ft\.?|with |remaster|edit|version|mix|live|mono|stereo|deluxe|official|audio|video|lyric|explicit|clean|radio|bonus|from )[^\)\]]*[\)\]]',
      caseSensitive: false);

  static String cleanTitle(String s) {
    var t = s.replaceAll(_noise, '');
    t = t.replaceAll(RegExp(r'\s+-\s+.*(remaster|version|edit|live|mix|mono|stereo).*$', caseSensitive: false), '');
    return t.trim().isEmpty ? s : t.trim();
  }

  static String norm(String s) => s.toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static const _badWords = ['cover', 'fingerstyle', 'acoustic', 'lesson', 'solo', 'bass', 'guitar', 'drum', 'instrumental', 'karaoke', 'if it had', 'piano', 'tutorial', 'live'];

  double _score(Track t, String title, Map r) {
    final rt = '${r['title'] ?? ''}';
    final ra = norm('${r['artist'] ?? ''}');
    final want = norm(title);
    final got = norm(cleanTitle(rt));
    if (want.isEmpty || got.isEmpty) return 0;
    var s = 0.0;
    if (got == want) {
      s += 3;
    } else if (got.startsWith(want) || want.startsWith(got)) {
      s += 2;
    } else if (got.contains(want) || want.contains(got)) {
      s += 1.5;
    } else {
      return 0;
    }
    final artists = [for (final a in t.artists) norm(a.name)].where((a) => a.isNotEmpty);
    if (artists.any((a) => ra == a)) {
      s += 2;
    } else if (artists.any((a) => ra.contains(a) || a.contains(ra))) {
      s += 1.5;
    } else {
      s -= 2; // someone else's song with the same name, or a cover band
    }
    final lowTitle = rt.toLowerCase(), lowWant = t.title.toLowerCase();
    for (final w in _badWords) {
      if (lowTitle.contains(w) && !lowWant.contains(w)) s -= 1;
    }
    return s;
  }

  Future<TabPart> _part(TabSong s, TabPartInfo info) async {
    final j = await _json('$_cdn/${s.songId}/${s.revisionId}/${s.image}/${info.index}.json',
        cacheAs: 'part-${s.songId}-${s.revisionId}-${info.index}.json', maxAge: const Duration(days: 365)) as Map;
    final strings = (j['strings'] as num?)?.toInt() ?? info.tuning.length;
    final tuning = (j['tuning'] as List?)?.cast<num>().map((n) => n.toInt()).toList() ?? info.tuning;
    final fixed = TabPartInfo(info.index, info.name, info.instrument, info.kind, tuning.take(strings).toList(), info.views);

    final measures = <TabMeasure>[];
    var sigN = 4, sigD = 4;
    for (final m in (j['measures'] as List? ?? const [])) {
      final mm = m as Map;
      final sig = mm['signature'] as List?;
      if (sig != null && sig.length == 2) {
        sigN = (sig[0] as num).toInt();
        sigD = (sig[1] as num).toInt();
      }
      final voices = (mm['voices'] as List?) ?? const [];
      final beats = <TabBeat>[];
      if (voices.isNotEmpty) {
        for (final b in ((voices.first as Map)['beats'] as List? ?? const [])) {
          beats.add(_beat(b as Map));
        }
      }
      final marker = (mm['marker'] as Map?)?['text'] as String?;
      measures.add(TabMeasure(
        marker,
        sigN,
        sigD,
        sig != null,
        beats,
        mm['repeatStart'] == true,
        (mm['repeatClose'] as num?)?.toInt() ?? 0,
        [for (final e in (mm['alternateEnding'] as List? ?? const [])) (e as num).toInt()],
      ));
    }

    // seconds per whole note at each measure, from the tempo map
    final tempo = <int, double>{};
    for (final a in ((j['automations'] as Map?)?['tempo'] as List? ?? const [])) {
      final at = a as Map;
      final bpm = (at['bpm'] as num?)?.toDouble() ?? 120;
      final unit = (at['type'] as num?)?.toDouble() ?? 4;
      tempo.putIfAbsent((at['measure'] as num?)?.toInt() ?? 0, () => unit * 60 / bpm);
    }
    final wholeSecs = <double>[];
    var cur = tempo[0] ?? 2.0;
    for (var i = 0; i < measures.length; i++) {
      cur = tempo[i] ?? cur;
      wholeSecs.add(cur);
    }

    return TabPart(fixed, measures, _playOrder(measures), wholeSecs);
  }

  TabBeat _beat(Map b) {
    final d = b['duration'] as List?;
    var len = d == null || d.length != 2 ? .25 : (d[0] as num) / (d[1] as num);
    final dots = (b['dots'] as num?)?.toInt() ?? 0;
    if (dots == 1) len *= 1.5;
    if (dots >= 2) len *= 1.75;
    final tup = (b['tuplet'] as num?)?.toInt();
    if (tup != null && tup > 1) {
      final into = tup == 3 ? 2 : tup < 8 ? 4 : 8;
      len *= into / tup;
    }
    final notes = <TabNote>[];
    if (b['rest'] != true) {
      for (final n in (b['notes'] as List? ?? const [])) {
        final nn = n as Map;
        if (nn['rest'] == true || nn['string'] == null || nn['fret'] == null) continue;
        notes.add(TabNote(
          (nn['string'] as num).toInt(),
          (nn['fret'] as num).toInt(),
          tie: nn['tie'] == true,
          ghost: nn['ghost'] == true,
          dead: nn['dead'] == true,
          hp: nn['hp'] == true,
          slide: nn['slide'] != null && nn['slide'] != false,
          bend: nn['bend'] != null,
          harmonic: nn['harmonic'] != null,
        ));
      }
    }
    return TabBeat(len.toDouble(), notes);
  }

  /// Expand repeats and alternate endings into the order the measures are played.
  static List<int> _playOrder(List<TabMeasure> ms) {
    final out = <int>[];
    var start = 0, pass = 1, i = 0;
    var inEnding = false;
    while (i < ms.length && out.length < 5000) {
      final m = ms[i];
      if (m.endings.isEmpty && inEnding) pass = 1; // finished the last ending
      inEnding = m.endings.isNotEmpty;
      if (m.repeatStart && pass == 1) start = i;
      if (m.endings.isNotEmpty && !m.endings.contains(pass)) {
        i++;
        continue;
      }
      out.add(i);
      if (m.repeatClose > 0) {
        if (pass < m.repeatClose) {
          pass++;
          i = start;
          continue;
        }
        pass = 1;
      }
      i++;
    }
    return out;
  }

  // ------------------------------------------------------------------ timing

  /// Time the tab against [track]'s audio: Songsterr's sync points for this exact
  /// video if it has them, else for the original recording, else the written tempo.
  TabClock clock(TabSong s, TabPart p, Track track) {
    final n = p.order.length;
    double secsOf(int k) {
      final mi = p.order[k];
      return p.measures[mi].length * p.wholeSecs[mi];
    }

    VideoSync? sync;
    for (final v in s.syncs) {
      if (v.videoId == track.id) sync = v;
    }
    sync ??= s.syncs.where((v) => v.feature == null).firstOrNull;
    sync ??= s.syncs.where((v) => v.feature != 'backing').firstOrNull;
    final usable = sync != null && (sync.points.length - n).abs() <= math.max(4, n ~/ 20);

    final starts = <double>[];
    if (usable) {
      final pts = sync.points;
      for (var k = 0; k < n; k++) {
        starts.add(k < pts.length ? pts[k] : starts[k - 1] + secsOf(k - 1));
      }
      for (var k = 1; k < n; k++) {
        if (starts[k] < starts[k - 1]) starts[k] = starts[k - 1]; // keep monotonic
      }
    } else {
      // written tempo; if it's close to the recording's length, stretch to fit it
      final total = [for (var k = 0; k < n; k++) secsOf(k)].fold(0.0, (a, b) => a + b);
      final dur = track.duration?.toDouble() ?? 0;
      final r = total > 0 && dur > 0 ? dur / total : 1.0;
      final scale = r > .8 && r < 1.25 ? r : 1.0;
      var t = 0.0;
      for (var k = 0; k < n; k++) {
        starts.add(t);
        t += secsOf(k) * scale;
      }
    }
    final off = offsets[track.id] ?? 0;
    final shifted = [for (final x in starts) x + off];
    final ends = [for (var k = 0; k < n; k++) k + 1 < n ? shifted[k + 1] : shifted[k] + secsOf(k)];
    if (n == 0) return TabClock(const [], const [], false);
    return TabClock(shifted, ends, usable);
  }

  void close() => _http.close();
}
