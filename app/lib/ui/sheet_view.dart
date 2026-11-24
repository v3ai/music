import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import '../core/ug.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

const _mono = 'RobotoMono';

/// A tab or chord sheet from Ultimate Guitar. Long lines are re-wrapped at bar lines
/// (tabs) or between words (chords over lyrics) so columns stay lined up on narrow
/// screens, and the sheet scrolls along with the song.
class SheetView extends StatefulWidget {
  const SheetView({super.key, required this.track, required this.version, required this.picker, this.big = false});
  final Track track;
  final UgVersion version;
  final Widget Function(String label) picker;
  final bool big;
  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView> with SingleTickerProviderStateMixin {
  late Future<UgSheet> _sheet = App.ug.sheet(widget.version);
  final _scroll = ScrollController();
  late final Ticker _ticker;
  DateTime _userScrolled = DateTime(2000);
  bool get _follow => App.lib.setting<bool>('sheetAutoScroll', true);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _tick());
    App.player.addListener(_playState);
    _playState();
  }

  void _playState() {
    if (!mounted) return;
    final on = App.player.playing && _follow;
    if (on && !_ticker.isActive) _ticker.start();
    if (!on && _ticker.isActive) _ticker.stop();
  }

  /// Glide toward the spot matching how far through the song we are.
  void _tick() {
    final p = App.player;
    if (p.current?.id != widget.track.id || !_scroll.hasClients) return;
    if (DateTime.now().difference(_userScrolled) < const Duration(seconds: 5)) return;
    final dur = p.duration.inMilliseconds / 1000;
    if (dur <= 0) return;
    final pos = p.position.inMilliseconds / 1000;
    // the first and last bits of a song are usually intro/outro
    final frac = ((pos - math.min(8, dur * .05)) / (dur * .9)).clamp(0.0, 1.0);
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final target = frac * max;
    final cur = _scroll.offset;
    if ((target - cur).abs() < .5) return;
    _scroll.jumpTo(cur + (target - cur) * .06);
  }

  void _toggleFollow() {
    App.lib.setSetting('sheetAutoScroll', !_follow);
    _userScrolled = DateTime(2000);
    setState(_playState);
  }

  @override
  void dispose() {
    App.player.removeListener(_playState);
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UgSheet>(
    future: _sheet,
    builder: (c, s) {
      if (s.hasError) return ErrorMessage(onRetry: () => setState(() => _sheet = App.ug.sheet(widget.version)));
      final sheet = s.data;
      if (sheet == null) return const Loading();
      final v = widget.version;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: widget.picker('${v.kind} · ★ ${v.rating.toStringAsFixed(1)}')),
              ),
              IconBtn(
                Icons.keyboard_double_arrow_down_rounded,
                size: 20,
                active: _follow,
                dot: _follow,
                tooltip: _follow ? 'Stop scrolling with the song' : 'Scroll with the song',
                onTap: _toggleFollow,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: _body(sheet)),
        ],
      );
    },
  );

  Widget _body(UgSheet sheet) => LayoutBuilder(
    builder: (c, box) {
      var size = widget.big ? 14.0 : 12.5;
      double charW(double sz) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'MMMMMMMMMM',
            style: TextStyle(fontFamily: _mono, fontSize: sz),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        return tp.width / 10;
      }

      var cols = ((box.maxWidth - 4) / charW(size)).floor();
      if (cols < 40) {
        size = math.max(10.5, size * cols / 40);
        cols = ((box.maxWidth - 4) / charW(size)).floor();
      }
      final lines = layoutSheet(sheet.content, math.max(20, cols));
      final info = [
        if (sheet.capo > 0) 'Capo ${_ordinal(sheet.capo)} fret',
        if (sheet.tuning != null && sheet.tuning != 'E A D G B E') 'Tuning ${sheet.tuning}',
        if (sheet.key != null && sheet.key!.isNotEmpty) 'Key ${sheet.key}',
      ];
      final items = <Widget>[
        if (info.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              info.join('  ·  '),
              style: const TextStyle(color: C.sub, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        if (sheet.chords.isNotEmpty)
          SizedBox(
            height: 112,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [for (final ch in sheet.chords) Padding(padding: const EdgeInsets.only(right: 14), child: ChordDiagram(ch))],
            ),
          ),
        if (sheet.chords.isNotEmpty) const SizedBox(height: 10),
        for (final l in lines) _line(l, size),
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text('From Ultimate Guitar · ${sheet.version.artist} – ${sheet.version.song}', style: subtle),
        ),
      ];
      return NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          _userScrolled = DateTime.now();
          return false;
        },
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0, .03, .93, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.only(top: 8, bottom: 120),
            itemCount: items.length,
            itemBuilder: (_, i) => items[i],
          ),
        ),
      );
    },
  );

  Widget _line(SheetLine l, double size) {
    if (l.header) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          l.text,
          style: TextStyle(fontSize: size + 1, fontWeight: FontWeight.w800, color: C.text),
        ),
      );
    }
    if (l.text.isEmpty) return SizedBox(height: size * .9);
    final base = TextStyle(fontFamily: _mono, fontSize: size, height: l.tab ? 1.2 : 1.45, color: l.tab ? const Color(0xFFD6D6D6) : C.text);
    const chord = TextStyle(fontWeight: FontWeight.w700, color: Colors.white, backgroundColor: Color(0x1FFFFFFF));
    final spans = <TextSpan>[];
    var at = 0;
    for (final (a, b) in l.chords) {
      if (a > at) spans.add(TextSpan(text: l.text.substring(at, a)));
      spans.add(TextSpan(text: l.text.substring(a, b), style: chord));
      at = b;
    }
    if (at < l.text.length) spans.add(TextSpan(text: l.text.substring(at)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      softWrap: !l.aligned,
    );
  }
}

