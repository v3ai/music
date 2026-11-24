import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import '../core/library.dart';
import '../core/player.dart';
import '../models.dart';
import 'nav.dart';
import 'tabs_view.dart';
import 'theme.dart';
import 'widgets.dart';

final queueOpen = ValueNotifier<bool>(false);

// ---------------------------------------------------------------- progress

class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.compact = false});
  final bool compact;
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = App.player;
    return StreamBuilder<Duration>(
      stream: p.positionStream,
      builder: (context, _) {
        final dur = p.duration;
        final pos = p.audio.audioSource == null ? p.restoredPosition : p.position;
        final max = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
        final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
        final slider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: widget.compact ? 4 : 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: p.current == null ? null : (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              p.seek(Duration(milliseconds: v.round()));
              setState(() => _drag = null);
            },
          ),
        );
        final cur = Text(fmtTime(Duration(milliseconds: value.round())), style: const TextStyle(fontSize: 11.5, color: C.sub, fontFeatures: [ui.FontFeature.tabularFigures()]));
        final total = Text(fmtTime(dur), style: const TextStyle(fontSize: 11.5, color: C.sub, fontFeatures: [ui.FontFeature.tabularFigures()]));
        if (widget.compact) {
          return Row(children: [SizedBox(width: 40, child: Align(alignment: Alignment.centerRight, child: cur)), Expanded(child: slider), SizedBox(width: 40, child: total)]);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 28, child: slider),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [cur, total])),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- controls

class Controls extends StatelessWidget {
  const Controls({super.key, this.big = false});
  final bool big;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: App.player,
        builder: (_, _) {
          final p = App.player;
          final has = p.current != null;
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconBtn(Icons.shuffle_rounded, size: big ? 26 : 20, active: p.shuffle, dot: p.shuffle, tooltip: p.shuffle ? 'Disable shuffle' : 'Enable shuffle', onTap: p.toggleShuffle),
            SizedBox(width: big ? 18 : 8),
            IconBtn(Icons.skip_previous_rounded, size: big ? 42 : 28, color: C.text, tooltip: 'Previous', onTap: has ? p.prev : null),
            SizedBox(width: big ? 18 : 8),
            _ToggleButton(size: big ? 68 : 36),
            SizedBox(width: big ? 18 : 8),
            IconBtn(Icons.skip_next_rounded, size: big ? 42 : 28, color: C.text, tooltip: 'Next', onTap: has ? p.next : null),
            SizedBox(width: big ? 18 : 8),
            IconBtn(p.repeat == Repeat.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                size: big ? 26 : 20,
                active: p.repeat != Repeat.off,
                dot: p.repeat != Repeat.off,
                tooltip: switch (p.repeat) { Repeat.off => 'Enable repeat', Repeat.all => 'Enable repeat one', Repeat.one => 'Disable repeat' },
                onTap: p.cycleRepeat),
          ]);
        },
      );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = App.player;
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: p.current == null ? null : p.toggle,
        child: SizedBox(
          width: size,
          height: size,
          child: p.loading && p.playing
              ? Padding(padding: EdgeInsets.all(size * .3), child: const CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
              : Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: size * .6),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- desktop player bar

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 84,
        child: ListenableBuilder(
          listenable: App.player,
          builder: (context, _) {
            final p = App.player;
            final t = p.current;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: t == null
                      ? const SizedBox()
                      : Row(children: [
                          GestureDetector(onTap: () => openNowPlaying(context), child: MouseRegion(cursor: SystemMouseCursors.click, child: TrackArt(t, size: 56))),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              InkWell(
                                onTap: t.album?.id != null ? () => Nav.album(t.album!.id!) : () => openNowPlaying(context),
                                child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              ),
                              const SizedBox(height: 3),
                              ArtistLinks(t.artists, style: subtle.copyWith(fontSize: 12)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          LikeButton(t, size: 18),
                        ]),
                ),
                Expanded(
                  flex: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Controls(), SizedBox(height: 2), SeekBar(compact: true)]),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    IconBtn(Icons.lyrics_outlined, size: 18, tooltip: 'Lyrics', onTap: t == null ? null : () => openNowPlaying(context, lyrics: true)),
                    TabsButton(size: 20, onTap: t == null ? null : () => openNowPlaying(context, tabs: true)),
                    ValueListenableBuilder(
                      valueListenable: queueOpen,
                      builder: (_, open, _) => IconBtn(Icons.queue_music_rounded, size: 20, active: open, dot: open, tooltip: 'Queue', onTap: () => queueOpen.value = !queueOpen.value),
                    ),
                    const _Volume(),
                    IconBtn(Icons.open_in_full_rounded, size: 18, tooltip: 'Full screen', onTap: t == null ? null : () => openNowPlaying(context)),
                  ]),
                ),
              ]),
            );
          },
        ),
      );
}

