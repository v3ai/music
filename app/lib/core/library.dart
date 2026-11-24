import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart' show ChangeNotifier;

import '../models.dart';

class LocalPlaylist {
  final String id;
  String name;
  String description;
  final List<String> trackIds;
  final int created;
  int updated;
  LocalPlaylist({required this.id, required this.name, this.description = '', List<String>? trackIds, int? created, int? updated})
      : trackIds = trackIds ?? [],
        created = created ?? DateTime.now().millisecondsSinceEpoch,
        updated = updated ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'description': description, 'tracks': trackIds, 'created': created, 'updated': updated};
  factory LocalPlaylist.fromJson(Map<String, dynamic> j) => LocalPlaylist(
        id: j['id'],
        name: j['name'] ?? 'Playlist',
        description: j['description'] ?? '',
        trackIds: List<String>.from(j['tracks'] ?? const []),
        created: j['created'],
        updated: j['updated'],
      );
}

enum DlStatus { queued, downloading, done, error }

class DownloadState {
  DlStatus status;
  double progress;
  String? path; // audio file
  String? cover; // cover image file
  int? size;
  String? error;
  final int added;
  DownloadState({this.status = DlStatus.queued, this.progress = 0, this.path, this.cover, this.size, this.error, int? added})
      : added = added ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() =>
      {'status': status.name, 'progress': progress, 'path': path, 'cover': cover, 'size': size, 'error': error, 'added': added};
  factory DownloadState.fromJson(Map<String, dynamic> j) => DownloadState(
        status: DlStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => DlStatus.error),
        progress: (j['progress'] ?? 0).toDouble(),
        path: j['path'],
        cover: j['cover'],
        size: j['size'],
        error: j['error'],
        added: j['added'],
      );
}

/// A saved album / artist / YouTube Music playlist.
class SavedItem {
  final String kind; // album | artist | playlist
  final Item item;
  final int added;
  SavedItem(this.kind, this.item, [int? added]) : added = added ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'added': added,
        'item': switch (item) {
          AlbumCard a => a.toJson(),
          ArtistCard a => a.toJson(),
          PlaylistCard p => p.toJson(),
          Track t => t.toJson(),
        },
      };
  static SavedItem? fromJson(Map<String, dynamic> j) {
    final m = Map<String, dynamic>.from(j['item'] ?? const {});
    final Item? item = switch (j['kind']) {
      'album' => AlbumCard.fromJson(m),
      'artist' => ArtistCard.fromJson(m),
      'playlist' => PlaylistCard.fromJson(m),
      _ => null,
    };
    return item == null ? null : SavedItem(j['kind'], item, j['added']);
  }
}

/// Everything the user owns: likes, playlists, saved items, downloads, history, settings.
/// Stored as one JSON file, written shortly after each change.
class Library extends ChangeNotifier {
  Library(this.dir);

  final Directory dir;
  File get _file => File('${dir.path}/library.json');

