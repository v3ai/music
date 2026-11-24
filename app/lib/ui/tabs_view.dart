import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import '../core/tabs.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Guitar/bass tablature for [track] that scrolls along with the song.
/// Tap a bar to jump there.
class TabsView extends StatefulWidget {
  const TabsView({super.key, required this.track, this.big = false});
  final Track track;
  final bool big;
  @override
  State<TabsView> createState() => _TabsViewState();
}

class _TabsViewState extends State<TabsView> with SingleTickerProviderStateMixin {
  late Future<TabSong?> _song;
  Future<TabPart>? _part;
  TabPart? _shown;
  TabClock? _clock;
  TabSong? _s;
  int _err = 0;

  final _scroll = ScrollController();
  final _now = ValueNotifier<double>(0); // playback position, seconds
  late final Ticker _ticker;
  DateTime _userScrolled = DateTime(2000);
  int _sysShown = -1;
  _Layout? _layout;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = createTicker((_) => _tick());
    App.player.addListener(_playState);
    _playState();
  }

  // animate only while music plays; otherwise just catch up once (e.g. after a seek)
  void _playState() {
    if (!mounted) return;
    if (App.player.playing) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      _tick();
    }
  }

  @override
  void didUpdateWidget(TabsView old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      _load();
    }
  }

  void _load() {
    _shown = null;
    _clock = null;
    _s = null;
    _part = null;
    _layout = null;
    _sysShown = -1;
    _song = App.tabs.find(widget.track).then((s) {
      _s = s;
      if (s != null) _part = App.tabs.defaultPart(s).then(_setPart);
      return s;
    });
  }

  TabPart _setPart(TabPart p) {
    if (!mounted) return p;
    setState(() {
      _shown = p;
      _clock = App.tabs.clock(_s!, p, widget.track);
      _layout = null;
      _sysShown = -1;
    });
    return p;
  }

  void _choosePart(TabPartInfo info) {
    final s = _s;
    if (s == null) return;
    setState(() => _part = App.tabs.part(s, info).then(_setPart));
  }

  void _nudge(double by) {
    final id = widget.track.id;
    final v = ((App.tabs.offsets[id] ?? 0) + by);
    App.tabs.offsets[id] = (v * 10).round() / 10;
    if (_s != null && _shown != null) setState(() => _clock = App.tabs.clock(_s!, _shown!, widget.track));
  }

  void _tick() {
    final p = App.player;
    if (p.current?.id != widget.track.id) return;
    final t = p.position.inMilliseconds / 1000;
    if ((t - _now.value).abs() > 0.004) _now.value = t;
    _follow(t);
  }

  void _follow(double t) {
    final c = _clock, l = _layout, part = _shown;
    if (c == null || l == null || part == null || !_scroll.hasClients) return;
    final k = c.indexAt(t);
    final sys = k < 0 ? 0 : l.systemOf[part.order[k]];
    if (sys == _sysShown) return;
    _sysShown = sys;
    if (DateTime.now().difference(_userScrolled) < const Duration(seconds: 4)) return;
    final view = _scroll.position.viewportDimension;
    final target = (l.top + sys * l.sysH - view * .22).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  void _tapMeasure(int mi) {
    final c = _clock, part = _shown;
    if (c == null || part == null) return;
    // the play of that bar nearest to where we are now (bars can repeat)
    final now = _now.value;
    var best = -1;
    var bestD = double.infinity;
    for (var k = 0; k < part.order.length; k++) {
      if (part.order[k] != mi) continue;
      final d = (c.starts[k] - now).abs();
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    if (best < 0) return;
    _userScrolled = DateTime(2000);
    final p = App.player;
    if (p.current?.id == widget.track.id) {
      p.seek(Duration(milliseconds: (math.max(0, c.starts[best]) * 1000).round())).then((_) => _tick());
    }
  }

  @override
  void dispose() {
    App.player.removeListener(_playState);
    _ticker.dispose();
    _scroll.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TabSong?>(
    key: ValueKey('${widget.track.id}#$_err'),
    future: _song,
    builder: (c, s) {
      if (s.hasError) {
        return ErrorMessage(
          onRetry: () => setState(() {
            _err++;
            _load();
          }),
        );
      }
      if (s.connectionState != ConnectionState.done) return const Loading();
      final song = s.data;
      if (song == null) {
        return const Message(icon: Icons.music_off_rounded, title: 'No tab for this song', text: 'There isn’t a guitar tab for this one yet.');
      }
      return FutureBuilder<TabPart>(
        future: _part,
        builder: (c, ps) {
          if (ps.hasError && _shown == null) {
            return ErrorMessage(
              onRetry: () => setState(() {
                _err++;
                _load();
              }),
            );
          }
          final part = _shown;
          if (part == null) return const Loading();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, song, part),
              const SizedBox(height: 8),
              Expanded(child: _body(part)),
            ],
          );
        },
      );
    },
  );

  Widget _header(BuildContext context, TabSong song, TabPart part) {
    final off = App.tabs.offsets[widget.track.id] ?? 0;
    final synced = _clock?.synced ?? false;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (bc) => InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  final box = bc.findRenderObject() as RenderBox?;
                  showActions(
                    context,
                    position: box?.localToGlobal(box.size.bottomLeft(Offset.zero)),
                    actions: [
                      for (final p in song.parts.where((p) => p.kind != 'vocals'))
                        MenuAction(
                          p.index == part.info.index ? Icons.check_rounded : (p.kind == 'bass' ? Icons.graphic_eq_rounded : Icons.music_note_rounded),
                          '${p.label} · ${p.tuningName}',
                          () => _choosePart(p),
                        ),
                    ],
                  );
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                  decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${part.info.label} · ${part.info.tuningName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded, size: 20, color: C.sub),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: synced ? 'Timed to the recording. Nudge if it’s off.' : 'Timed from the written tempo. Nudge to line it up.',
          child: Text(
            off == 0 ? (synced ? 'Sync' : 'Tempo') : '${off > 0 ? '+' : ''}${off.toStringAsFixed(1)}s',
            style: const TextStyle(color: C.sub, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        IconBtn(Icons.remove_rounded, size: 18, tooltip: 'Tab earlier', onTap: () => _nudge(-.5)),
        IconBtn(Icons.add_rounded, size: 18, tooltip: 'Tab later', onTap: () => _nudge(.5)),
      ],
    );
  }

  Widget _body(TabPart part) => LayoutBuilder(
    builder: (c, box) {
      final style = _Style(widget.big);
      final l = _layout != null && _layout!.width == box.maxWidth ? _layout! : (_layout = _Layout.build(part, box.maxWidth, style));
      if (_sysShown == -1) WidgetsBinding.instance.addPostFrameCallback((_) => _follow(_now.value));
      return NotificationListener<ScrollStartNotification>(
        onNotification: (n) {
          if (n.dragDetails != null) _userScrolled = DateTime.now();
          return false;
        },
        child: NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            _userScrolled = DateTime.now();
            return false;
          },
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0, .04, .92, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.only(top: l.top, bottom: 160),
              itemExtent: l.sysH,
              itemCount: l.systems.length,
              itemBuilder: (_, i) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final mi = l.systems[i].measureAt(d.localPosition.dx);
                  if (mi != null) _tapMeasure(mi);
                },
                child: CustomPaint(size: Size(box.maxWidth, l.sysH), painter: _SystemPainter(part, l, i, _now, _clock, style)),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------- layout

class _Style {
  _Style(this.big) : sp = big ? 15 : 13, font = big ? 13 : 11.5;
  final bool big;
  final double sp; // distance between strings
  final double font;
  static const gutter = 20.0;
  static const markerH = 20.0;
  static const gap = 22.0; // between systems
}

class _MBox {
  _MBox(this.index, this.x, this.w, this.beatX);
  final int index;
  double x, w;
  List<double> beatX; // left edge of each beat's slot, relative to x
}

class _System {
  _System(this.ms);
  final List<_MBox> ms;
  int? measureAt(double dx) {
    for (final m in ms) {
      if (dx >= m.x && dx < m.x + m.w) return m.index;
    }
    return null;
  }
}

class _Layout {
  _Layout(this.width, this.systems, this.systemOf, this.sysH, this.top);
  final double width;
  final List<_System> systems;
  final List<int> systemOf; // measure index -> system index
  final double sysH;
  final double top;

  static double _beatW(double len, bool big) => big ? 9 + 58 * math.sqrt(len) : 5 + 43 * math.sqrt(len);

  static _Layout build(TabPart p, double width, _Style st) {
    final avail = math.max(120.0, width - _Style.gutter - 2);
    final systems = <_System>[];
    final systemOf = List.filled(p.measures.length, 0);
    var line = <_MBox>[];
    var used = 0.0;

    void flush({bool last = false}) {
      if (line.isEmpty) return;
      // stretch to fill the line (not the final short one)
      final fill = avail / used;
      if (!last || used > avail * .7) {
        for (final m in line) {
          m.w *= fill;
          m.beatX = [for (final b in m.beatX) b * fill];
        }
      }
      var x = _Style.gutter;
      for (final m in line) {
        m.x = x;
        x += m.w;
        systemOf[m.index] = systems.length;
      }
      systems.add(_System(line));
      line = [];
      used = 0;
    }

    for (var i = 0; i < p.measures.length; i++) {
      final m = p.measures[i];
      double w;
      List<double> bx;
      if (m.empty || m.beats.isEmpty) {
        w = st.big ? 46 : 34;
        bx = [for (var j = 0; j < m.beats.length; j++) 10.0];
      } else {
        bx = [];
        var x = st.big ? 10.0 : 7.0;
        for (final b in m.beats) {
          bx.add(x);
          x += _beatW(b.length, st.big);
        }
        w = x + 4;
      }
      if (w > avail) {
        // a very busy bar on a narrow screen: squeeze it
        final f = avail / w;
        bx = [for (final b in bx) b * f];
        w = avail;
      }
      if (used + w > avail && line.isNotEmpty) flush();
      line.add(_MBox(i, 0, w, bx));
      used += w;
    }
    flush(last: true);

    final strings = p.strings;
    final sysH = _Style.markerH + (strings - 1) * st.sp + _Style.gap + 10;
    return _Layout(width, systems, systemOf, sysH, 8);
  }
}

// ---------------------------------------------------------------- painting

class _SystemPainter extends CustomPainter {
  _SystemPainter(this.part, this.layout, this.index, this.now, this.clock, this.st) : super(repaint: now);
  final TabPart part;
  final _Layout layout;
  final int index;
  final ValueNotifier<double> now;
  final TabClock? clock;
  final _Style st;

  static final _texts = <String, TextPainter>{};

  TextPainter _text(String s, double size, Color color, {FontWeight weight = FontWeight.w700}) {
    final key = '$s|$size|${color.toARGB32()}|${weight.value}';
    return _texts.putIfAbsent(key, () {
      if (_texts.length > 3000) _texts.clear();
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: size, color: color, fontWeight: weight, fontFeatures: const [FontFeature.tabularFigures()], height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sys = layout.systems[index];
    final strings = part.strings;
    final y0 = _Style.markerH + 4;
    double yOf(int s) => y0 + s * st.sp;
    final left = _Style.gutter;
    final right = sys.ms.last.x + sys.ms.last.w;
    final lineP = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1;
    final barP = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;

    // where is playback?
    final c = clock;
    var curM = -1;
    var frac = 0.0;
    if (c != null) {
      final k = c.indexAt(now.value);
      if (k >= 0 && k < part.order.length) {
        curM = part.order[k];
        frac = c.fraction(k, now.value);
      }
    }

    // current bar highlight
    for (final m in sys.ms) {
      if (m.index != curM) continue;
      final r = RRect.fromRectAndRadius(Rect.fromLTRB(m.x, y0 - 10, m.x + m.w, yOf(strings - 1) + 10), const Radius.circular(6));
      canvas.drawRRect(r, Paint()..color = const Color(0x17FFFFFF));
    }

    // tuning letters
    for (var s = 0; s < strings; s++) {
      final tp = _text(noteName(part.info.tuning[s]), st.font - 2, C.faint, weight: FontWeight.w600);
      tp.paint(canvas, Offset(2, yOf(s) - tp.height / 2));
    }

    // note positions per string, to leave gaps in the lines behind the numbers
    final gaps = List.generate(strings, (_) => <(double, double)>[]);
    final labels = <(Offset, TextPainter)>[];
    for (final m in sys.ms) {
      final meas = part.measures[m.index];
      final active = m.index == curM ? _activeBeat(meas, frac) : -1;
      for (var j = 0; j < meas.beats.length; j++) {
        final b = meas.beats[j];
        final x = m.x + m.beatX[j];
        for (final n in b.notes) {
          if (n.string < 0 || n.string >= strings) continue;
          final lbl = _label(n, meas, j);
          final on = j == active;
          final tp = _text(lbl, st.font, on ? Colors.black : (n.ghost || n.tie ? C.sub : C.text));
          final w = tp.width;
          final y = yOf(n.string);
          gaps[n.string].add((x - 2, x + w + 2));
          if (on) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x - 3, y - tp.height / 2 - 2.5, w + 6, tp.height + 5), const Radius.circular(4)),
              Paint()..color = Colors.white,
            );
          }
          labels.add((Offset(x, y - tp.height / 2), tp));
        }
      }
    }

    // strings
    for (var s = 0; s < strings; s++) {
      final y = yOf(s);
      final g = gaps[s]..sort((a, b) => a.$1.compareTo(b.$1));
      var x = left;
      for (final (a, b) in g) {
        if (a > x) canvas.drawLine(Offset(x, y), Offset(a, y), lineP);
        x = math.max(x, b);
      }
      if (x < right) canvas.drawLine(Offset(x, y), Offset(right, y), lineP);
    }

    // bars, markers, numbers
    for (final m in sys.ms) {
      final meas = part.measures[m.index];
      canvas.drawLine(Offset(m.x, yOf(0)), Offset(m.x, yOf(strings - 1)), barP);
      if (meas.repeatStart) _dots(canvas, m.x + 4, yOf, strings);
      if (meas.repeatClose > 0) {
        _dots(canvas, m.x + m.w - 4, yOf, strings);
        if (meas.repeatClose > 2) {
          final tp = _text('×${meas.repeatClose}', st.font - 2, C.sub);
          tp.paint(canvas, Offset(m.x + m.w - tp.width - 2, y0 - 8 - tp.height));
        }
      }
      if (meas.marker != null) {
        final tp = _text(meas.marker!, st.font, C.text, weight: FontWeight.w800);
        tp.paint(canvas, Offset(m.x + 2, 0));
      } else if (m == sys.ms.first) {
        final tp = _text('${m.index + 1}', st.font - 3, C.faint, weight: FontWeight.w600);
        tp.paint(canvas, Offset(m.x + 2, y0 - 8 - tp.height));
      }
      if (meas.endings.isNotEmpty) {
        final tp = _text('${meas.endings.join(', ')}.', st.font - 2, C.sub);
        tp.paint(canvas, Offset(m.x + 4, y0 - 8 - tp.height));
      }
      if (meas.sigChanged && m.index > 0 || m.index == 0 && (meas.sigNum != 4 || meas.sigDen != 4)) {
        final tp = _text('${meas.sigNum}/${meas.sigDen}', st.font - 2, C.sub);
        tp.paint(canvas, Offset(m.x + m.w - tp.width - 4, y0 - 8 - tp.height));
      }
    }
    canvas.drawLine(Offset(right, yOf(0)), Offset(right, yOf(strings - 1)), barP);

    for (final (o, tp) in labels) {
      tp.paint(canvas, o);
    }

    // playhead
    for (final m in sys.ms) {
      if (m.index != curM) continue;
      final meas = part.measures[m.index];
      final x = m.x + _xAt(meas, m, frac);
      canvas.drawLine(
        Offset(x, y0 - 9),
        Offset(x, yOf(strings - 1) + 9),
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _dots(Canvas canvas, double x, double Function(int) yOf, int strings) {
    final mid = (yOf(0) + yOf(strings - 1)) / 2;
    final p = Paint()..color = const Color(0x99FFFFFF);
    canvas.drawCircle(Offset(x, mid - st.sp * .6), 1.8, p);
    canvas.drawCircle(Offset(x, mid + st.sp * .6), 1.8, p);
  }

  String _label(TabNote n, TabMeasure m, int j) {
    if (n.dead) return 'x';
    var s = '${n.fret}';
    if (n.harmonic) s = '<$s>';
    if (n.ghost || n.tie) s = '($s)';
    if (n.bend) s = '${s}b';
    if (n.slide) s = '$s/';
    if (n.hp) {
      // hammer-on if the next note on this string is higher, pull-off if lower
      for (var k = j + 1; k < m.beats.length; k++) {
        final next = m.beats[k].notes.where((x) => x.string == n.string).firstOrNull;
        if (next != null) {
          s = '$s${next.fret >= n.fret ? 'h' : 'p'}';
          break;
        }
      }
    }
    return s;
  }

  /// Beat playing at [frac] through the bar.
  int _activeBeat(TabMeasure m, double frac) {
    final t = frac * m.length;
    var acc = 0.0;
    for (var j = 0; j < m.beats.length; j++) {
      acc += m.beats[j].length;
      if (t < acc - 1e-6) return m.beats[j].notes.isEmpty ? -1 : j;
    }
    return -1;
  }

  double _xAt(TabMeasure m, _MBox box, double frac) {
    if (m.beats.isEmpty || box.beatX.length != m.beats.length) return box.w * frac;
    final t = frac * m.length;
    var acc = 0.0;
    for (var j = 0; j < m.beats.length; j++) {
      final len = m.beats[j].length;
      if (t < acc + len || j == m.beats.length - 1) {
        final x0 = box.beatX[j];
        final x1 = j + 1 < box.beatX.length ? box.beatX[j + 1] : box.w - 4;
        final f = len <= 0 ? 0.0 : ((t - acc) / len).clamp(0.0, 1.0);
        return x0 + (x1 - x0) * f;
      }
      acc += len;
    }
    return box.w * frac;
  }

  @override
  bool shouldRepaint(_SystemPainter old) => old.part != part || old.layout != layout || old.index != index || old.clock != clock;
}
