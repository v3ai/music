import 'dart:convert';
import 'package:http/http.dart' as http;

/// Minimal client for YouTube Music's internal API ("InnerTube", WEB_REMIX client).
/// No account, no API key: the same anonymous requests music.youtube.com makes.
class InnerTube {
  InnerTube({this.hl = 'en', this.gl = 'US', http.Client? client}) : _http = client ?? http.Client();

  final String hl;
  final String gl;
  final http.Client _http;
  String? visitorData;

  static const _base = 'https://music.youtube.com/youtubei/v1/';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  String get _clientVersion {
    final d = DateTime.now().toUtc().subtract(const Duration(days: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    return '1.${d.year}${two(d.month)}${two(d.day)}.01.00';
  }

  Map<String, dynamic> get _context => {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': _clientVersion,
          'hl': hl,
          'gl': gl,
          if (visitorData != null) 'visitorData': visitorData,
        },
        'user': {},
      };

  Future<Map<String, dynamic>> call(String endpoint, Map<String, dynamic> body, {String? query}) async {
    final uri = Uri.parse('$_base$endpoint?prettyPrint=false${query ?? ''}');
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await _http
            .post(uri,
                headers: {
                  'content-type': 'application/json',
                  'user-agent': _ua,
                  'origin': 'https://music.youtube.com',
                  'referer': 'https://music.youtube.com/',
                  'x-youtube-client-name': '67',
                  'x-youtube-client-version': _clientVersion,
                  'x-goog-visitor-id': ?visitorData,
                },
                body: jsonEncode({'context': _context, ...body}))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode >= 500 || r.statusCode == 429) {
          lastError = 'HTTP ${r.statusCode}';
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        if (r.statusCode != 200) throw InnerTubeException('HTTP ${r.statusCode} from $endpoint');
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        visitorData ??= nav(j, ['responseContext', 'visitorData']);
        return j;
      } on InnerTubeException {
        rethrow;
      } catch (e) {
        lastError = e;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw InnerTubeException('Network error: $lastError');
  }

  Future<Map<String, dynamic>> browse(String browseId, {String? params}) =>
      call('browse', {'browseId': browseId, 'params': ?params});

  Future<Map<String, dynamic>> continuation(String token) =>
      call('browse', {}, query: '&ctoken=$token&continuation=$token&type=next');

  Future<Map<String, dynamic>> continuationCommand(String endpoint, String token) =>
      call(endpoint, {'continuation': token});

  Future<Map<String, dynamic>> search(String query, {String? params}) =>
      call('search', {'query': query, 'params': ?params});

  Future<Map<String, dynamic>> next({required String videoId, String? playlistId, String? params}) => call('next', {
        'videoId': videoId,
        'playlistId': playlistId ?? 'RDAMVM$videoId',
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
        'params': ?params,
      });

  Future<Map<String, dynamic>> suggestions(String input) => call('music/get_search_suggestions', {'input': input});

  void close() => _http.close();
}

class InnerTubeException implements Exception {
  final String message;
  InnerTubeException(this.message);
  @override
  String toString() => message;
}

/// Walk a decoded JSON tree: nav(j, ['a', 0, 'b']). Returns null if any step is missing.
dynamic nav(dynamic root, List path) {
  var cur = root;
  for (final k in path) {
    if (cur == null) return null;
    if (k is int) {
      if (cur is List && k >= 0 && k < cur.length) {
        cur = cur[k];
      } else if (cur is List && k < 0 && cur.length + k >= 0) {
        cur = cur[cur.length + k];
      } else {
        return null;
      }
    } else {
      if (cur is Map) {
        cur = cur[k];
      } else {
        return null;
      }
    }
  }
  return cur;
}
