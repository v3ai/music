import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';

// Keeps the app up to date from the GitHub releases, the same files the download page
// offers. How an update gets applied depends on how the app was installed.

enum UpdateKind {
  android, // download the APK, then the system's install screen (Android always asks)
  windows, // run the new installer silently, it reopens the app
  macos, // swap the app in /Applications from the new disk image
  appimage, // swap the AppImage file in place
  apt, // installed from the apt repository: apt-get through the system password prompt
  manual, // anything else (a dev build, an old zip): just point at the download page
}

enum UpdateState { idle, checking, upToDate, available, downloading, ready, installing, failed }

class Updater extends ChangeNotifier {
  Updater(this.dir);
  final Directory dir;

  static const _repo = 'https://github.com/v3ai/music';
  static const page = 'https://v3ai.github.io/music/';
  static const _channel = MethodChannel('music/update');

  final kind = _detect();
  String current = '';
  String? latest; // e.g. "1.3.0"
  UpdateState state = UpdateState.idle;
  double progress = 0; // while downloading, 0..1
  String? error;
  File? _file;
  Timer? _timer;
  final _http = http.Client();
  AppLifecycleListener? _resume;
  bool _askedPermission = false;

  bool get auto => App.lib.setting<bool>('autoUpdate', true);
  set auto(bool v) {
    App.lib.setSetting('autoUpdate', v);
    notifyListeners();
    if (v) check(quiet: true);
  }

  bool get hasUpdate => state == UpdateState.available || state == UpdateState.downloading || state == UpdateState.ready || state == UpdateState.installing;

  /// What the update button says.
  String get action => switch (kind) {
    UpdateKind.android => 'Install',
    UpdateKind.apt => 'Update',
    UpdateKind.manual => 'Download',
    _ => state == UpdateState.ready ? 'Restart' : 'Update',
  };

  // Big downloads over a phone's data plan wait for a tap; computers fetch right away.
  bool get _autoDownload => kind == UpdateKind.windows || kind == UpdateKind.macos || kind == UpdateKind.appimage;

  static UpdateKind _detect() {
    if (Platform.isAndroid) return UpdateKind.android;
    final exe = Platform.resolvedExecutable;
    if (Platform.isWindows) return exe.toLowerCase().contains(r'\programs\music\') ? UpdateKind.windows : UpdateKind.manual;
    if (Platform.isMacOS) return exe.contains('.app/Contents/MacOS/') ? UpdateKind.macos : UpdateKind.manual;
    if (Platform.isLinux) {
      if ((Platform.environment['APPIMAGE'] ?? '').isNotEmpty) return UpdateKind.appimage;
      if (exe.startsWith('/opt/music/')) return UpdateKind.apt;
    }
    return UpdateKind.manual;
  }

  String? get _asset => switch (kind) {
    UpdateKind.android => 'music-android.apk',
    UpdateKind.windows => 'music-windows-setup.exe',
    UpdateKind.macos => 'music-macos.dmg',
    UpdateKind.appimage => 'music-linux-x86_64.AppImage',
    _ => null,
  };

  Future<void> start() async {
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    notifyListeners();
    if (current.isEmpty) return;
    await Future.delayed(const Duration(seconds: 10)); // let startup finish first
    if (auto) await check(quiet: true);
    _timer = Timer.periodic(const Duration(hours: 6), (_) {
      if (auto) check(quiet: true);
    });
  }

  /// Ask GitHub for the newest release. [quiet] checks don't show errors.
  Future<void> check({bool quiet = false}) async {
    if (current.isEmpty || state == UpdateState.checking || state == UpdateState.downloading || state == UpdateState.installing) return;
    if (state == UpdateState.ready) return; // already have it
    _set(UpdateState.checking);
    try {
      final tag = await _latestTag();
      latest = tag.replaceFirst(RegExp('^v'), '');
      if (!newer(latest!, current)) {
        _set(UpdateState.upToDate);
        _cleanup(keep: null);
        return;
      }
      final f = _target(tag);
      if (f != null && await f.exists()) {
        _file = f;
        _set(UpdateState.ready);
      } else {
        _set(UpdateState.available);
        if (_autoDownload) unawaited(download());
      }
    } catch (e) {
      error = 'Couldn’t check for updates';
      _set(quiet ? UpdateState.idle : UpdateState.failed);
    }
  }

  /// The button: download if needed, then apply.
  Future<void> run() async {
    switch (state) {
      case UpdateState.available || UpdateState.failed when kind == UpdateKind.apt:
        await _apt();
      case UpdateState.available || UpdateState.failed when kind == UpdateKind.manual:
        await openUrl(page);
      case UpdateState.available || UpdateState.failed:
        if (await download()) await apply();
      case UpdateState.ready:
        await apply();
      default:
        await check();
    }
  }

  Future<String> _latestTag() async {
    final req = http.Request('GET', Uri.parse('$_repo/releases/latest'))..followRedirects = false;
    final res = await _http.send(req).timeout(const Duration(seconds: 15));
    await res.stream.drain<void>();
    final m = RegExp(r'/releases/tag/(v?\d+(?:\.\d+)*)').firstMatch(res.headers['location'] ?? '');
    if (m == null) throw const HttpException('no release');
    return m.group(1)!;
  }

  /// Numeric compare of dotted versions: 1.10.0 > 1.9.3.
  static bool newer(String a, String b) {
    List<int> p(String v) => [for (final x in v.split('+').first.split('.')) int.tryParse(x) ?? 0];
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d > 0;
    }
    return false;
  }