  final tracks = <String, Track>{}; // metadata for every track referenced below
  final liked = <String>[]; // newest first
  final playlists = <LocalPlaylist>[];
  final saved = <SavedItem>[];
  final downloads = <String, DownloadState>{};
  final history = <(String, int)>[]; // (trackId, playedAt ms), newest first
  final recentSearches = <String>[];
  final artMatches = <String, (String?, AlbumRef?, int)>{}; // videoId -> (album art, album, checkedAt)
  final settings = <String, dynamic>{'autoplay': true, 'volume': 1.0};
  Map<String, dynamic>? playerState;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      for (final t in (j['tracks'] as Map? ?? const {}).values) {
        final tr = Track.fromJson(Map<String, dynamic>.from(t));
        tracks[tr.id] = tr;
      }
      liked.addAll(List<String>.from(j['liked'] ?? const []));
      for (final p in (j['playlists'] as List? ?? const [])) {
        playlists.add(LocalPlaylist.fromJson(Map<String, dynamic>.from(p)));
      }
      for (final s in (j['saved'] as List? ?? const [])) {
        final si = SavedItem.fromJson(Map<String, dynamic>.from(s));
        if (si != null) saved.add(si);
      }
      (j['downloads'] as Map? ?? const {}).forEach((k, v) {
        final d = DownloadState.fromJson(Map<String, dynamic>.from(v));
        // interrupted downloads restart
        if (d.status == DlStatus.downloading) d.status = DlStatus.queued;
        downloads[k] = d;
      });
      for (final h in (j['history'] as List? ?? const [])) {
        history.add((h[0] as String, h[1] as int));
      }
      recentSearches.addAll(List<String>.from(j['recentSearches'] ?? const []));
      (j['artMatches'] as Map? ?? const {}).forEach((k, v) {
        artMatches[k] = (v['art'], v['album'] == null ? null : AlbumRef.fromJson(Map<String, dynamic>.from(v['album'])), v['t'] ?? 0);
      });
      settings.addAll(Map<String, dynamic>.from(j['settings'] ?? const {}));
      playerState = j['player'] == null ? null : Map<String, dynamic>.from(j['player']);
    } catch (e) {
      // corrupt file: keep a copy, start fresh
      try {
        await _file.copy('${_file.path}.broken');
      } catch (_) {}
    }
  }

  Timer? _saveTimer;
  void _changed({bool notify = true}) {
    if (notify) notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), save);
  }

  /// Persist now (also called on app pause/exit).
  Future<void> save() async {
    _saveTimer?.cancel();
    // only keep metadata that something still refers to
    final used = <String>{
      ...liked,
      for (final p in playlists) ...p.trackIds,
      ...downloads.keys,
      for (final h in history) h.$1,
      ...?(playerState?['queue'] as List?)?.map((t) => t['id'] as String),
    };
    tracks.removeWhere((k, _) => !used.contains(k));
    final j = {
      'version': 1,
      'tracks': {for (final t in tracks.values) t.id: t.toJson()},
      'liked': liked,
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'saved': saved.map((s) => s.toJson()).toList(),
      'downloads': downloads.map((k, v) => MapEntry(k, v.toJson())),
      'history': [for (final h in history) [h.$1, h.$2]],
      'recentSearches': recentSearches,
      'artMatches': artMatches.map((k, v) => MapEntry(k, {'art': v.$1, 'album': v.$2?.toJson(), 't': v.$3})),
      'settings': settings,
      'player': playerState,
    };
    try {
      await dir.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(j), flush: true);
      await tmp.rename(_file.path);
    } catch (_) {}
  }

  void remember(Iterable<Track> ts) {
    for (final t in ts) {
      final old = tracks[t.id];
      // never replace a real cover with a video frame
      if (old != null && t.art != null && t.art!.contains('i.ytimg.com') && old.art != null && !old.art!.contains('i.ytimg.com')) {
        continue;
      }
      tracks[t.id] = t;
    }
  }

  Track? track(String id) => tracks[id];
  List<Track> tracksFor(Iterable<String> ids) => [for (final id in ids) if (tracks[id] != null) tracks[id]!];

  // ---------- likes

  bool isLiked(String id) => liked.contains(id);
  List<Track> get likedTracks => tracksFor(liked);

  bool toggleLike(Track t, [bool? on]) {
    on ??= !isLiked(t.id);
    liked.remove(t.id);
    if (on) {
      remember([t]);
      liked.insert(0, t.id);
    }
    _changed();
    return on;
  }

  // ---------- playlists

  static String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  LocalPlaylist? playlist(String id) => playlists.where((p) => p.id == id).firstOrNull;

  LocalPlaylist createPlaylist(String name, [List<Track> initial = const []]) {
    final p = LocalPlaylist(id: _newId(), name: name.trim().isEmpty ? 'My Playlist #${playlists.length + 1}' : name.trim());
    playlists.insert(0, p);
    addToPlaylist(p.id, initial);
    _changed();
    return p;
  }

  /// Returns how many were added (duplicates are skipped).
  int addToPlaylist(String pid, List<Track> ts) {
    final p = playlist(pid);
    if (p == null) return 0;
    remember(ts);
    var n = 0;
    for (final t in ts) {
      if (!p.trackIds.contains(t.id)) {
        p.trackIds.add(t.id);
        n++;
      }
    }
    p.updated = DateTime.now().millisecondsSinceEpoch;
    _touchPlaylist(p);
    _changed();
    return n;
  }

  void removeFromPlaylist(String pid, String tid) {
    final p = playlist(pid);
    if (p == null) return;
    p.trackIds.remove(tid);
    p.updated = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  /// Move a track; [to] is its index after the move.
  void reorderPlaylist(String pid, int from, int to) {
    final p = playlist(pid);
    if (p == null) return;
    final id = p.trackIds.removeAt(from);
    p.trackIds.insert(to.clamp(0, p.trackIds.length), id);
    p.updated = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  void renamePlaylist(String pid, String name, [String? description]) {
    final p = playlist(pid);
    if (p == null) return;
    p.name = name.trim().isEmpty ? p.name : name.trim();
    if (description != null) p.description = description;
    p.updated = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  void deletePlaylist(String pid) {
    playlists.removeWhere((p) => p.id == pid);
    _changed();
  }

  void _touchPlaylist(LocalPlaylist p) {
    playlists.remove(p);
    playlists.insert(0, p);
  }

  List<String> playlistCovers(LocalPlaylist p) {
    final out = <String>[];
    for (final id in p.trackIds) {
      final a = tracks[id]?.art;
      if (a != null && !out.contains(a)) out.add(a);
      if (out.length == 4) break;
    }
    return out;
  }

  // ---------- saved albums / artists / playlists

  bool isSaved(String kind, String id) => saved.any((s) => s.kind == kind && s.item.id == id);

  bool toggleSave(String kind, Item item, [bool? on]) {
    on ??= !isSaved(kind, item.id);
    saved.removeWhere((s) => s.kind == kind && s.item.id == item.id);
    if (on) saved.insert(0, SavedItem(kind, item));
    _changed();
    return on;
  }

  // ---------- downloads (state only; the work happens in Downloads)

  DownloadState? download(String id) => downloads[id];
  bool isDownloaded(String id) => downloads[id]?.status == DlStatus.done;
  String? localFile(String id) {
    final d = downloads[id];
    return d?.status == DlStatus.done ? d!.path : null;
  }

  List<Track> get downloadedTracks {
    final ids = downloads.entries.toList()..sort((a, b) => b.value.added.compareTo(a.value.added));
    return tracksFor(ids.map((e) => e.key));
  }

  void setDownload(String id, DownloadState? s, {bool notify = true}) {
    if (s == null) {
      downloads.remove(id);
    } else {
      downloads[id] = s;
    }
    _changed(notify: notify);
  }

  void downloadProgress() => notifyListeners();

  // ---------- history

  void played(Track t) {
    remember([t]);
    history.removeWhere((h) => h.$1 == t.id);
    history.insert(0, (t.id, DateTime.now().millisecondsSinceEpoch));
    if (history.length > 300) history.removeRange(300, history.length);
    _changed();
  }

  List<Track> recentTracks([int n = 30]) => tracksFor(history.take(n).map((h) => h.$1));

  void addSearch(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    recentSearches.remove(q);
    recentSearches.insert(0, q);
    if (recentSearches.length > 20) recentSearches.removeLast();
    _changed();
  }

  void removeSearch(String q) {
    recentSearches.remove(q);
    _changed();
  }

  void clearSearches() {
    recentSearches.clear();
    _changed();
  }

  // ---------- album art for videos

  void storeArtMatch(String videoId, Track? song) {
    artMatches[videoId] = (song?.art, song?.album, DateTime.now().millisecondsSinceEpoch);
    if (song != null) {
      final t = tracks[videoId];
      if (t != null) tracks[videoId] = t.copyWith(art: song.art, album: t.album ?? song.album);
    }
    _changed(notify: false);
  }

  /// Known album cover for a video: (found?, art, album). Misses are re-checked after a week.
  (bool, String?, AlbumRef?) artMatch(String videoId) {
    final m = artMatches[videoId];
    if (m == null) return (false, null, null);
    if (m.$1 == null && DateTime.now().millisecondsSinceEpoch - m.$3 > 7 * 86400000) return (false, null, null);
    return (true, m.$1, m.$2);
  }

  // ---------- settings / player state

  T setting<T>(String key, T fallback) => (settings[key] as T?) ?? fallback;
  void setSetting(String key, Object? value) {
    settings[key] = value;
    _changed();
  }

  void savePlayerState(Map<String, dynamic> s) {
    playerState = s;
    _changed(notify: false);
  }
}
