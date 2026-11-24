import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../yt/innertube.dart';
import '../yt/ytm.dart';
import 'desktop_integration.dart';
import 'downloads.dart';
import 'images.dart';
import 'library.dart';
import 'player.dart';
import 'proxy.dart';
import 'streams.dart';
import 'tabs.dart';

/// The app's services, created once at startup.
class App {
  static late final Library lib;
  static late final Ytm ytm;
  static late final StreamResolver resolver;
  static late final StreamProxy proxy;
  static late final Player player;
  static late final Downloads downloads;
  static late final AlbumArt art;
  static late final Tabs tabs;
  static late final Directory dataDir;

  static bool get isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static Future<void> init() async {
    if (Platform.isLinux || Platform.isWindows) JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    dataDir = support;
    NetArt.dir = Directory('${cache.path}/art');

    final locale = Platform.localeName; // e.g. en_US
    final parts = locale.split(RegExp(r'[_.-]'));
    final gl = parts.length > 1 && parts[1].length == 2 ? parts[1].toUpperCase() : 'US';

    lib = Library(support);
    await lib.load();
    ytm = Ytm(client: InnerTube(hl: 'en', gl: gl));
    resolver = StreamResolver(configFile: File('${support.path}/clients.json'));
    resolver.refreshClients().ignore();
    proxy = StreamProxy(resolver, localFile: (id) => lib.localFile(id));
    await proxy.start();
    art = AlbumArt(lib, ytm);
    tabs = Tabs(Directory('${cache.path}/tabs'));
    downloads = Downloads(lib, resolver, proxy, ytm, Directory('${support.path}/downloads'));
    player = Player(lib, ytm, resolver, proxy, art);

    MusicHandler handler;
    try {
      handler = await AudioService.init(
        builder: () => MusicHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'io.github.v3ai.music.playback',
          androidNotificationChannelName: 'Playback',
          androidNotificationIcon: 'drawable/ic_stat_music',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (_) {
      // platforms without media-session support (e.g. Windows): play without OS controls
      handler = MusicHandler();
    }
    await player.init(handler);
    downloads.start();
    integrateAppImage().ignore();
  }
}
