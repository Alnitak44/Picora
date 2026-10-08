import 'dart:async';
import 'dart:io';
import 'package:receive_intent/receive_intent.dart' as receive;
import 'package:uri_to_file/uri_to_file.dart';
import 'diagnostics.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:picora/router/application.dart';
import 'controller.dart';
import 'hero_theme.dart';
import 'upload_page.dart';
import 'album_page.dart';
import 'repositories_page.dart';
import 'settings_page.dart';

class HeroScope extends InheritedWidget {
  final PicoraController controller;
  const HeroScope({super.key, required this.controller, required super.child});
  static PicoraController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeroScope>()!.controller;
  @override
  bool updateShouldNotify(HeroScope oldWidget) =>
      controller != oldWidget.controller;
}

class HeroApp extends StatefulWidget {
  final PicoraController? controller;
  const HeroApp({super.key, this.controller});
  @override
  State<HeroApp> createState() => _HeroAppState();
}

class _HeroAppState extends State<HeroApp> {
  late final PicoraController _controller;
  StreamSubscription<receive.Intent?>? _intents;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PicoraController();
    if (widget.controller == null) {
      _controller.initialize().then((_) async {
        if (!mounted || !Platform.isAndroid) return;
        try {
          _intents = receive.ReceiveIntent.receivedIntentStream.listen(
            _receiveIntent,
            onError: (Object error, StackTrace stack) {
              HeroDiagnostics.instance.record('接收系统分享', error, stack: stack);
            },
          );
          await _receiveIntent(await receive.ReceiveIntent.getInitialIntent());
        } catch (e, stack) {
          HeroDiagnostics.instance.record('初始化系统分享', e, stack: stack);
        }
      });
    }
  }

  Future<void> _receiveIntent(receive.Intent? intent) async {
    final streams = intent?.extra?['android.intent.extra.STREAM'];
    if (streams == null) return;
    try {
      final paths = <String>[];
      for (final uri in streams is List ? streams : [streams]) {
        final file = await toFile(uri.toString());
        paths.add(file.path);
      }
      if (mounted) _controller.receiveSharedPaths(paths);
    } catch (e, stack) {
      HeroDiagnostics.instance.record('读取分享图片', e, stack: stack);
    }
  }

  @override
  void dispose() {
    _intents?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => HeroScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Picora',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: heroMessengerKey,
        theme: heroTheme(Brightness.light),
        darkTheme: heroTheme(Brightness.dark),
        themeMode: _controller.themeChoice == 'dark'
            ? ThemeMode.dark
            : _controller.themeChoice == 'light'
            ? ThemeMode.light
            : ThemeMode.system,
        home: HeroShell(controller: _controller),
        onGenerateRoute: Application.router.generator,
      ),
    ),
  );
}

class HeroShell extends StatefulWidget {
  final PicoraController controller;
  final int selectedIndex;
  const HeroShell({
    super.key,
    required this.controller,
    this.selectedIndex = 0,
  });
  @override
  State<HeroShell> createState() => _HeroShellState();
}

class _HeroShellState extends State<HeroShell> {
  late final PageController _pager;
  late int _index;
  @override
  void initState() {
    super.initState();
    _index = widget.selectedIndex.clamp(0, 3);
    _pager = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    _pager.animateToPage(
      index,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _navigation(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Align(
          heightFactor: 1,
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: heroInk.withValues(alpha: .08),
                  blurRadius: 28,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        surface.withValues(alpha: .91),
                        surface.withValues(alpha: .73),
                      ],
                    ),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white12
                          : Colors.white.withValues(alpha: .9),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: _NavItem(
                            index: i,
                            selected: _index == i,
                            onTap: () => _go(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              children: [
                if (widget.controller.initializing)
                  const LinearProgressIndicator(minHeight: 2),
                if (!widget.controller.initializing &&
                    widget.controller.initializationFailure != null)
                  MaterialBanner(
                    content: Text(
                      widget.controller.initializationFailure!,
                      style: const TextStyle(fontSize: 11),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => widget.controller.initialize(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: PageView(
                    controller: _pager,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      UploadPage(
                        controller: widget.controller,
                        openRepositories: () => _go(2),
                        openAlbum: () => _go(1),
                      ),
                      AlbumPage(
                        controller: widget.controller,
                        openUpload: () => _go(0),
                      ),
                      RepositoriesPage(controller: widget.controller),
                      SettingsPage(
                        controller: widget.controller,
                        openRepositories: () => _go(2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _navigation(context),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final int index;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.index,
    required this.selected,
    required this.onTap,
  });
  static const labels = ['上传', '相册', '仓库', '设置'];
  static const icons = [
    Icons.cloud_upload_outlined,
    Icons.photo_library_outlined,
    Icons.inventory_2_outlined,
    Icons.tune_rounded,
  ];
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: labels[index],
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('nav-$index'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 230),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? heroBlue.withValues(alpha: .10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icons[index],
                color: selected ? heroBlue : heroMuted,
                size: 23,
              ),
              const SizedBox(height: 5),
              Text(
                labels[index],
                style: TextStyle(
                  color: selected ? heroBlue : heroMuted,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
