import 'dart:io';

import 'package:flutter/services.dart';

/// When running as an AppImage, add music to the app menu (with its icon) and make it
/// the handler for v3ai-music:// links, so the website can open it. Re-done whenever
/// the AppImage file moves, so the menu entry always points at it.
Future<void> integrateAppImage() async {
  final appImage = Platform.environment['APPIMAGE'];
  final home = Platform.environment['HOME'];
  if (!Platform.isLinux || appImage == null || home == null) return;
  try {
    final data = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    final apps = Directory('$data/applications');
    final desktop = File('${apps.path}/io.github.v3ai.music.desktop');
    final exec = '"${appImage.replaceAll('"', r'\"')}" %u';
    if (await desktop.exists() && (await desktop.readAsString()).contains('Exec=$exec')) return;

    final icon = File('$data/icons/hicolor/256x256/apps/io.github.v3ai.music.png');
    await icon.parent.create(recursive: true);
    final png = await rootBundle.load('assets/icon.png');
    await icon.writeAsBytes(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));

    await apps.create(recursive: true);
    await desktop.writeAsString('''[Desktop Entry]
Type=Application
Name=music
Comment=Ad-free music player
Exec=$exec
TryExec=$appImage
Icon=io.github.v3ai.music
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=io.github.v3ai.music
MimeType=x-scheme-handler/v3ai-music;
''');
    await Process.run('xdg-mime', ['default', 'io.github.v3ai.music.desktop', 'x-scheme-handler/v3ai-music']).catchError((_) => ProcessResult(0, 1, '', ''));
    await Process.run('update-desktop-database', [apps.path]).catchError((_) => ProcessResult(0, 1, '', ''));
  } catch (_) {
    // not being in the menu isn't worth failing over
  }
}
