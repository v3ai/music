import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart' show ChangeNotifier;

import '../models.dart';
import '../yt/ytm.dart';
import 'images.dart';
import 'library.dart';
import 'proxy.dart';
import 'streams.dart';

enum Repeat { off, all, one }

/// The playback engine: one queue, shuffle/repeat, autoplay radio, and the
/// OS integration (lock screen, notification, media keys) via audio_service.
class Player extends ChangeNotifier {
  Player(this.lib, this.ytm, this.resolver, this.proxy, this.art);

  final Library lib;
  final Ytm ytm;
  final StreamResolver resolver;
  final StreamProxy proxy;
  final AlbumArt art;
  final audio = AudioPlayer(handleInterruptions: true);
  late final MusicHandler handler;

  List<Track> queue = [];
  int index = -1;
  List<Track>? _unshuffled;
  bool shuffle = false;
  Repeat repeat = Repeat.off;
  final autoIds = <String>{}; // songs added by autoplay
  final _userIds = <String>{}; // songs added with "Add to queue"
  String? contextTitle; // "Playing from …"
  String? contextRoute;

  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  bool get autoplay => lib.setting('autoplay', true);
  set autoplay(bool v) {
    lib.setSetting('autoplay', v);
    notifyListeners();
  }

  Track? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get playing => audio.playing;
  bool get loading => audio.processingState == ProcessingState.loading || audio.processingState == ProcessingState.buffering;
  Duration get position => audio.position;
  Duration get duration => audio.duration ?? Duration(seconds: current?.duration ?? 0);
  Stream<Duration> get positionStream => audio.positionStream;
  List<Track> get upNext => index + 1 < queue.length ? queue.sublist(index + 1) : const [];
  bool isUserQueued(String id) => _userIds.contains(id);

  int _loadSeq = 0;
  int _attempt = 0;
  Timer? _saveTimer;