String _ordinal(int n) => '$n${n % 100 >= 11 && n % 100 <= 13 ? 'th' : const ['th', 'st', 'nd', 'rd', 'th', 'th', 'th', 'th', 'th', 'th'][n % 10]}';

// ---------------------------------------------------------------- layout

/// One display line. [chords] are [start, end) ranges of chord names in [text].
class SheetLine {
  final String text;
  final List<(int, int)> chords;
  final bool tab; // a string line like "e|--3--|"
  final bool aligned; // part of a block whose columns must line up (don't soft-wrap)
  final bool header; // "[Verse 1]"
  const SheetLine(this.text, this.chords, {this.tab = false, this.aligned = false, this.header = false});
}

final _chordRe = RegExp(r'\[ch\](.*?)\[/ch\]');
final _tabLineRe = RegExp(r'^\s*[A-Ga-g][#b]?\s*\|');
final _headerRe = RegExp(r'^\s*\[([^\]]{1,40})\]\s*$');

SheetLine _parse(String raw, {bool aligned = false}) {
  final chords = <(int, int)>[];
  final out = StringBuffer();
  var at = 0;
  for (final m in _chordRe.allMatches(raw)) {
    out.write(raw.substring(at, m.start));
    final start = out.length;
    out.write(m.group(1));
    chords.add((start, out.length));
    at = m.end;
  }
  out.write(raw.substring(at));
  final text = out.toString().replaceAll('\t', '    ').trimRight();
  final h = chords.isEmpty ? _headerRe.firstMatch(text) : null;
  if (h != null) return SheetLine(h.group(1)!.trim(), const [], header: true);
  return SheetLine(text, chords, tab: _tabLineRe.hasMatch(text), aligned: aligned);
}

/// Turn UG markup into display lines no wider than [cols] characters.
List<SheetLine> layoutSheet(String content, int cols) {
  final src = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = <List<SheetLine>>[]; // aligned blocks; free lines are blocks of one
  final tabRe = RegExp(r'\[tab\]([\s\S]*?)\[/tab\]');
  var at = 0;

  void free(String text) {
    // lines outside [tab] tags: group runs of tab-string lines so they wrap together
    List<SheetLine>? run;
    for (final raw in text.split('\n')) {
      final l = _parse(raw);
      if (l.tab) {
        run ??= [];
        run.add(SheetLine(l.text, l.chords, tab: true, aligned: true));
        continue;
      }
      if (run != null) {
        blocks.add(run);
        run = null;
      }
      blocks.add([l]);
    }
    if (run != null) blocks.add(run);
  }

  for (final m in tabRe.allMatches(src)) {
    free(src.substring(at, m.start));
    blocks.add([for (final raw in m.group(1)!.split('\n')) _parse(raw, aligned: true)]);
    at = m.end;
  }
  free(src.substring(at));

  // collapse runs of blank lines, trim leading/trailing blanks
  final out = <SheetLine>[];
  for (final b in blocks) {
    for (final l in (b.length == 1 && !b.first.aligned) ? b : _wrapBlock(b, cols)) {
      if (l.text.isEmpty && !l.header && (out.isEmpty || out.last.text.isEmpty)) continue;
      out.add(l);
    }
  }
  while (out.isNotEmpty && out.last.text.isEmpty) {
    out.removeLast();
  }
  return out;
}