class _Volume extends StatefulWidget {
  const _Volume();
  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double _before = 1;
  @override
  Widget build(BuildContext context) {
    final v = App.player.audio.volume;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconBtn(
        v == 0 ? Icons.volume_off_rounded : (v < .5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
        size: 20,
        tooltip: v == 0 ? 'Unmute' : 'Mute',
        onTap: () {
          if (v > 0) {
            _before = v;
            App.player.setVolume(0);
          } else {
            App.player.setVolume(_before == 0 ? 1 : _before);
          }
        },
      ),
      SizedBox(
        width: 110,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
          child: Slider(value: v.clamp(0, 1), onChanged: (x) => App.player.setVolume(x)),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- mobile mini player

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: App.player,
        builder: (context, _) {
          final p = App.player;
          final t = p.current;
          if (t == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: GestureDetector(
              onTap: () => openNowPlaying(context),
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < -200) openNowPlaying(context);
              },
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300) p.next();
                if (v > 300) p.prev();
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: const Color(0xFF2B2B2B),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                      child: Row(children: [
                        TrackArt(t, size: 42),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtle.copyWith(fontSize: 12.5)),
                          ]),
                        ),
                        LikeButton(t, size: 24),
                        IconButton(
                          onPressed: p.toggle,
                          icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
                          tooltip: p.playing ? 'Pause' : 'Play',
                        ),
                      ]),
                    ),
                    StreamBuilder<Duration>(
                      stream: p.positionStream,
                      builder: (_, _) {
                        final d = p.duration.inMilliseconds;
                        final pos = (p.audio.audioSource == null ? p.restoredPosition : p.position).inMilliseconds;
                        return LinearProgressIndicator(value: d <= 0 ? 0 : (pos / d).clamp(0, 1), minHeight: 2, backgroundColor: const Color(0x33FFFFFF), color: Colors.white);
                      },
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

// ---------------------------------------------------------------- now playing

void openNowPlaying(BuildContext context, {bool lyrics = false, bool tabs = false}) {
  if (App.player.current == null) return;
  Nav.rootKey.currentState!.push(PageRouteBuilder(
    settings: const RouteSettings(name: 'now'),
    opaque: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => NowPlaying(panel: tabs ? 'tabs' : (lyrics ? 'lyrics' : 'art')),
    transitionsBuilder: (_, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key, this.panel = 'art'});
  final String panel; // art | lyrics | tabs | queue
  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  late String _panel = widget.panel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.player, App.art, App.lib]),
      builder: (context, _) {
        final p = App.player;
        final t0 = p.current;
        if (t0 == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
          return const ColoredBox(color: C.bg);
        }
        final t = App.art.upgrade(t0);
        final wide = MediaQuery.sizeOf(context).width >= 1000;
        return Scaffold(
          backgroundColor: C.bg,
          body: Stack(fit: StackFit.expand, children: [
            _Backdrop(t),
            SafeArea(child: wide ? _wide(context, t) : _narrow(context, t)),
          ]),
        );
      },
    );
  }

  Widget _head(BuildContext context, Track t) {
    final p = App.player;
    return Row(children: [
      IconBtn(Icons.keyboard_arrow_down_rounded, size: 32, color: C.text, tooltip: 'Close', onTap: () => Navigator.of(context).maybePop()),
      Expanded(
        child: InkWell(
          onTap: p.contextRoute == null ? null : () => Nav.openRoute(p.contextRoute),
          child: Column(children: [
            const Text('PLAYING FROM', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: C.sub, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(p.contextTitle ?? (p.autoIds.contains(t.id) ? 'Autoplay' : 'Your queue'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
        ),
      ),
      Builder(builder: (bc) => IconBtn(Icons.more_horiz_rounded, size: 26, color: C.text, tooltip: 'More', onTap: () {
            final box = bc.findRenderObject() as RenderBox?;
            showTrackMenu(context, t, position: box?.localToGlobal(box.size.bottomLeft(Offset.zero)));
          })),
    ]);
  }

  Widget _meta(Track t) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: t.album?.id == null ? null : () => Nav.album(t.album!.id!),
              child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            ),
            const SizedBox(height: 4),
            ArtistLinks(t.artists, style: const TextStyle(fontSize: 16, color: C.sub)),
          ]),
        ),
        LikeButton(t, size: 28),
      ]);

  Widget _bottomActions(Track t) {
    final d = App.lib.download(t.id);
    return Row(children: [
      IconBtn(
        d?.status == DlStatus.done ? Icons.download_done_rounded : Icons.download_rounded,
        size: 24,
        active: d?.status == DlStatus.done,
        tooltip: d == null ? 'Download' : 'Remove download',
        onTap: () {
          if (d == null || d.status == DlStatus.error) {
            App.downloads.add([t]);
            Nav.toast('Downloading');
          } else {
            App.downloads.remove(t.id);
            Nav.toast('Download removed');
          }
        },
      ),
      const Spacer(),
      IconBtn(Icons.lyrics_outlined, size: 24, active: _panel == 'lyrics', dot: _panel == 'lyrics', tooltip: 'Lyrics', onTap: () => setState(() => _panel = _panel == 'lyrics' ? 'art' : 'lyrics')),
      const SizedBox(width: 8),
      TabsButton(size: 24, active: _panel == 'tabs', onTap: () => setState(() => _panel = _panel == 'tabs' ? 'art' : 'tabs')),
      const SizedBox(width: 8),
      IconBtn(Icons.queue_music_rounded, size: 24, active: _panel == 'queue', dot: _panel == 'queue', tooltip: 'Queue', onTap: () => setState(() => _panel = _panel == 'queue' ? 'art' : 'queue')),
    ]);
  }

  Widget _narrow(BuildContext context, Track t) {
    final stage = switch (_panel) {
      'lyrics' => LyricsView(track: t),
      'tabs' => TabsView(track: t),
      'queue' => const QueueView(),
      _ => Center(
          child: LayoutBuilder(builder: (c, box) {
            final s = box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight;
            return GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300) App.player.next();
                if (v > 300) App.player.prev();
              },
              child: TrackArt(t, size: s, radius: 8, px: 1200),
            );
          }),
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(children: [
        _head(context, t),
        const SizedBox(height: 16),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: stage)),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _meta(t)),
        const SizedBox(height: 8),
        const SeekBar(),
        const SizedBox(height: 4),
        const Controls(big: true),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _bottomActions(t)),
      ]),
    );
  }

  Widget _wide(BuildContext context, Track t) {
    final side = switch (_panel) {
      'queue' => const QueueView(),
      'tabs' => TabsView(track: t, big: true),
      _ => LyricsView(track: t, big: true),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(children: [
        _head(context, t),
        const SizedBox(height: 16),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(builder: (c, box) {
                  final s = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight).clamp(200.0, 640.0);
                  return TrackArt(t, size: s, radius: 8, px: 1200);
                }),
              ),
            ),
            const SizedBox(width: 48),
            Expanded(child: side),
          ]),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(children: [
            _meta(t),
            const SizedBox(height: 8),
            const SeekBar(),
            const SizedBox(height: 4),
            Stack(alignment: Alignment.center, children: [
              const Controls(big: true),
              Positioned(left: 0, right: 0, child: _bottomActions(t)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Blurred, darkened album art behind the now-playing screen.
class _Backdrop extends StatelessWidget {
  const _Backdrop(this.t);
  final Track t;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.decal),
          child: Opacity(opacity: .55, child: TrackArt(t, size: 600, radius: 0, px: 240)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0xE6000000), C.bg]),
          ),
        ),
      ]);
}

