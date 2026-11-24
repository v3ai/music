import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import '../core/images.dart';
import '../core/library.dart';
import '../models.dart';
import 'nav.dart';
import 'theme.dart';

bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 760;

String fmtTime(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
}

String fmtLong(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h hr $m min';
  return '$m min ${seconds % 60} sec';
}

String songs(int n) => n == 1 ? '1 song' : '$n songs';

String fmtBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Rebuild when any of the app's state changes (library, player, artwork).
class Watch extends StatelessWidget {
  const Watch({super.key, required this.builder, this.player = true, this.lib = true, this.art = false});
  final WidgetBuilder builder;
  final bool player, lib, art;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([if (player) App.player, if (lib) App.lib, if (art) App.art]),
        builder: (c, _) => builder(c),
      );
}

// ---------------------------------------------------------------- artwork

/// Track artwork, swapping a music video's frame for its album cover when found.
class TrackArt extends StatelessWidget {
  const TrackArt(this.track, {super.key, this.size = 48, this.radius = 4, this.px});
  final Track track;
  final double size;
  final double radius;
  final int? px;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: App.art,
        builder: (_, _) => ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: artImage(App.art.artFor(track), size: size, px: px ?? (size * 2).round(), localFile: App.lib.download(track.id)?.cover),
        ),
      );
}

class Art extends StatelessWidget {
  const Art(this.url, {super.key, this.size, this.radius = 4, this.circle = false, this.px, this.shadow = false});
  final String? url;
  final double? size;
  final double radius;
  final bool circle;
  final int? px;
  final bool shadow;
  @override
  Widget build(BuildContext context) {
    Widget img = artImage(url, size: size, px: px ?? ((size ?? 200) * 2).round());
    img = circle ? ClipOval(child: img) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    if (!shadow) return img;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(circle ? 999 : radius),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 8))],
      ),
      child: img,
    );
  }
}

/// 2x2 grid of covers for a playlist.
class Mosaic extends StatelessWidget {
  const Mosaic(this.covers, {super.key, this.size = 48, this.radius = 4, this.icon});
  final List<String> covers;
  final double size;
  final double radius;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    Widget child;
    if (covers.length >= 4) {
      final h = size / 2;
      child = Column(children: [
        Row(children: [artImage(covers[0], size: h, px: (h * 2).round()), artImage(covers[1], size: h, px: (h * 2).round())]),
        Row(children: [artImage(covers[2], size: h, px: (h * 2).round()), artImage(covers[3], size: h, px: (h * 2).round())]),
      ]);
    } else if (covers.isNotEmpty) {
      child = artImage(covers.first, size: size, px: (size * 2).round());
    } else {
      child = Container(
        width: size,
        height: size,
        color: C.hover,
        child: Icon(icon ?? Icons.music_note_rounded, color: C.sub, size: size * .42),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: size, height: size, child: child));
  }
}

/// Gradient tile used for Liked Songs / Downloads.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 48, this.radius = 4});
  final IconData icon;
  final double size;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFFFFF), Color(0xFF8C8C8C)]),
        ),
        child: Icon(icon, color: Colors.black, size: size * .42),
      );
}

// ---------------------------------------------------------------- buttons

