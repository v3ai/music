import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class StreamInfo {
  final Uri url;
  final int size;
  final String mime;
  final String ext;
  final DateTime expires;
  final Map<String, String> headers; // send these when fetching [url]
  StreamInfo(this.url, this.size, this.mime, this.ext, this.expires, this.headers);
  bool get fresh => DateTime.now().isBefore(expires);
}

/// One YouTube app identity to ask for streams as. YouTube treats clients differently
/// (some need sign-in or tokens), so we keep a list and use the first that works.
class PlayerClient {
  final String name;
  final String version;
  final int id;
  final String userAgent;
  final Map<String, dynamic> extra;
  const PlayerClient(this.name, this.version, this.id, this.userAgent, [this.extra = const {}]);

  factory PlayerClient.fromJson(Map<String, dynamic> j) => PlayerClient(
        j['clientName'],
        j['clientVersion'],
        j['clientId'],
        j['userAgent'],
        Map<String, dynamic>.from(j['extra'] ?? const {}),
      );
}

const _defaultClients = [
  PlayerClient('VISIONOS', '1.02', 101, 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15', {
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice17,1',
    'osName': 'visionOS',
    'osVersion': '26.5.23O471',
  }),
];

/// Finds the audio stream for a YouTube video, on the device, with no account.
/// Results are cached until shortly before YouTube's link expires; concurrent
/// lookups for the same video share one request.
class StreamResolver {
  StreamResolver({this.configFile});

  /// Where an updated client list is cached (see [refreshClients]).
  final File? configFile;

  static const _webUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const configUrl = 'https://raw.githubusercontent.com/v3ai/music/main/app/clients.json';

  final _http = http.Client();
  final _cache = <String, StreamInfo>{};
  final _pending = <String, Future<StreamInfo>>{};
  List<PlayerClient> _clients = List.of(_defaultClients);
  Future<String?>? _visitor;
  DateTime _visitorAt = DateTime(2000);

  /// Use the newest client list: cached copy now, then the published one in the background.
  /// This lets playback be fixed for everyone (by updating clients.json in the repo)
  /// when YouTube changes something, without shipping a new app.
  Future<void> refreshClients() async {
    final f = configFile;
    try {
      if (f != null && await f.exists()) _apply(await f.readAsString());
    } catch (_) {}
    try {
      final r = await _http.get(Uri.parse(configUrl)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && _apply(r.body) && f != null) await f.writeAsString(r.body);
    } catch (_) {}
  }

  bool _apply(String body) {
    try {
      final j = jsonDecode(body);
      final list = [for (final c in (j['clients'] as List)) PlayerClient.fromJson(Map<String, dynamic>.from(c))];
      if (list.isEmpty) return false;
      _clients = list;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<StreamInfo> resolve(String videoId, {bool fresh = false}) {
    if (!fresh) {
      final hit = _cache[videoId];
      if (hit != null && hit.fresh) return Future.value(hit);
      final p = _pending[videoId];
      if (p != null) return p;
    }
    final f = _resolve(videoId).whenComplete(() {
      _pending.remove(videoId);
    });
    _pending[videoId] = f;
    return f;
  }

  /// Warm the cache for a song that is about to play.
  void prefetch(String videoId) => resolve(videoId).ignore();

  void forget(String videoId) => _cache.remove(videoId);

  Future<String?> _visitorData({bool renew = false}) {
    if (renew || _visitor == null || DateTime.now().difference(_visitorAt) > const Duration(hours: 6)) {
      _visitorAt = DateTime.now();
      _visitor = () async {
        try {
          final r = await _http
              .get(Uri.parse('https://www.youtube.com/'), headers: {'user-agent': _webUa, 'accept-language': 'en-US,en;q=0.9'})
              .timeout(const Duration(seconds: 10));
          return RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(r.body)?.group(1);
        } catch (_) {
          _visitorAt = DateTime(2000);
          return null;
        }
      }();
    }
    return _visitor!;
  }

  Future<StreamInfo> _resolve(String videoId) async {
    Object? lastError;
    for (final c in _clients) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final info = await _player(videoId, c, renewVisitor: attempt > 0);
          _cache[videoId] = info;
          if (_cache.length > 200) _cache.remove(_cache.keys.first);
          return info;
        } on _Retry catch (e) {
          lastError = e.reason;
          continue; // new visitor id, same client
        } catch (e) {
          lastError = e;
          break; // next client
        }
      }
    }
    throw StreamException(videoId, lastError);
  }

  Future<StreamInfo> _player(String videoId, PlayerClient c, {bool renewVisitor = false}) async {
    final visitor = await _visitorData(renew: renewVisitor);
    final r = await _http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: {
            'content-type': 'application/json',
            'user-agent': c.userAgent,
            'origin': 'https://www.youtube.com',
            'x-youtube-client-name': '${c.id}',
            'x-youtube-client-version': c.version,
            'x-goog-visitor-id': ?visitor,
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': c.name,
                'clientVersion': c.version,
                'userAgent': c.userAgent,
                'hl': 'en',
                'visitorData': ?visitor,
                ...c.extra,
              },
            },
            'videoId': videoId,
            'playbackContext': {
              'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
            },
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw HttpException('player ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final status = j['playabilityStatus']?['status'];
    if (status == 'LOGIN_REQUIRED' && !renewVisitor) throw _Retry('sign-in check');
    if (status != 'OK') throw StateError(j['playabilityStatus']?['reason'] ?? status ?? 'unplayable');

    final formats = [
      for (final f in (j['streamingData']?['adaptiveFormats'] as List? ?? const []))
        if (f is Map && (f['mimeType'] as String? ?? '').startsWith('audio/') && f['url'] != null && f['contentLength'] != null) f,
    ];
    if (formats.isEmpty) throw StateError('no audio');
    // AAC in MP4 plays everywhere; then the highest bitrate
    formats.sort((a, b) {
      final am = (a['mimeType'] as String).startsWith('audio/mp4') ? 1 : 0;
      final bm = (b['mimeType'] as String).startsWith('audio/mp4') ? 1 : 0;
      if (am != bm) return bm - am;
      return ((b['bitrate'] ?? 0) as num).compareTo((a['bitrate'] ?? 0) as num);
    });
    final f = formats.first;
    final url = Uri.parse(f['url']);
    final mp4 = (f['mimeType'] as String).startsWith('audio/mp4');
    final expireParam = int.tryParse(url.queryParameters['expire'] ?? '');
    final expires = expireParam != null
        ? DateTime.fromMillisecondsSinceEpoch(expireParam * 1000).subtract(const Duration(minutes: 10))
        : DateTime.now().add(const Duration(hours: 4));
    return StreamInfo(url, int.parse('${f['contentLength']}'), mp4 ? 'audio/mp4' : 'audio/webm', mp4 ? 'm4a' : 'webm', expires, {'user-agent': c.userAgent});
  }

  void close() => _http.close();
}

class _Retry implements Exception {
  final String reason;
  _Retry(this.reason);
}

class StreamException implements Exception {
  final String videoId;
  final Object? cause;
  StreamException(this.videoId, this.cause);
  @override
  String toString() => 'Could not play $videoId: ${cause.toString().split('\n').first}';
}
