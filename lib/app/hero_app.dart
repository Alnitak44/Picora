import 'dart:async';
import 'dart:io';
import 'package:receive_intent/receive_intent.dart' as receive;
import 'package:uri_to_file/uri_to_file.dart';
import 'diagnostics.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:picora/legacy/router/application.dart';
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

  Widget _navigation(BuildContext context) => _GlassNavigation(
    selectedIndex: _index,
    showLabels: widget.controller.showNavigationLabels,
    onSelected: _go,
  );

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
                    // Keep the neighbouring pages mounted and laid out so a
                    // tab change does not pay their first-build cost.
                    allowImplicitScrolling: true,
                    children: [
                      RepaintBoundary(
                        key: const ValueKey('hero-page-upload'),
                        child: UploadPage(
                          controller: widget.controller,
                          openRepositories: () => _go(2),
                          openAlbum: () => _go(1),
                        ),
                      ),
                      RepaintBoundary(
                        key: const ValueKey('hero-page-album'),
                        child: AlbumPage(
                          controller: widget.controller,
                          openUpload: () => _go(0),
                          isActive: _index == 1,
                        ),
                      ),
                      RepaintBoundary(
                        key: const ValueKey('hero-page-repositories'),
                        child: RepositoriesPage(controller: widget.controller),
                      ),
                      RepaintBoundary(
                        key: const ValueKey('hero-page-settings'),
                        child: SettingsPage(
                          controller: widget.controller,
                          openRepositories: () => _go(2),
                        ),
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

class _GlassNavigation extends StatefulWidget {
  final int selectedIndex;
  final bool showLabels;
  final ValueChanged<int> onSelected;
  const _GlassNavigation({
    required this.selectedIndex,
    required this.showLabels,
    required this.onSelected,
  });

  @override
  State<_GlassNavigation> createState() => _GlassNavigationState();
}

class _GlassNavigationState extends State<_GlassNavigation> {
  int? _previewIndex;

  int get _activeIndex => _previewIndex ?? widget.selectedIndex;

  void _previewAt(Offset position, double width) {
    if (width <= 0) return;
    final next = (position.dx / width * 4).floor().clamp(0, 3);
    if (next == _previewIndex) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _previewIndex = next);
  }

  void _commit() {
    final target = _previewIndex;
    if (target == null) return;
    setState(() => _previewIndex = null);
    if (target != widget.selectedIndex) widget.onSelected(target);
  }

  void _cancel() {
    if (_previewIndex != null) setState(() => _previewIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 250);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Align(
          heightFactor: 1,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 540),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (dark ? Colors.black : heroInk).withValues(
                        alpha: dark ? .38 : .14,
                      ),
                      blurRadius: 40,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Container(
                      key: const ValueKey('nav-surface'),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? [
                                  const Color(
                                    0xFF182238,
                                  ).withValues(alpha: .80),
                                  const Color(
                                    0xFF101827,
                                  ).withValues(alpha: .70),
                                ]
                              : [
                                  Colors.white.withValues(alpha: .76),
                                  const Color(
                                    0xFFF6F9FF,
                                  ).withValues(alpha: .60),
                                ],
                        ),
                        border: Border.all(
                          color: dark
                              ? Colors.white.withValues(alpha: .13)
                              : Colors.white.withValues(alpha: .62),
                          width: 1,
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final itemWidth = constraints.maxWidth / 4;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (details) {
                              unawaited(HapticFeedback.selectionClick());
                              _previewAt(details.localPosition, itemWidth * 4);
                            },
                            onHorizontalDragUpdate: (details) => _previewAt(
                              details.localPosition,
                              itemWidth * 4,
                            ),
                            onHorizontalDragEnd: (_) => _commit(),
                            onHorizontalDragCancel: _cancel,
                            child: Stack(
                              children: [
                                AnimatedPositioned(
                                  key: const ValueKey('nav-indicator'),
                                  duration: duration,
                                  // Overshooting curves clip the pill at the
                                  // first and last destinations.
                                  curve: Curves.easeOutCubic,
                                  left: _activeIndex * itemWidth,
                                  top: 0,
                                  bottom: 0,
                                  width: itemWidth,
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF285FEA),
                                            Color(0xFF4F86FF),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: .28,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: heroBlue.withValues(
                                              alpha: dark ? .42 : .32,
                                            ),
                                            blurRadius: 22,
                                            offset: const Offset(0, 7),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    for (var i = 0; i < 4; i++)
                                      Expanded(
                                        child: _NavItem(
                                          index: i,
                                          selected: _activeIndex == i,
                                          showLabel: widget.showLabels,
                                          onTap: () => widget.onSelected(i),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;
  const _NavItem({
    required this.index,
    required this.selected,
    required this.showLabel,
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
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 230);
    final foreground = selected ? Colors.white : heroMuted;
    final labelStyle = DefaultTextStyle.of(context).style.copyWith(
      color: foreground,
      fontSize: 10,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    return Semantics(
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
            duration: duration,
            padding: EdgeInsets.symmetric(vertical: showLabel ? 10 : 14),
            child: AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.04 : 1,
                    duration: duration,
                    curve: Curves.easeOutBack,
                    child: TweenAnimationBuilder<Color?>(
                      duration: duration,
                      curve: Curves.easeOut,
                      tween: ColorTween(end: foreground),
                      builder: (context, color, _) => Icon(
                        icons[index],
                        color: color ?? foreground,
                        size: 23,
                      ),
                    ),
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: 5),
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: Curves.easeOut,
                      style: labelStyle,
                      child: Text(labels[index]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