// ---------------------------------------------------------------- lyrics

class LyricsView extends StatelessWidget {
  const LyricsView({super.key, required this.track, this.big = false});
  final Track track;
  final bool big;
  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics?>(
        key: ValueKey(track.id),
        future: App.ytm.lyrics(track.id),
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Loading();
          final l = s.data;
          if (l == null) {
            return const Message(icon: Icons.lyrics_outlined, title: 'No lyrics for this song', text: 'Lyrics aren’t available for this one.');
          }
          return ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0, .06, .9, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 24), children: [
              SelectableText(l.text, style: TextStyle(fontSize: big ? 26 : 22, fontWeight: FontWeight.w700, height: 1.5, color: C.text, letterSpacing: -.2)),
              if (l.source != null) Padding(padding: const EdgeInsets.only(top: 24), child: Text('Lyrics from ${l.source}', style: subtle)),
            ]),
          );
        },
      );
}

// ---------------------------------------------------------------- queue

class QueueView extends StatelessWidget {
  const QueueView({super.key, this.panel = false});
  final bool panel;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([App.player, App.art]),
        builder: (context, _) {
          final p = App.player;
          final cur = p.current;
          if (cur == null) return const Message(icon: Icons.queue_music_rounded, title: 'Your queue is empty', text: 'Play something to get started.');
          final up = <int>[];
          for (var i = p.index + 1; i < p.queue.length; i++) {
            up.add(i);
          }
          final user = up.where((i) => p.isUserQueued(p.queue[i].id)).toList();
          final ctx = up.where((i) => !p.isUserQueued(p.queue[i].id) && !p.autoIds.contains(p.queue[i].id)).toList();
          final auto = up.where((i) => !p.isUserQueued(p.queue[i].id) && p.autoIds.contains(p.queue[i].id)).toList();

          Widget row(int i) => Dismissible(
                key: ValueKey('q${p.queue[i].id}$i'),
                direction: DismissDirection.endToStart,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: C.hover, child: const Icon(Icons.remove_circle_outline_rounded)),
                onDismissed: (_) => p.removeAt(i),
                child: TrackTile(track: p.queue[i], onPlay: () => p.jump(i)),
              );