  Future<void> init(MusicHandler h) async {
    handler = h..player = this;
    volume = lib.setting<num>('volume', 1.0).toDouble().clamp(0.0, 1.0);
    await audio.setVolume(_gain(volume));
    audio.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onComplete();
      notifyListeners();
    });
    audio.playbackEventStream.listen((_) => handler.sync(), onError: (Object e, StackTrace _) => _onError(e));
    audio.durationStream.listen((_) {
      handler.sync(mediaChanged: true);
      notifyListeners();
    });
    art.addListener(_artChanged);
    _restore();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (playing) _saveState();
    });
  }

  // ---------------------------------------------------------------- public API

  Future<void> playList(List<Track> tracks, {int start = 0, bool? shuffled, String? context, String? route}) async {
    if (tracks.isEmpty) return;
    lib.remember(tracks);
    queue = List.of(tracks);
    index = start.clamp(0, queue.length - 1);
    autoIds.clear();
    _userIds.clear();
    contextTitle = context;
    contextRoute = route;
    _unshuffled = null;
    if (shuffled != null) shuffle = shuffled;
    if (shuffle) {
      final first = shuffled == true && start == 0 ? queue[Random().nextInt(queue.length)] : queue[index];
      _unshuffled = List.of(queue);
      final rest = List.of(queue)..remove(first);
      rest.shuffle();
      queue = [first, ...rest];
      index = 0;
    }
    await _load();
  }

  /// Play one song, then keep going with similar songs.
  Future<void> playTrack(Track t, {String? context, String? route}) async {
    await playList([t], context: context, route: route);
    _extend(force: true);
  }

  Future<void> startRadio(Track t) async {
    await playList([t], context: '${t.title} Radio');
    _extend(force: true);
  }

  void playNext(List<Track> ts) {
    if (current == null) {
      playList(ts);
      return;
    }
    lib.remember(ts);
    final ids = ts.map((t) => t.id).toSet();
    _removeLater(ids);
    queue.insertAll(index + 1, ts);
    _userIds.addAll(ids);
    _changed();
  }

  void addToQueue(List<Track> ts) {
    if (current == null) {
      playList(ts);
      return;
    }
    lib.remember(ts);
    final ids = ts.map((t) => t.id).toSet();
    _removeLater(ids);
    // after the songs already added by the user, before the rest of the context
    var at = index + 1;
    while (at < queue.length && _userIds.contains(queue[at].id)) {
      at++;
    }
    queue.insertAll(at, ts);
    _userIds.addAll(ids);
    _changed();
  }

  void _removeLater(Set<String> ids) {
    for (var i = queue.length - 1; i > index; i--) {
      if (ids.contains(queue[i].id)) queue.removeAt(i);
    }
  }

  void removeAt(int i) {
    if (i < 0 || i >= queue.length || i == index) return;
    queue.removeAt(i);
    if (i < index) index--;
    _changed();
  }

  void move(int from, int to) {
    if (from == index || from < 0 || from >= queue.length) return;
    final t = queue.removeAt(from);
    if (to > from) to--;
    to = to.clamp(index + 1, queue.length);
    queue.insert(to, t);
    if (from < index) index--;
    _changed();
  }

  void clearUpNext() {
    queue = queue.sublist(0, index + 1);
    _userIds.clear();
    _changed();
  }

  Future<void> jump(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    await _load();
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (current == null) return;
    if (audio.audioSource == null || audio.processingState == ProcessingState.idle) {
      final at = _restorePosition ?? audio.position;
      _restorePosition = null;
      await _load(startAt: at);
      return;
    }
    if (audio.processingState == ProcessingState.completed) await audio.seek(Duration.zero);
    audio.play();
  }

  Future<void> pause() async {
    await audio.pause();
    _saveState();
  }

  Future<void> next() => _advance(user: true);

  Future<void> prev() async {
    if (audio.position > const Duration(seconds: 3) || index <= 0) {
      await seek(Duration.zero);
      if (!playing) play();
      return;
    }
    index--;
    await _load();
  }

  Future<void> seek(Duration d) => audio.seek(d);

  /// Where the volume slider sits, 0..1. Changes show at once; the player catches up.
  double volume = 1;

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    notifyListeners();
    lib.setSetting('volume', volume);
    await audio.setVolume(_gain(volume));
  }

  // Slider position -> what the audio engine wants, so the slider feels the same everywhere:
  // loudness follows position², i.e. half way is -12 dB, a quarter -24 dB. mpv (Linux,
  // Windows) cubes its volume itself; the Android and macOS players take it as is.
  static double _gain(double s) => (Platform.isLinux || Platform.isWindows) ? pow(s, 2 / 3).toDouble() : s * s;

  void toggleShuffle() {
    shuffle = !shuffle;
    final cur = current;
    if (cur == null) {
      notifyListeners();
      return;
    }
    if (shuffle) {
      _unshuffled = List.of(queue);
      final before = queue.sublist(0, index + 1);
      final after = queue.sublist(index + 1)..shuffle();
      queue = [...before, ...after];
    } else if (_unshuffled != null) {
      // keep anything added since shuffling
      final extra = queue.where((t) => !_unshuffled!.contains(t)).toList();
      queue = [..._unshuffled!, ...extra];
      index = queue.indexOf(cur).clamp(0, queue.length - 1);
      _unshuffled = null;
    }
    _changed();
  }

  void cycleRepeat() {
    repeat = Repeat.values[(repeat.index + 1) % Repeat.values.length];
    _changed();
  }

  // ---------------------------------------------------------------- internals

  Future<void> _advance({bool user = false}) async {
    if (current == null) return;
    if (index + 1 < queue.length) {
      index++;
      return _load();
    }
    if (repeat == Repeat.all && queue.isNotEmpty) {
      index = 0;
      return _load();
    }
    if (autoplay) {
      final added = await _extend(force: true);
      if (added > 0) {
        index++;
        return _load();
      }
    }
    // end of the queue
    await audio.pause();
    await audio.seek(Duration.zero);
    notifyListeners();
  }

  void _onComplete() {
    if (repeat == Repeat.one) {
      audio.seek(Duration.zero);
      audio.play();
      return;
    }
    _advance();
  }

  Future<void> _load({Duration? startAt, bool autoplayNow = true, int attempt = 0}) async {
    final t = current;
    if (t == null) return;
    final seq = ++_loadSeq;
    _attempt = attempt;
    lib.remember([t]);
    handler.sync(mediaChanged: true);
    notifyListeners();
    try {
      final source = AudioSource.uri(proxy.urlFor(t.id, attempt: attempt));
      await audio.setAudioSource(source, initialPosition: startAt, preload: true);
      if (seq != _loadSeq) return;
      if (autoplayNow) audio.play();
      if (attempt == 0) lib.played(t);
      _attempt = 0;
    } on PlayerInterruptedException {
      return;
    } catch (e) {
      if (seq != _loadSeq) return;
      _onError(e);
      return;
    }
    // get ready for what's next
    final n = index + 1 < queue.length ? queue[index + 1] : null;
    if (n != null && !lib.isDownloaded(n.id)) resolver.prefetch(n.id);
    if (index >= queue.length - 2 && autoplay && repeat == Repeat.off) _extend();
    if (Ytm.isVideoArt(t.art)) art.artFor(t);
    _saveState();
  }

  void _onError(Object e) {
    final t = current;
    if (t == null) return;
    if (_attempt < 1) {
      // most failures are an expired or blocked link: try once more with a fresh one
      resolver.forget(t.id);
      _load(startAt: audio.position, attempt: _attempt + 1);
      return;
    }
    _errors.add('Couldn’t play “${t.title}”');
    _attempt = 0;
    if (index + 1 < queue.length) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (current == t) next();
      });
    }
  }

  bool _extending = false;

  /// Append similar songs (YouTube Music radio) when the queue is about to run out.
  Future<int> _extend({bool force = false}) async {
    final seed = current;
    if (seed == null || _extending || (!force && !autoplay)) return 0;
    _extending = true;
    try {
      final radio = await ytm.radio(seed.id);
      final have = queue.map((t) => t.id).toSet();
      final add = radio.where((t) => !have.contains(t.id)).take(25).toList();
      if (current != seed && !force) return 0;
      queue.addAll(add);
      autoIds.addAll(add.map((t) => t.id));
      lib.remember(add);
      _changed();
      final n = index + 1 < queue.length ? queue[index + 1] : null;
      if (n != null) resolver.prefetch(n.id);
      return add.length;
    } catch (_) {
      return 0;
    } finally {
      _extending = false;
    }
  }

  void _artChanged() {
    // swap in album covers found for music videos
    var changed = false;
    for (var i = 0; i < queue.length; i++) {
      final up = art.upgrade(queue[i]);
      if (!identical(up, queue[i]) && up.art != queue[i].art) {
        queue[i] = up;
        changed = true;
      }
    }
    if (changed) {
      handler.sync(mediaChanged: true);
      notifyListeners();
    }
  }

  void _changed() {
    handler.sync(mediaChanged: true);
    notifyListeners();
    _saveState();
  }

  void _saveState() {
    if (queue.isEmpty) return;
    // keep the saved queue small: a window around the current song
    final from = max(0, index - 20);
    final to = min(queue.length, index + 100);
    lib.savePlayerState({
      'queue': [for (final t in queue.sublist(from, to)) t.toJson()],
      'index': index - from,
      'position': audio.position.inMilliseconds,
      'shuffle': shuffle,
      'repeat': repeat.name,
      'context': contextTitle,
      'route': contextRoute,
    });
  }

  void _restore() {
    final s = lib.playerState;
    if (s == null) return;
    try {
      queue = [for (final t in (s['queue'] as List)) Track.fromJson(Map<String, dynamic>.from(t))];
      index = (s['index'] as int).clamp(-1, queue.length - 1);
      shuffle = s['shuffle'] ?? false;
      repeat = Repeat.values.firstWhere((r) => r.name == s['repeat'], orElse: () => Repeat.off);
      contextTitle = s['context'];
      contextRoute = s['route'];
      final pos = Duration(milliseconds: s['position'] ?? 0);
      if (current != null) {
        // ready to resume, but don't start playing on launch
        _restorePosition = pos;
        handler.sync(mediaChanged: true);
      }
    } catch (_) {
      queue = [];
      index = -1;
    }
  }

  Duration? _restorePosition;
  Duration get restoredPosition => _restorePosition ?? Duration.zero;

  /// First press of play after launch: load the restored song at its old position.
  Future<void> resume() async {
    final p = _restorePosition;
    _restorePosition = null;
    await _load(startAt: p);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    audio.dispose();
    super.dispose();
  }
}

