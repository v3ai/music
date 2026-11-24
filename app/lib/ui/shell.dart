import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app.dart';
import 'nav.dart';
import 'pages/home.dart';
import 'pages/library.dart';
import 'pages/search.dart';
import 'player_ui.dart';
import 'theme.dart';
import 'widgets.dart';

/// App layout: sidebar + content + queue + player bar on desktop;
/// content + mini player + tab bar on phones.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  StreamSubscription<String>? _errs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errs = App.player.errors.listen(Nav.toast);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _errs?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.detached || s == AppLifecycleState.hidden) App.lib.save();
  }

  bool _typing() {
    final f = FocusManager.instance.primaryFocus;
    return f?.context?.widget is EditableText || f?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final k = e.logicalKey;
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed || hk.isMetaPressed;
    final shift = hk.isShiftPressed;
    final p = App.player;
    if (ctrl && k == LogicalKeyboardKey.keyK) {
      Nav.switchTab('search');
      Future.delayed(const Duration(milliseconds: 50), SearchPage.focus.requestFocus);
      return true;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause) {
      p.toggle();
      return true;
    }
    if (_typing()) return false;
    if (e is KeyRepeatEvent && k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight && k != LogicalKeyboardKey.arrowUp && k != LogicalKeyboardKey.arrowDown) return false;
    if (k == LogicalKeyboardKey.space) {
      p.toggle();
    } else if (k == LogicalKeyboardKey.arrowRight && (shift || ctrl)) {
      p.next();
    } else if (k == LogicalKeyboardKey.arrowLeft && (shift || ctrl)) {
      p.prev();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      p.seek(p.position + const Duration(seconds: 5));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      final t = p.position - const Duration(seconds: 5);
      p.seek(t.isNegative ? Duration.zero : t);
    } else if (k == LogicalKeyboardKey.arrowUp && (shift || ctrl)) {
      p.setVolume(p.audio.volume + .1);
    } else if (k == LogicalKeyboardKey.arrowDown && (shift || ctrl)) {
      p.setVolume(p.audio.volume - .1);
    } else if (k == LogicalKeyboardKey.slash) {
      Nav.switchTab('search');
      Future.delayed(const Duration(milliseconds: 50), SearchPage.focus.requestFocus);
    } else if (k == LogicalKeyboardKey.keyL && p.current != null) {
      final on = App.lib.toggleLike(App.art.upgrade(p.current!));
      Nav.toast(on ? 'Added to Liked Songs' : 'Removed from Liked Songs');
    } else if (k == LogicalKeyboardKey.keyS) {
      p.toggleShuffle();
    } else if (k == LogicalKeyboardKey.keyR) {
      p.cycleRepeat();
    } else if (k == LogicalKeyboardKey.keyQ) {
      queueOpen.value = !queueOpen.value;
    } else if (k == LogicalKeyboardKey.keyT && p.current != null) {
      openNowPlaying(context, tabs: true);
    } else if (k == LogicalKeyboardKey.escape) {
      Nav.rootKey.currentState?.maybePop();
    } else {
      return false;
    }
    return true;
  }

  Widget _content() => Navigator(
        key: Nav.key,
        onGenerateRoute: (s) => PageRouteBuilder(pageBuilder: (_, _, _) => const HomePage(), settings: const RouteSettings(name: 'home'), transitionDuration: Duration.zero),
        observers: [_TabObserver()],
      );

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = Nav.key.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (Nav.tab.value != 'home') {
          Nav.switchTab('home');
        } else {
          SystemNavigator.pop();
        }
      },
      child: wide ? _desktop() : _mobile(),
    );
  }

  Widget _desktop() => Scaffold(
        backgroundColor: C.bg,
        body: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(width: 290, child: _Sidebar()),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Material(color: C.surface, child: _content()),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: queueOpen,
                  builder: (_, open, _) => !open
                      ? const SizedBox()
                      : Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 340,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Material(
                                color: C.surface,
                                child: Column(children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                                    child: Row(children: [
                                      const Expanded(child: Text('Queue', style: titleM)),
                                      IconBtn(Icons.close_rounded, size: 20, tooltip: 'Close', onTap: () => queueOpen.value = false),
                                    ]),
                                  ),
                                  const Expanded(child: QueueView(panel: true)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                ),
              ]),
            ),
          ),
          const PlayerBar(),
        ]),
      );

  Widget _mobile() => Scaffold(
        backgroundColor: C.bg,
        body: Column(children: [
          Expanded(child: _content()),
          const MiniPlayer(),
        ]),
        bottomNavigationBar: ValueListenableBuilder(
          valueListenable: Nav.tab,
          builder: (_, tab, _) => Container(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE6000000), C.bg])),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 60,
                child: Row(children: [
                  _Tab(icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home', selected: tab == 'home', onTap: () => Nav.switchTab('home')),
                  _Tab(icon: Icons.search_rounded, active: Icons.manage_search_rounded, label: 'Search', selected: tab == 'search', onTap: () => Nav.switchTab('search')),
                  _Tab(icon: Icons.library_music_outlined, active: Icons.library_music_rounded, label: 'Your Library', selected: tab == 'library', onTap: () => Nav.switchTab('library')),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.active, required this.label, required this.selected, required this.onTap});
  final IconData icon, active;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: InkResponse(
          onTap: onTap,
          radius: 40,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(selected ? active : icon, color: selected ? Colors.white : C.sub, size: 26),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : C.sub, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ]),
        ),
      );
}

