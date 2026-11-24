import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models.dart';
import '../yt/ytm.dart';
import 'library.dart';
import 'proxy.dart';
import 'streams.dart';

/// Saves songs (audio + cover) onto this device so they play with no connection.
class Downloads {
  Downloads(this.lib, this.resolver, this.proxy, this.ytm, this.dir);

  final Library lib;
  final StreamResolver resolver;
  final StreamProxy proxy;
  final Ytm ytm;
  final Directory dir;

  final _queue = <String>[];
  final _active = <String>{};
  static const _parallel = 2;

  void start() {
    for (final e in lib.downloads.entries) {
      if (e.value.status == DlStatus.queued) _queue.add(e.key);
      // files deleted behind our back
      if (e.value.status == DlStatus.done && (e.value.path == null || !File(e.value.path!).existsSync())) {
        e.value.status = DlStatus.queued;
        _queue.add(e.key);
      }
    }
    _pump();
  }

  void add(List<Track> tracks) {
    lib.remember(tracks);
    for (final t in tracks) {
      final s = lib.download(t.id);
      if (s != null && s.status != DlStatus.error) continue;
      lib.setDownload(t.id, DownloadState());
      _queue.add(t.id);
    }
    _pump();
  }

  Future<void> remove(String id) async {
    _queue.remove(id);
    final s = lib.download(id);
    lib.setDownload(id, null);
    for (final p in [s?.path, s?.cover]) {
      if (p != null) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }
  }

  int get pending => _queue.length + _active.length;

  void _pump() {
    while (_active.length < _parallel && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      if (_active.contains(id)) continue;
      _active.add(id);
      _one(id).whenComplete(() {
        _active.remove(id);
        _pump();
      });
    }
  }

  Future<void> _one(String id) async {
    final state = lib.download(id);
    var t = lib.track(id);
    if (state == null || t == null) return;
    state
      ..status = DlStatus.downloading
      ..progress = 0
      ..error = null;
    lib.setDownload(id, state);
    try {
      await dir.create(recursive: true);
      // videos: use the album cover if we can find one
      if (Ytm.isVideoArt(t.art)) {
        final m = await ytm.matchSong(t).catchError((_) => null);
        lib.storeArtMatch(id, m);
        if (m != null) t = t.copyWith(art: m.art, album: t.album ?? m.album);
        lib.remember([t]);
      }
      final info = await resolver.resolve(id);
      final file = File('${dir.path}/$id.${info.ext}');
      final part = File('${file.path}.part');
      var last = DateTime.now();
      await proxy.download(id, part, (p) {
        state.progress = p;
        if (DateTime.now().difference(last).inMilliseconds > 250) {
          last = DateTime.now();
          lib.downloadProgress();
        }
      });
      await part.rename(file.path);
      String? cover;
      final artUrlStr = artUrl(t.art, 544);
      if (artUrlStr != null) {
        try {
          final r = await http.get(Uri.parse(artUrlStr)).timeout(const Duration(seconds: 20));
          if (r.statusCode == 200) {
            final f = File('${dir.path}/$id.jpg');
            await f.writeAsBytes(r.bodyBytes);
            cover = f.path;
          }
        } catch (_) {}
      }
      state
        ..status = DlStatus.done
        ..progress = 1
        ..path = file.path
        ..cover = cover
        ..size = await file.length();
      if (lib.download(id) == null) {
        // removed while downloading
        await file.delete().catchError((_) => file);
        return;
      }
      lib.setDownload(id, state);
    } catch (e) {
      if (lib.download(id) == null) return;
      state
        ..status = DlStatus.error
        ..error = e.toString().split('\n').first;
      lib.setDownload(id, state);
    }
  }

  Future<int> usedBytes() async {
    var n = 0;
    for (final d in lib.downloads.values) {
      n += d.size ?? 0;
    }
    return n;
  }
}