          Widget head(String text, {Widget? trailing}) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 0, 6),
                child: Row(children: [Expanded(child: Text(text, style: titleM, maxLines: 1, overflow: TextOverflow.ellipsis)), ?trailing]),
              );

          return ListView(padding: EdgeInsets.symmetric(horizontal: panel ? 8 : 0, vertical: 8), children: [
            head('Now playing'),
            TrackTile(track: cur, onPlay: p.toggle),
            if (user.isNotEmpty) ...[
              head('Next in queue', trailing: TextButton(onPressed: p.clearUpNext, child: const Text('Clear queue', style: TextStyle(color: C.sub, fontWeight: FontWeight.w700)))),
              for (final i in user) row(i),
            ],
            if (ctx.isNotEmpty) ...[head('Next from: ${p.contextTitle ?? 'your queue'}'), for (final i in ctx.take(100)) row(i)],
            head('Autoplay', trailing: Switch(value: p.autoplay, onChanged: (v) => p.autoplay = v)),
            if (p.autoplay && auto.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(left: 4, bottom: 6), child: Text('Similar songs will keep playing', style: subtle)),
              for (final i in auto.take(50)) row(i),
            ],
            if (!p.autoplay) const Padding(padding: EdgeInsets.only(left: 4), child: Text('Turn on to keep listening to similar songs when your music ends.', style: subtle)),
          ]);
        },
      );
}