/// Keeps the highlighted tab in sync when the user navigates with back.
class _TabObserver extends NavigatorObserver {
  void _sync(Route<dynamic>? r) {
    final n = r?.settings.name;
    if (n == 'home' || n == 'search' || n == 'library') {
      WidgetsBinding.instance.addPostFrameCallback((_) => Nav.tab.value = n!);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _sync(previousRoute);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _sync(route);
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();
  @override
  Widget build(BuildContext context) => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Material(
            color: C.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ValueListenableBuilder(
                valueListenable: Nav.tab,
                builder: (_, tab, _) => Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                    child: Row(children: [
                      Image.asset('assets/icon.png', width: 30, height: 30),
                      const SizedBox(width: 10),
                      const Text('music', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                    ]),
                  ),
                  _NavRow(icon: tab == 'home' ? Icons.home_rounded : Icons.home_outlined, label: 'Home', selected: tab == 'home', onTap: () => Nav.switchTab('home')),
                  _NavRow(icon: Icons.search_rounded, label: 'Search', selected: tab == 'search', onTap: () {
                    Nav.switchTab('search');
                    Future.delayed(const Duration(milliseconds: 50), SearchPage.focus.requestFocus);
                  }),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Material(
              color: C.surface,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Nav.switchTab('library'),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Row(children: [
                            Icon(Icons.library_music_rounded, color: C.sub),
                            SizedBox(width: 14),
                            Text('Your Library', style: TextStyle(fontWeight: FontWeight.w700, color: C.sub, fontSize: 15)),
                          ]),
                        ),
                      ),
                    ),
                    IconBtn(Icons.settings_outlined, size: 20, tooltip: 'Settings', onTap: Nav.settings),
                    IconBtn(Icons.add_rounded, size: 22, tooltip: 'Create playlist', onTap: () => createPlaylistFlow(context)),
                  ]),
                ),
                const Expanded(child: _SideLibrary()),
              ]),
            ),
          ),
        ),
      ]);
}

class _SideLibrary extends StatelessWidget {
  const _SideLibrary();
  @override
  Widget build(BuildContext context) => Watch(player: false, builder: (_) => LibraryList(compact: true, padding: const EdgeInsets.symmetric(horizontal: 8)));
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Row(children: [
            Icon(icon, color: selected ? Colors.white : C.sub, size: 26),
            const SizedBox(width: 18),
            Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : C.sub)),
          ]),
        ),
      );
}