/// Bridges the player to the OS: notification, lock screen, headset buttons, media keys.
class MusicHandler extends BaseAudioHandler with SeekHandler {
  Player? player;

  @override
  Future<void> play() async {
    final p = player;
    if (p == null) return;
    if (p.audio.audioSource == null) return p.resume();
    return p.play();
  }

  @override
  Future<void> pause() async => player?.pause();
  @override
  Future<void> stop() async => player?.pause();
  @override
  Future<void> seek(Duration position) async => player?.seek(position);
  @override
  Future<void> skipToNext() async => player?.next();
  @override
  Future<void> skipToPrevious() async => player?.prev();
  @override
  Future<void> skipToQueueItem(int index) async => player?.jump(index);
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (player?.playing ?? false) {
          await pause();
        } else {
          await play();
        }
      case MediaButton.next:
        await skipToNext();
      case MediaButton.previous:
        await skipToPrevious();
    }
  }

  String? _lastId;
  String? _lastArt;
  Duration? _lastDuration;

  void sync({bool mediaChanged = false}) {
    final p = player;
    if (p == null) return;
    final t = p.current;
    if (t != null && (mediaChanged || t.id != _lastId)) {
      final d = p.audio.duration ?? (t.duration != null ? Duration(seconds: t.duration!) : null);
      final shownArt = p.art.upgrade(t).art;
      if (t.id != _lastId || shownArt != _lastArt || d != _lastDuration) {
        _lastId = t.id;
        _lastArt = shownArt;
        _lastDuration = d;
        final cover = p.lib.download(t.id)?.cover;
        final a = artUrl(shownArt, 544);
        mediaItem.add(MediaItem(
          id: t.id,
          title: t.title,
          artist: t.artistNames,
          album: t.album?.name ?? '',
          duration: d,
          artUri: cover != null ? Uri.file(cover) : (a == null ? null : Uri.parse(a)),
        ));
      }
    }
    final ps = p.audio.processingState;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (p.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.playPause},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (ps) {
        ProcessingState.idle => t == null ? AudioProcessingState.idle : AudioProcessingState.ready,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: p.playing,
      updatePosition: p.audio.position,
      bufferedPosition: p.audio.bufferedPosition,
      speed: 1,
      queueIndex: p.index < 0 ? null : p.index,
      repeatMode: switch (p.repeat) {
        Repeat.off => AudioServiceRepeatMode.none,
        Repeat.all => AudioServiceRepeatMode.all,
        Repeat.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: p.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }
}
