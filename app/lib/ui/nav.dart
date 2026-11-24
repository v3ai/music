import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import '../models.dart';
import 'pages/album.dart';
import 'pages/artist.dart';
import 'pages/collection.dart';
import 'pages/home.dart';
import 'pages/library.dart';
import 'pages/search.dart';
import 'pages/settings.dart';

/// Navigation inside the main content area (the player bar / sidebar stay put).
class Nav {
  static final key = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final tab = ValueNotifier<String>('home');
  static final messenger = GlobalKey<ScaffoldMessengerState>();

  static NavigatorState get _nav => key.currentState!;

  static Route<void> _route(Widget page, String name) => MaterialPageRoute(builder: (_) => page, settings: RouteSettings(name: name));

  static void push(Widget page, String name) {
    // close the now-playing screen if it's open
    rootKey.currentState?.popUntil((r) => r.isFirst);
    _nav.push(_route(page, name));
  }

  static void switchTab(String t) {
    rootKey.currentState?.popUntil((r) => r.isFirst);
    if (tab.value == t && _nav.canPop()) {
      _nav.popUntil((r) => r.isFirst);
      return;
    }
    tab.value = t;
    _nav.pushAndRemoveUntil(
      PageRouteBuilder(pageBuilder: (_, _, _) => rootFor(t), transitionDuration: Duration.zero, settings: RouteSettings(name: t)),
      (_) => false,
    );
  }

  static Widget rootFor(String t) => switch (t) {
        'search' => const SearchPage(),
        'library' => const LibraryPage(),
        _ => const HomePage(),
      };

  static void album(String id, [AlbumCard? preview]) => push(AlbumPage(id: id, preview: preview), 'album:$id');
  static void artist(String id, [ArtistCard? preview]) => push(ArtistPage(id: id, preview: preview), 'artist:$id');
  static void playlist(String id, [PlaylistCard? preview]) =>
      push(CollectionPage(source: CollectionSource.remote(id, preview)), 'playlist:$id');
  static void local(String id) => push(CollectionPage(source: CollectionSource.local(id)), 'local:$id');
  static void liked() => push(const CollectionPage(source: CollectionSource.liked()), 'liked');
  static void downloads() => push(const CollectionPage(source: CollectionSource.downloads()), 'downloads');
  static void settings() => push(const SettingsPage(), 'settings');

  static void open(Item i) => switch (i) {
        AlbumCard a => album(a.id, a),
        ArtistCard a => artist(a.id, a),
        PlaylistCard p => playlist(p.id, p),
        Track t => App.player.playTrack(t),
      };

  /// Go to where the current queue came from ("Playing from …").
  static void openRoute(String? route) {
    if (route == null) return;
    final i = route.indexOf(':');
    final kind = i < 0 ? route : route.substring(0, i);
    final id = i < 0 ? '' : route.substring(i + 1);
    switch (kind) {
      case 'album':
        album(id);
      case 'artist':
        artist(id);
      case 'playlist':
        playlist(id);
      case 'local':
        local(id);
      case 'liked':
        liked();
      case 'downloads':
        downloads();
      case 'search':
        switchTab('search');
    }
  }

  static void toast(String msg) {
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}