class PlayCircle extends StatelessWidget {
  const PlayCircle({super.key, required this.playing, required this.onTap, this.size = 56});
  final bool playing;
  final VoidCallback onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: size * .55),
          ),
        ),
      );
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.size = 24, this.color, this.active = false, this.dot = false, this.glyph});
  final IconData icon;

  /// Draw this instead of [icon] (for symbols Material doesn't have).
  final Widget Function(Color color, double size)? glyph;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? color;
  final bool active;
  final bool dot;
  @override
  Widget build(BuildContext context) {
    final btn = IconButton(
      onPressed: onTap,
      icon: Column(mainAxisSize: MainAxisSize.min, children: [
        glyph != null
            ? glyph!(color ?? (active ? Colors.white : (onTap == null ? C.faint : C.sub)), size)
            : Icon(icon, size: size, color: color ?? (active ? Colors.white : (onTap == null ? C.faint : C.sub))),
        if (dot) Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ]),
      splashRadius: size,
      hoverColor: const Color(0x14FFFFFF),
      visualDensity: VisualDensity.compact,
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class LikeButton extends StatelessWidget {
  const LikeButton(this.track, {super.key, this.size = 22});
  final Track track;
  final double size;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: App.lib,
        builder: (_, _) {
          final on = App.lib.isLiked(track.id);
          return IconBtn(
            on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: size,
            color: on ? Colors.white : C.sub,
            tooltip: on ? 'Remove from Liked Songs' : 'Save to Liked Songs',
            onTap: () {
              final now = App.lib.toggleLike(track);
              Nav.toast(now ? 'Added to Liked Songs' : 'Removed from Liked Songs');
            },
          );
        },
      );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.selected = false, this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Colors.white : C.hover,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.black : C.text), const SizedBox(width: 6)],
              Text(label, style: TextStyle(color: selected ? Colors.black : C.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class OutlineBtn extends StatelessWidget {
  const OutlineBtn(this.label, {super.key, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null ? null : Icon(icon, size: 18, color: C.text),
        label: Text(label, style: const TextStyle(color: C.text, fontWeight: FontWeight.w700, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF7C7C7C)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
}

/// Download state for a track / collection, as an icon.
class DownloadBadge extends StatelessWidget {
  const DownloadBadge(this.id, {super.key, this.size = 14});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) {
    final d = App.lib.download(id);
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: switch (d.status) {
        DlStatus.done => Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.arrow_downward_rounded, size: size * .75, color: Colors.black),
          ),
        DlStatus.error => Icon(Icons.error_outline_rounded, size: size, color: C.sub),
        _ => SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(value: d.progress > 0 ? d.progress : null, strokeWidth: 2, color: Colors.white, backgroundColor: C.hover),
          ),
      },
    );
  }
}

class Explicit extends StatelessWidget {
  const Explicit({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: C.sub, borderRadius: BorderRadius.circular(2)),
        child: const Text('E', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800)),
      );
}

/// "Artist A, Artist B" where each name opens the artist.
class ArtistLinks extends StatelessWidget {
  const ArtistLinks(this.artists, {super.key, this.style = subtle, this.maxLines = 1});
  final List<ArtistRef> artists;
  final TextStyle style;
  final int maxLines;
  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < artists.length; i++) {
      final a = artists[i];
      if (i > 0) spans.add(const TextSpan(text: ', '));
      spans.add(TextSpan(
        text: a.name,
        recognizer: a.id == null ? null : (TapGestureRecognizer()..onTap = () => Nav.artist(a.id!)),
        mouseCursor: a.id == null ? null : SystemMouseCursors.click,
      ));
    }
    return Text.rich(TextSpan(children: spans), style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}

// ---------------------------------------------------------------- track rows

