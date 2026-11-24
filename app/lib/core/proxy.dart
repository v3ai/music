import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'streams.dart';

/// A tiny HTTP server on 127.0.0.1 that the audio player streams from.
///
/// YouTube throttles or rejects open-ended requests for audio, so this fetches
/// the stream in ranged chunks and hands the player a normal seekable file.
/// Downloaded songs are served straight from disk.
class StreamProxy {
  StreamProxy(this.resolver, {required this.localFile});

  final StreamResolver resolver;

  /// Path of a downloaded copy of a song, if there is one.
  final String? Function(String videoId) localFile;

  static const _chunk = 2 * 1024 * 1024;
  final _http = http.Client();
  HttpServer? _server;

  int get port => _server!.port;

  Uri urlFor(String videoId, {int attempt = 0}) =>
      Uri.parse('http://127.0.0.1:$port/stream/$videoId${attempt > 0 ? '?r=$attempt' : ''}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) => _handle(req).catchError((_) {}));
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final seg = req.uri.pathSegments;
    if (seg.length != 2 || seg[0] != 'stream' || (req.method != 'GET' && req.method != 'HEAD')) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    final id = seg[1];
    final head = req.method == 'HEAD';
    final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader));

    final path = localFile(id);
    if (path != null && File(path).existsSync()) {
      return _serveFile(res, File(path), range, head);
    }

    StreamInfo info;
    try {
      info = await resolver.resolve(id, fresh: req.uri.queryParameters.containsKey('r'));
    } catch (e) {
      res.statusCode = HttpStatus.badGateway;
      res.write(e.toString());
      return res.close();
    }

    final size = info.size;
    final start = range?.$1 ?? 0;
    final end = (range?.$2 == null || range!.$2! >= size) ? size - 1 : range.$2!;
    if (start >= size) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      return res.close();
    }
    res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
    res.headers
      ..contentType = ContentType.parse(info.mime)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    if (range != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
    if (head) return res.close();

    var pos = start;
    var refreshed = false;
    try {
      while (pos <= end) {
        final to = (pos + _chunk - 1).clamp(pos, end);
        final up = http.Request('GET', info.url)
          ..headers.addAll(info.headers)
          ..headers['range'] = 'bytes=$pos-$to';
        final r = await _http.send(up).timeout(const Duration(seconds: 20));
        if (r.statusCode == 403 && !refreshed) {
          // the link expired or was revoked: get a new one and carry on
          await r.stream.drain<void>();
          refreshed = true;
          info = await resolver.resolve(id, fresh: true);
          continue;
        }
        if (r.statusCode != 206 && r.statusCode != 200) throw HttpException('upstream ${r.statusCode}');
        await for (final data in r.stream) {
          res.add(data);
          pos += data.length;
        }
        await res.flush();
      }
    } catch (e) {
      // client went away (seek/skip) or upstream failed; the player will retry
      resolver.forget(id);
    } finally {
      await res.close().catchError((_) {});
    }
  }

  Future<void> _serveFile(HttpResponse res, File f, (int, int?)? range, bool head) async {
    final size = await f.length();
    final start = range?.$1 ?? 0;
    final end = (range?.$2 == null || range!.$2! >= size) ? size - 1 : range.$2!;
    res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
    res.headers
      ..contentType = ContentType.parse(f.path.endsWith('.webm') ? 'audio/webm' : 'audio/mp4')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    if (range != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
    if (!head) await res.addStream(f.openRead(start, end + 1)).catchError((_) {});
    await res.close().catchError((_) {});
  }

  static (int, int?)? _parseRange(String? h) {
    if (h == null) return null;
    final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(h);
    if (m == null) return null;
    final s = int.tryParse(m.group(1)!) ?? 0;
    final e = int.tryParse(m.group(2)!);
    return (s, e);
  }

  /// Fetch a whole stream to a file (for downloads), reporting progress 0..1.
  Future<void> download(String videoId, File out, void Function(double) progress) async {
    var info = await resolver.resolve(videoId);
    final sink = out.openWrite();
    var pos = 0;
    var refreshed = false;
    try {
      while (pos < info.size) {
        final to = (pos + _chunk - 1).clamp(pos, info.size - 1);
        final r = await _http
            .send(http.Request('GET', info.url)
              ..headers.addAll(info.headers)
              ..headers['range'] = 'bytes=$pos-$to')
            .timeout(const Duration(seconds: 30));
        if (r.statusCode == 403 && !refreshed) {
          await r.stream.drain<void>();
          refreshed = true;
          info = await resolver.resolve(videoId, fresh: true);
          continue;
        }
        if (r.statusCode != 206 && r.statusCode != 200) throw HttpException('download failed (${r.statusCode})');
        await for (final data in r.stream) {
          sink.add(data);
          pos += data.length;
        }
        progress(pos / info.size);
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _http.close();
  }
}