/// Wrap lines that must stay column-aligned, cutting every line at the same columns:
/// at bar lines for tabs, between words for chords over lyrics.
List<SheetLine> _wrapBlock(List<SheetLine> block, int cols) {
  final width = block.fold<int>(0, (m, l) => math.max(m, l.text.length));
  if (width <= cols) return block;
  final tab = block.where((l) => l.tab).firstOrNull;
  // tab lines repeat their string name ("e|") on each wrapped row
  final prefix = tab == null ? 0 : tab.text.indexOf('|') + 1;

  bool canCut(int c) {
    if (tab != null) return c > 0 && c <= tab.text.length && tab.text[c - 1] == '|';
    return block.every((l) => c >= l.text.length || l.text[c] == ' ');
  }

  final cuts = <(int, int)>[];
  var start = 0;
  while (start < width) {
    final room = cols - (start > 0 ? prefix : 0);
    var end = math.min(width, start + room);
    if (end < width) {
      var c = end;
      while (c > start + room ~/ 3 && !canCut(c)) {
        c--;
      }
      if (c > start + room ~/ 3) end = c;
    }
    cuts.add((start, end));
    start = end;
    if (tab == null) {
      while (start < width && block.every((l) => start >= l.text.length || l.text[start] == ' ')) {
        start++; // don't begin a row with spaces
      }
    }
  }

  final out = <SheetLine>[];
  for (var i = 0; i < cuts.length; i++) {
    final (a, b) = cuts[i];
    final rows = <SheetLine>[];
    for (final l in block) {
      final lead = i == 0 || prefix == 0 ? '' : (l.tab ? l.text.substring(0, math.min(prefix, l.text.length)) : ' ' * prefix);
      final from = i == 0 ? a : math.max(a, l.tab ? prefix : 0);
      final body = from < l.text.length ? l.text.substring(from, math.min(b, l.text.length)) : '';
      final shift = lead.length - from;
      final chords = [
        for (final (s, e) in l.chords)
          if (e > from && s < b) (math.max(s, from) + shift, math.min(e, b) + shift),
      ];
      rows.add(SheetLine((lead + body).trimRight(), chords, tab: l.tab, aligned: true));
    }
    // leave out rows with nothing on them (e.g. a lyric line shorter than its chords)
    final kept = rows.where((r) => r.text.trim().isNotEmpty).toList();
    if (kept.isEmpty) continue;
    if (out.isNotEmpty) out.add(const SheetLine('', [], aligned: true));
    out.addAll(kept);
  }
  return out;
}

// ---------------------------------------------------------------- chord diagrams

class ChordDiagram extends StatelessWidget {
  const ChordDiagram(this.shape, {super.key});
  final ChordShape shape;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 66,
    child: Column(
      children: [
        Text(
          shape.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        const SizedBox(height: 4),
        CustomPaint(size: const Size(66, 86), painter: _ChordPainter(shape)),
      ],
    ),
  );
}

class _ChordPainter extends CustomPainter {
  _ChordPainter(this.s);
  final ChordShape s;

  @override
  void paint(Canvas canvas, Size size) {
    final n = s.frets.length;
    if (n < 2) return;
    const rows = 5;
    const left = 12.0, top = 14.0, right = 6.0, bottom = 4.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    final dx = w / (n - 1), dy = h / rows;
    final played = s.frets.where((f) => f > 0).toList();
    final hi = played.isEmpty ? 0 : played.reduce(math.max);
    final lo = played.isEmpty ? 0 : played.reduce(math.min);
    final base = s.baseFret > 1 ? s.baseFret : (hi > rows ? lo : 1);
    final line = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;

    for (var i = 0; i < n; i++) {
      canvas.drawLine(Offset(left + i * dx, top), Offset(left + i * dx, top + h), line);
    }
    for (var r = 0; r <= rows; r++) {
      canvas.drawLine(Offset(left, top + r * dy), Offset(left + w, top + r * dy), line);
    }
    if (base == 1) {
      canvas.drawRect(Rect.fromLTWH(left - .5, top - 2.5, w + 1, 3), Paint()..color = Colors.white);
    } else {
      _text(canvas, '$base', Offset(left - 4, top + dy / 2), 9, C.sub, alignRight: true);
    }
    final dot = Paint()..color = Colors.white;
    for (var i = 0; i < n; i++) {
      final f = s.frets[i];
      final x = left + i * dx;
      if (f < 0) {
        _text(canvas, '×', Offset(x, top - 8), 10, C.sub);
      } else if (f == 0) {
        canvas.drawCircle(
          Offset(x, top - 7),
          2.6,
          Paint()
            ..color = C.sub
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      } else {
        final r = f - base;
        if (r < 0 || r >= rows) continue;
        canvas.drawCircle(Offset(x, top + (r + .5) * dy), math.min(dx, dy) * .36, dot);
      }
    }
  }

  void _text(Canvas c, String t, Offset center, double size, Color color, {bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(alignRight ? center.dx - tp.width : center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChordPainter old) => old.s != s;
}