/// One song in a list. Tap plays it within [list]; long-press / right-click opens its menu.
class TrackTile extends StatefulWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onPlay,
    this.number,
    this.showArt = true,
    this.showAlbum = false,
    this.showArtist = true,
    this.playlistId,
  });
  final Track track;
  final VoidCallback onPlay;
  final int? number;
  final bool showArt;
  final bool showAlbum;
  final bool showArtist;
  final String? playlistId;

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final wide = isWide(context);
    return Watch(builder: (context) {
      final p = App.player;
      final isCurrent = p.current?.id == t.id;
      final sub = <Widget>[
        if (t.explicit) const Explicit(),
        DownloadBadge(t.id),
        if (widget.showArtist && t.artists.isNotEmpty) Flexible(child: ArtistLinks(t.artists)),
        if (widget.showArtist && t.artists.isEmpty && t.isVideo) const Text('Video', style: subtle),
      ];
      return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapDown: (d) => showTrackMenu(context, t, position: d.globalPosition, playlistId: widget.playlistId),
          child: InkWell(
            onTap: widget.onPlay,
            onLongPress: () => showTrackMenu(context, t, playlistId: widget.playlistId),
            borderRadius: BorderRadius.circular(4),
            hoverColor: const Color(0x12FFFFFF),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 0, vertical: 6),
              child: Row(children: [
                if (widget.number != null)
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: isCurrent && p.playing
                          ? const Icon(Icons.graphic_eq_rounded, size: 18)
                          : (_hover && wide
                              ? const Icon(Icons.play_arrow_rounded, size: 20)
                              : Text('${widget.number}', style: TextStyle(color: isCurrent ? Colors.white : C.sub, fontSize: 15))),
                    ),
                  ),
                if (widget.number != null) const SizedBox(width: 8),
                if (widget.showArt) ...[TrackArt(t, size: 48), const SizedBox(width: 12)],
                Expanded(
                  flex: 5,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500, color: C.text, decoration: isCurrent ? TextDecoration.underline : null, decorationColor: Colors.white54),
                    ),
                    if (sub.isNotEmpty) ...[const SizedBox(height: 3), Row(children: sub)],
                  ]),
                ),
                if (wide && widget.showAlbum) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: t.album == null
                        ? const SizedBox()
                        : InkWell(
                            onTap: t.album!.id == null ? null : () => Nav.album(t.album!.id!),
                            child: Text(t.album!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtle),
                          ),
                  ),
                ],
                if (App.lib.isLiked(t.id) || (_hover && wide)) LikeButton(t, size: 18),
                if (wide)
                  SizedBox(
                    width: 52,
                    child: Text(t.duration == null ? '' : fmtTime(Duration(seconds: t.duration!)), textAlign: TextAlign.right, style: subtle),
                  ),
                Builder(
                  builder: (bc) => IconBtn(
                    Icons.more_horiz_rounded,
                    size: 20,
                    tooltip: 'More options',
                    onTap: () {
                      final box = bc.findRenderObject() as RenderBox?;
                      final pos = box?.localToGlobal(box.size.bottomRight(Offset.zero));
                      showTrackMenu(context, t, position: wide ? pos : null, playlistId: widget.playlistId);
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------- cards

class ItemCard extends StatefulWidget {
  const ItemCard(this.item, {super.key, this.width = 160, this.subtitle});
  final Item item;
  final double width;
  final String? subtitle;
  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  bool _hover = false;

  String _subtitle(Item i) => widget.subtitle ??
      switch (i) {
        AlbumCard a => [if (a.year != null) a.year!, a.type == 'Album' && a.artists.isNotEmpty ? a.artists.map((x) => x.name).join(', ') : a.type].join(' • '),
        ArtistCard _ => 'Artist',
        PlaylistCard p => ['Playlist', if (p.author != null) p.author!].join(' • '),
        Track t => t.artistNames.isEmpty ? (t.isVideo ? 'Video' : 'Song') : t.artistNames,
      };

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final w = widget.width;
    final isArtist = i is ArtistCard;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTapDown: i is Track ? (d) => showTrackMenu(context, i, position: d.globalPosition) : null,
        onLongPress: i is Track ? () => showTrackMenu(context, i) : null,
        child: InkWell(
          onTap: () => Nav.open(i),
          borderRadius: BorderRadius.circular(8),
          hoverColor: const Color(0x10FFFFFF),
          child: SizedBox(
            width: w,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                Stack(children: [
                  if (i is Track)
                    TrackArt(i, size: w - 12, radius: 6, px: 400)
                  else
                    Art(i.art, size: w - 12, radius: 6, circle: isArtist, px: 400, shadow: true),
                  if (_hover && !isArtist && isWide(context))
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: PlayCircle(size: 44, playing: false, onTap: () => playItem(i)),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(i.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: isArtist ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(_subtitle(i), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: isArtist ? TextAlign.center : TextAlign.start, style: subtle),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Play an album / playlist / artist straight from a card.
Future<void> playItem(Item i) async {
  try {
    switch (i) {
      case Track t:
        await App.player.playTrack(t);
      case AlbumCard a:
        final al = await App.ytm.album(a.id);
        await App.player.playList(al.tracks, context: al.title, route: 'album:${a.id}');
      case PlaylistCard p:
        final pl = await App.ytm.playlist(p.id);
        await App.player.playList(pl.tracks, context: pl.title, route: 'playlist:${p.id}');
      case ArtistCard a:
        final ar = await App.ytm.artist(a.id);
        await App.player.playList(ar.songs, context: ar.name, route: 'artist:${a.id}');
    }
  } catch (_) {
    Nav.toast('Couldn’t load that. Check your connection.');
  }
}

/// A titled horizontal row of cards.
class ShelfRow extends StatelessWidget {
  const ShelfRow({super.key, required this.title, required this.items, this.onMore});
  final String title;
  final List<Item> items;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final w = wide ? 184.0 : 148.0;
    final songsOnly = items.every((i) => i is Track && !(i).isVideo) && items.length > 4;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(title, onMore: onMore),
      if (songsOnly)
        _QuickPicks(items.cast<Track>(), title: title)
      else
        SizedBox(
          height: w + 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 10),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (_, i) => ItemCard(items[i], width: w),
          ),
        ),
      const SizedBox(height: 20),
    ]);
  }
}

/// Songs shelves ("Quick picks"): columns of 4 compact rows, scrolling sideways.
class _QuickPicks extends StatelessWidget {
  const _QuickPicks(this.tracks, {required this.title});
  final List<Track> tracks;
  final String title;
  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final colW = wide ? 360.0 : MediaQuery.sizeOf(context).width * .86;
    final cols = <List<int>>[];
    for (var i = 0; i < tracks.length; i += 4) {
      cols.add([for (var j = i; j < i + 4 && j < tracks.length; j++) j]);
    }
    return SizedBox(
      height: 4 * 60.0,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 12),
        itemCount: cols.length,
        itemBuilder: (_, c) => SizedBox(
          width: colW,
          child: Column(children: [
            for (final i in cols[c])
              SizedBox(
                height: 60,
                child: TrackTile(
                  track: tracks[i],
                  onPlay: () => App.player.playList(tracks, start: i, context: title),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onMore, this.padding});
  final String title;
  final VoidCallback? onMore;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? EdgeInsets.fromLTRB(isWide(context) ? 24 : 16, 8, isWide(context) ? 24 : 16, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: titleL, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              child: const Text('Show all', style: TextStyle(color: C.sub, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ]),
      );
}

// ---------------------------------------------------------------- states

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(padding: EdgeInsets.all(48), child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
}

class Message extends StatelessWidget {
  const Message({super.key, required this.icon, required this.title, this.text, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: C.sub),
            const SizedBox(height: 16),
            Text(title, style: titleM, textAlign: TextAlign.center),
            if (text != null) ...[const SizedBox(height: 8), Text(text!, style: subtle, textAlign: TextAlign.center)],
            if (action != null) ...[const SizedBox(height: 20), OutlineBtn(action!, onTap: onAction)],
          ]),
        ),
      );
}

class ErrorMessage extends StatelessWidget {
  const ErrorMessage({super.key, this.onRetry});
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Message(
        icon: Icons.wifi_off_rounded,
        title: 'Couldn’t load this',
        text: 'Check your connection and try again.',
        action: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
}

/// Loads [future] and shows a spinner / error with retry.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.loading});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final Widget? loading;
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          if (s.hasData) return widget.builder(c, s.data as T);
          if (s.hasError) return ErrorMessage(onRetry: () => setState(() => _f = widget.load()));
          return widget.loading ?? const Loading();
        },
      );
}

/// Back button row shown at the top of pushed pages.
class PageTop extends StatelessWidget {
  const PageTop({super.key, this.title, this.actions = const []});
  final String? title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              style: IconButton.styleFrom(backgroundColor: const Color(0x99000000)),
              tooltip: 'Back',
            ),
          if (title != null) Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(title!, style: titleM, maxLines: 1, overflow: TextOverflow.ellipsis))) else const Spacer(),
          ...actions,
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- menus & dialogs

class MenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const MenuAction(this.icon, this.label, this.onTap);
}

/// Bottom sheet on phones, popup menu on desktop.
/// [growRight] opens the desktop menu to the right of [position] (under a dropdown)
/// instead of toward the roomier side of the screen.
Future<void> showActions(BuildContext context, {required List<MenuAction> actions, Widget? header, Offset? position, bool growRight = false}) async {
  if (position != null && isWide(context)) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<int>(
      context: context,
      // equal left/right insets make Flutter grow the menu in reading direction
      position: growRight
          ? RelativeRect.fromLTRB(position.dx, position.dy, position.dx, overlay.size.height - position.dy - 1)
          : RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 220),
      items: [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem(
            value: i,
            height: 40,
            child: Row(children: [Icon(actions[i].icon, size: 18, color: C.sub), const SizedBox(width: 12), Text(actions[i].label)]),
          ),
      ],
    );
    if (choice != null) actions[choice].onTap();
    return;
  }
  final chosen = await showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .8),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (header != null) ...[header, const Divider(height: 16)],
            for (var i = 0; i < actions.length; i++)
              ListTile(
                leading: Icon(actions[i].icon, color: C.sub),
                title: Text(actions[i].label, style: const TextStyle(fontSize: 15.5)),
                onTap: () => Navigator.pop(c, i),
                dense: false,
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ),
  );
  if (chosen != null) actions[chosen].onTap();
}

Widget sheetHeader(Widget art, String title, String subtitle) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        art,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: titleM, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: subtle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );

Future<void> showTrackMenu(BuildContext context, Track t, {Offset? position, String? playlistId}) {
  final lib = App.lib;
  final p = App.player;
  final shown = App.art.upgrade(t);
  final dl = lib.download(t.id);
  return showActions(
    context,
    position: position,
    header: sheetHeader(TrackArt(t, size: 48), t.title, t.artistNames),
    actions: [
      MenuAction(lib.isLiked(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          lib.isLiked(t.id) ? 'Remove from Liked Songs' : 'Add to Liked Songs', () {
        final on = lib.toggleLike(shown);
        Nav.toast(on ? 'Added to Liked Songs' : 'Removed from Liked Songs');
      }),
      MenuAction(Icons.playlist_add_rounded, 'Add to playlist', () => showAddToPlaylist(context, [shown])),
      if (playlistId != null)
        MenuAction(Icons.remove_circle_outline_rounded, 'Remove from this playlist', () {
          lib.removeFromPlaylist(playlistId, t.id);
          Nav.toast('Removed from playlist');
        }),
      MenuAction(Icons.queue_play_next_rounded, 'Play next', () {
        p.playNext([shown]);
        Nav.toast('Playing next');
      }),
      MenuAction(Icons.queue_music_rounded, 'Add to queue', () {
        p.addToQueue([shown]);
        Nav.toast('Added to queue');
      }),
      if (dl == null || dl.status == DlStatus.error)
        MenuAction(Icons.download_rounded, 'Download', () {
          App.downloads.add([shown]);
          Nav.toast('Downloading');
        })
      else
        MenuAction(Icons.download_done_rounded, dl.status == DlStatus.done ? 'Remove download' : 'Cancel download', () {
          App.downloads.remove(t.id);
          Nav.toast('Download removed');
        }),
      MenuAction(Icons.sensors_rounded, 'Go to song radio', () => p.startRadio(shown)),
      for (final a in t.artists.where((a) => a.id != null).take(3)) MenuAction(Icons.person_outline_rounded, t.artists.length > 1 ? 'Go to ${a.name}' : 'Go to artist', () => Nav.artist(a.id!)),
      if (shown.album?.id != null) MenuAction(Icons.album_outlined, 'Go to album', () => Nav.album(shown.album!.id!)),
    ],
  );
}

Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  final lib = App.lib;
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .75),
        child: ListView(shrinkWrap: true, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 12), child: Text('Add to playlist', style: titleL)),
          ListTile(
            leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.add_rounded)),
            title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(c, '+'),
          ),
          for (final pl in lib.playlists)
            ListTile(
              leading: Mosaic(lib.playlistCovers(pl), size: 48),
              title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(songs(pl.trackIds.length), style: subtle),
              onTap: () => Navigator.pop(c, pl.id),
            ),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == '+') {
    final name = await promptText(context, title: 'New playlist', hint: 'My playlist', initial: tracks.length == 1 ? tracks.first.title : '');
    if (name == null) return;
    final p = lib.createPlaylist(name, tracks);
    Nav.toast('Added to ${p.name}');
    return;
  }
  final n = lib.addToPlaylist(choice, tracks);
  final name = lib.playlist(choice)?.name ?? 'playlist';
  Nav.toast(n == 0 ? 'Already in $name' : 'Added to $name');
}

Future<String?> promptText(BuildContext context, {required String title, String hint = '', String initial = '', String ok = 'Save'}) {
  final ctl = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (c) => AlertDialog(
      title: Text(title, style: titleL),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel', style: TextStyle(color: C.sub))),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctl.text),
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: const StadiumBorder()),
          child: Text(ok, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, String? text, String ok = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: Text(title, style: titleL),
        content: text == null ? null : Text(text, style: subtle),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(color: C.sub))),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: const StadiumBorder()),
            child: Text(ok, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ) ??
    false;

/// A small "TAB" badge, used as the guitar-tab button icon.
Widget tabGlyph(Color color, double size) => SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: size * .06, vertical: size * .05),
          decoration: BoxDecoration(border: Border.all(color: color, width: 1.6), borderRadius: BorderRadius.circular(size * .14)),
          child: Text('TAB', maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: TextStyle(color: color, fontSize: size * .3, fontWeight: FontWeight.w900, height: 1.1)),
        ),
      ),
    );

/// Button that opens guitar tabs.
class TabsButton extends StatelessWidget {
  const TabsButton({super.key, this.size = 24, this.active = false, this.onTap});
  final double size;
  final bool active;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) =>
      IconBtn(Icons.music_note_rounded, size: size, active: active, dot: active, tooltip: 'Tabs & chords', onTap: onTap, glyph: tabGlyph);
}
