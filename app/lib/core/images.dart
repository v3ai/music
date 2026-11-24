import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../yt/ytm.dart';
import 'library.dart';

/// Artwork from the network, cached on disk so it shows instantly (and offline) next time.
class NetArt extends ImageProvider<NetArt> {
  const NetArt(this.url);
  final String url;

  static late Directory dir;
  static final _client = http.Client();
  static int _running = 0;
  static final _waiting = Queue<Completer<void>>();

  @override
  Future<NetArt> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(NetArt key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0, debugLabel: url);

  static String _name(String s) {
    // FNV-1a 64-bit: short, stable file names
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final f = File('${dir.path}/${_name(url)}');
    Uint8List? bytes;
    if (await f.exists()) {
      bytes = await f.readAsBytes();
    } else {
      bytes = await _fetch(url);
      // 16:9 video frames: not every video has the HD frame
      if (bytes == null && url.contains('/hq720.jpg')) bytes = await _fetch(url.replaceFirst('/hq720.jpg', '/mqdefault.jpg'));
      if (bytes == null) throw StateError('image failed: $url');
      try {
        await dir.create(recursive: true);
        await f.writeAsBytes(bytes, flush: false);
      } catch (_) {}
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  static Future<Uint8List?> _fetch(String url) async {
    // a few at a time: Google rate-limits bursts of image requests
    if (_running >= 6) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
          if (r.statusCode == 404) return null;
        } catch (_) {}
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  static Future<int> cacheSize() async {
    var n = 0;
    try {
      await for (final e in dir.list()) {
        if (e is File) n += await e.length();
      }
    } catch (_) {}
    return n;
  }

  static Future<void> clear() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    PaintingBinding.instance.imageCache.clear();
  }

  @override
  bool operator ==(Object other) => other is NetArt && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

/// Music videos come with a video frame as their picture. This finds the album the
/// song is on and swaps in the real cover, everywhere the song appears.
class AlbumArt extends ChangeNotifier {
  AlbumArt(this.lib, this.ytm);
  final Library lib;
  final Ytm ytm;
  final _inflight = <String>{};
  int _running = 0;
  final _waiting = Queue<Track>();

  /// The best known art for [t]; schedules a lookup for videos.
  String? artFor(Track t) {
    if (!Ytm.isVideoArt(t.art)) return t.art;
    final m = lib.artMatch(t.id);
    if (m.$1) return m.$2 ?? t.art;
    if (_inflight.add(t.id)) {
      _waiting.add(t);
      _pump();
    }
    return t.art;
  }

  /// The track with its album cover (and album) filled in, if known.
  Track upgrade(Track t) {
    if (!Ytm.isVideoArt(t.art)) return t;
    final m = lib.artMatch(t.id);
    if (m.$1 && m.$2 != null) return t.copyWith(art: m.$2, album: t.album ?? m.$3);
    return t;
  }

  void _pump() {
    while (_running < 3 && _waiting.isNotEmpty) {
      final t = _waiting.removeFirst();
      _running++;
      ytm.matchSong(t).then((m) => lib.storeArtMatch(t.id, m), onError: (_) {}).whenComplete(() {
        _running--;
        _inflight.remove(t.id);
        _scheduleNotify();
        _pump();
      });
    }
  }

  Timer? _t;
  void _scheduleNotify() {
    _t ??= Timer(const Duration(milliseconds: 150), () {
      _t = null;
      notifyListeners();
    });
  }
}

/// An image for any artwork URL (or a downloaded cover file), with a quiet placeholder.
Widget artImage(String? url, {double? size, BoxFit fit = BoxFit.cover, int px = 240, String? localFile}) {
  ImageProvider? provider;
  if (localFile != null && File(localFile).existsSync()) {
    provider = FileImage(File(localFile));
  } else {
    final u = artUrl(url, px);
    if (u != null) provider = NetArt(u);
  }
  final ph = Container(
    width: size,
    height: size,
    color: const Color(0xFF282828),
    alignment: Alignment.center,
    child: Icon(Icons.music_note_rounded, color: const Color(0xFF7A7A7A), size: size == null ? 32 : size * .4),
  );
  if (provider == null) return ph;
  return Image(
    image: provider,
    width: size,
    height: size,
    fit: fit,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    frameBuilder: (context, child, frame, sync) => sync || frame != null
        ? child
        : Stack(fit: StackFit.passthrough, children: [ph, AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 200), child: child)]),
    errorBuilder: (_, _, _) => ph,
  );
}