  File? _target(String tag) {
    final a = _asset;
    if (a == null) return null;
    if (kind == UpdateKind.appimage) {
      // next to the AppImage, so it can be renamed into place
      final img = File(Platform.environment['APPIMAGE']!);
      return File('${img.parent.path}/.music-$tag.AppImage');
    }
    return File('${dir.path}/$tag-$a');
  }

  Future<bool> download() async {
    if (state == UpdateState.downloading) return false;
    final tag = 'v$latest';
    var f = _target(tag);
    final a = _asset;
    if (f == null || a == null) return false;
    _set(UpdateState.downloading, progress: 0);
    try {
      if (kind == UpdateKind.appimage && !await _writable(f.parent)) f = File('${dir.path}/$tag-$a');
      await f.parent.create(recursive: true);
      final part = File('${f.path}.part');
      final res = await _http.send(http.Request('GET', Uri.parse('$_repo/releases/download/$tag/$a'))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('download ${res.statusCode}');
      final total = res.contentLength ?? 0;
      final sink = part.openWrite();
      var got = 0, shown = 0.0;
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0 && got / total - shown >= .01) {
            shown = got / total;
            _set(UpdateState.downloading, progress: shown);
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw const HttpException('download cut short');
      await part.rename(f.path);
      _file = f;
      _cleanup(keep: f);
      _set(UpdateState.ready);
      return true;
    } catch (e) {
      error = 'The update didn’t download. Try again in a bit.';
      _set(UpdateState.failed);
      return false;
    }
  }

  /// Install the downloaded update (restarting the app on computers).
  Future<void> apply() async {
    final f = _file;
    if (f == null || !await f.exists()) {
      _set(UpdateState.available);
      return;
    }
    try {
      switch (kind) {
        case UpdateKind.android:
          final r = await _channel.invokeMethod<String>('install', {'path': f.path});
          if (r == 'permission') {
            // Android sent them to "Install unknown apps"; carry on when they come back
            _askedPermission = true;
            _resume ??= AppLifecycleListener(
              onResume: () {
                if (!_askedPermission) return;
                _askedPermission = false;
                apply();
              },
            );
          }
          return;
        case UpdateKind.windows:
          _set(UpdateState.installing);
          await _beforeExit();
          await Process.start(f.path, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/relaunch=1'], mode: ProcessStartMode.detached);
          exit(0);
        case UpdateKind.macos:
          await _mac(f);
        case UpdateKind.appimage:
          await _appImage(f);
        default:
          await openUrl(page);
      }
    } catch (e) {
      error = 'Couldn’t install the update.';
      _set(UpdateState.failed);
    }
  }

  Future<void> _mac(File dmg) async {
    final app = File(Platform.resolvedExecutable).parent.parent.parent.path; // …/music.app
    final movable = !app.contains('/AppTranslocation/') && !app.startsWith('/Volumes/') && await _writable(Directory(File(app).parent.path));
    if (!movable) {
      // can't replace it in place: open the disk image so it can be dragged over
      await Process.run('open', [dmg.path]);
      return;
    }
    _set(UpdateState.installing);
    final script = File('${dir.path}/update.sh');
    // the same script CI runs against each release (assets/update-macos.sh)
    await script.writeAsString(await rootBundle.loadString('assets/update-macos.sh'));
    await _beforeExit();
    await Process.start('/bin/sh', [script.path, '$pid', dmg.path, app], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _appImage(File f) async {
    final img = Platform.environment['APPIMAGE']!;
    _set(UpdateState.installing);
    await Process.run('chmod', ['755', f.path]);
    if (File(img).parent.path == f.parent.path) {
      await f.rename(img); // atomic; the running copy keeps its old file
    } else {
      await f.copy('$img.new');
      await Process.run('chmod', ['755', '$img.new']);
      await File('$img.new').rename(img);
      await f.delete();
    }
    await _relaunch(img);
  }

  Future<void> _apt() async {
    _set(UpdateState.installing);
    final r = await Process.run('pkexec', ['sh', '-c', 'apt-get update -qq && apt-get install -y --only-upgrade music']);
    if (r.exitCode != 0) {
      error = r.exitCode == 126 || r.exitCode == 127 ? 'Update cancelled.' : 'Update didn’t finish. Run: sudo apt update && sudo apt upgrade';
      _set(UpdateState.failed);
      return;
    }
    await _relaunch('/usr/bin/music');
  }

  // Start the new version once this one has quit (a second copy would just hand over
  // to this one, which is about to exit).
  Future<void> _relaunch(String exe) async {
    await _beforeExit();
    await Process.start('/bin/sh', ['-c', 'while kill -0 $pid 2>/dev/null; do sleep 0.2; done; exec "\$0"', exe], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _beforeExit() async {
    try {
      await App.lib.save();
    } catch (_) {}
  }

  static Future<bool> _writable(Directory d) async {
    try {
      final t = File('${d.path}/.music-write-test-$pid');
      await t.writeAsString('');
      await t.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Old downloads are just clutter once a newer one (or the installed one) replaces them.
  void _cleanup({required File? keep}) {
    () async {
      final dirs = {dir.path, if (kind == UpdateKind.appimage) File(Platform.environment['APPIMAGE']!).parent.path};
      for (final d in dirs) {
        try {
          await for (final e in Directory(d).list()) {
            final name = e.uri.pathSegments.last;
            final ours = name.startsWith('.music-v') || RegExp(r'^v\d.*-music-').hasMatch(name);
            if (ours && e is File && e.path != keep?.path) await e.delete();
          }
        } catch (_) {}
      }
    }();
  }

  void _set(UpdateState s, {double? progress}) {
    state = s;
    if (progress != null) this.progress = progress;
    if (s != UpdateState.failed) error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resume?.dispose();
    _http.close();
    super.dispose();
  }
}

/// Open a web page in the default browser.
Future<void> openUrl(String url) async {
  if (Platform.isAndroid) {
    await Updater._channel.invokeMethod('open', {'url': url});
  } else if (Platform.isWindows) {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else {
    await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [url]);
  }
}
