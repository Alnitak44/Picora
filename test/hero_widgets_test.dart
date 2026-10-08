import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:fluro/fluro.dart';
import 'package:picora/hero/hero_app.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/models.dart';
import 'package:picora/router/application.dart';

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('HERO_SCREENSHOTS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('artifacts/previews').create(recursive: true);
    await File(
      'artifacts/previews/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> initialize(
  WidgetTester tester,
  PicoraController controller, {
  Size size = const Size(390, 844),
}) async {
  final originalShadows = debugDisableShadows;
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = originalShadows);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.runAsync(() async {
    for (final entry in controller.images) {
      final file = File(entry.path);
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      final key = FileImage(file);
      PaintingBinding.instance.imageCache.evict(key);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: frame.image)),
        ),
      );
      codec.dispose();
    }
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('capture'),
      child: HeroApp(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

PicoraController exampleController({bool images = true}) {
  const config = RepositoryConfig(
    host: 'aliyun',
    slot: 'A',
    name: '阿里云 OSS · 主图床',
    values: {'bucket': 'creative-images', 'area': 'oss-cn-hangzhou'},
  );
  final controller = PicoraController()
    ..initializing = false
    ..repositories = [config]
    ..target = config
    ..defaultId = config.id;
  if (images) {
    controller.images = List.generate(
      6,
      (i) => AlbumEntry(
        {
          'id': i,
          'name': [
            'blue_hour.png',
            'weekend_walk.png',
            'quiet_moment.png',
            'city_lights.png',
            'a_little_escape.png',
            'morning_light.png',
          ][i],
          'path': 'artifacts/fixtures/art-$i.png',
          'url': 'https://images.example.com/photo-$i.png',
          'hostSpecificArgA': 'test',
        },
        'aliyun',
        uploadedAt: DateTime(2026, 10, 5, 10, i),
        repositoryId: config.id,
      ),
    );
    controller.latest = controller.images.first;
  }
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Application.router = FluroRouter();
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final regular = FontLoader('Roboto')
        ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
      await regular.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await Directory('artifacts/fixtures').create(recursive: true);
    for (var i = 0; i < 6; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final height = i.isEven ? 360.0 : 480.0;
      const palette = [
        Color(0xFF82AFBE),
        Color(0xFFCFB1A1),
        Color(0xFFADBDAA),
        Color(0xFF576985),
        Color(0xFFDFBC8E),
        Color(0xFFBCCDD8),
      ];
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 440, height),
        Paint()..color = palette[i],
      );
      canvas.drawCircle(
        Offset(325, height * .24),
        52,
        Paint()..color = const Color(0xFFF9EACF),
      );
      final path = Path()
        ..moveTo(0, height * .7)
        ..quadraticBezierTo(120, height * .26, 250, height * .8)
        ..quadraticBezierTo(350, height * .55, 440, height * .78)
        ..lineTo(440, height)
        ..lineTo(0, height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = palette[i].withValues(
            red: palette[i].r * .72,
            green: palette[i].g * .75,
            blue: palette[i].b * .76,
          ),
      );
      final image = await recorder.endRecording().toImage(440, height.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'artifacts/fixtures/art-$i.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }
  });
  testWidgets(
    'four navigation destinations, empty storage, link validation and sheets',
    (tester) async {
      final controller = PicoraController()..initializing = false;
      await initialize(tester, controller);
      expect(find.text('当前上传目标'), findsOneWidget);
      expect(find.byType(PageHeading), findsNothing);
      await screenshot(tester, 'upload-empty');
      await tester.tap(find.text('链接上传'));

      await tester.pumpAndSettle();
      expect(find.text('通过链接上传'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'not-a-url');
      await tester.tap(find.text('下载并上传'));

      await tester.pumpAndSettle();
      expect(find.text('请输入有效的 HTTP 或 HTTPS 图片链接'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-2')));

      await tester.pumpAndSettle();
      expect(find.text('暂无图床配置'), findsOneWidget);
      await screenshot(tester, 'repositories-empty');
      await tester.tap(find.byTooltip('添加图床'));

      await tester.pumpAndSettle();
      expect(find.text('选择图床类型'), findsOneWidget);
      expect(find.text('阿里云 OSS'), findsOneWidget);
      await screenshot(tester, 'provider-sheet');
      if (const bool.fromEnvironment('HERO_SCREENSHOTS')) {
        final press = await tester.startGesture(
          tester.getCenter(find.text('又拍云')),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 120));
        await screenshot(tester, 'provider-sheet-pressed');
        await press.cancel();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('阿里云 OSS'));

      await tester.pumpAndSettle();
      expect(find.text('添加图床'), findsOneWidget);
      await screenshot(tester, 'repository-editor');
      await tester.tap(find.byType(BackButton).first);

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-3')));

      await tester.pumpAndSettle();
      expect(find.text('上传设置'), findsOneWidget);
      expect(find.text('图床参数设置'), findsNothing);
      await screenshot(tester, 'settings');
      await tester.tap(find.byKey(const ValueKey('nav-1')));

      await tester.pumpAndSettle();
      expect(find.text('暂无上传图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
      controller.dispose();
    },
  );
  testWidgets(
    'gallery layouts, search, multi-select and default target selector',
    (tester) async {
      final controller = exampleController();
      await initialize(tester, controller);
      await screenshot(tester, 'upload');
      expect(find.text('blue_hour.png'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-1')));

      await tester.pumpAndSettle();
      await screenshot(tester, 'album-grid');
      await tester.tap(find.byTooltip('瀑布流'));

      await tester.pumpAndSettle();
      await screenshot(tester, 'album-masonry');
      await tester.tap(find.byTooltip('列表'));

      await tester.pumpAndSettle();
      await screenshot(tester, 'album-list');
      await tester.enterText(find.byType(TextField).first, 'blue_hour');

      await tester.pumpAndSettle();
      expect(find.text('blue_hour.png'), findsOneWidget);
      expect(find.text('weekend_walk.png'), findsNothing);
      await tester.tap(find.byTooltip('多选图片'));

      await tester.pumpAndSettle();
      await tester.tap(find.text('blue_hour.png'));

      await tester.pumpAndSettle();
      expect(find.text('已选 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('nav-2')));

      await tester.pumpAndSettle();
      await screenshot(tester, 'repositories');
      expect(find.text('阿里云 OSS · 主图床'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-3')));
      await tester.pumpAndSettle();
      await screenshot(tester, 'settings');
      await tester.tap(find.byKey(const ValueKey('nav-0')));

      await tester.pumpAndSettle();
      await tester.tap(find.text('阿里云 OSS · 主图床').first);

      await tester.pumpAndSettle();
      expect(find.text('上传到哪里？'), findsOneWidget);
      expect(tester.getSize(find.byType(BottomSheet)).width, closeTo(390, .1));
      await screenshot(tester, 'target-sheet');
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
      controller.dispose();
    },
  );
  testWidgets('320px viewport and dark theme do not overflow', (tester) async {
    final controller = exampleController(images: false)..themeChoice = 'dark';
    await initialize(tester, controller, size: const Size(320, 700));
    await screenshot(tester, 'upload-dark');
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(ValueKey('nav-$i')));

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
    controller.dispose();
  });
  testWidgets('album distinguishes two configurations on the same platform', (
    tester,
  ) async {
    final controller = exampleController();
    controller.repositories.add(
      RepositoryConfig(
        host: 'aliyun',
        slot: 'B',
        name: '阿里云 OSS · 备用',
        values: {'bucket': 'second-bucket', 'area': 'oss-cn-hangzhou'},
      ),
    );
    await initialize(tester, controller);
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部相册'));
    await tester.pumpAndSettle();
    expect(find.text('按图床配置'), findsOneWidget);
    await tester.tap(find.text('阿里云 OSS · 备用'));
    await tester.pumpAndSettle();
    expect(find.text('blue_hour.png'), findsNothing);
    await tester.tap(find.text('阿里云 OSS · 备用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿里云 OSS · 主图床'));
    await tester.pumpAndSettle();
    expect(find.text('blue_hour.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
    controller.dispose();
  });
  testWidgets(
    'theme selector applies light, dark and automatic modes to all four pages',
    (tester) async {
      final controller = exampleController();
      await initialize(tester, controller);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      Brightness currentBrightness() => Theme.of(
        tester.element(find.byKey(const ValueKey('nav-0'))),
      ).brightness;
      Future<void> chooseTheme(String label) async {
        await tester.tap(find.byKey(const ValueKey('nav-3')));
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('主题模式')),
          alignment: .25,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('主题模式'));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        for (final option in ['浅色', '自动', '深色']) {
          expect(
            find.descendant(of: sheet, matching: find.text(option)),
            findsOneWidget,
          );
        }
        await tester.tap(
          find.descendant(of: sheet, matching: find.text(label)),
        );
        await tester.pumpAndSettle();
      }

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await chooseTheme('浅色');
      expect(currentBrightness(), Brightness.light);
      expect(SpUtil.getString('hero_theme'), 'light');
      await chooseTheme('深色');
      expect(currentBrightness(), Brightness.dark);
      expect(SpUtil.getString('hero_theme'), 'dark');
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('nav-$i')));
        await tester.pumpAndSettle();
        expect(find.byType(PageHeading), findsNothing);
        if (i == 3) {
          final settingsScroll = find.descendant(
            of: find.byKey(const PageStorageKey('settings')),
            matching: find.byType(Scrollable),
          );
          tester
              .state<ScrollableState>(settingsScroll.first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
        }
        await screenshot(
          tester,
          [
            'upload-dark-full',
            'album-dark',
            'repositories-dark',
            'settings-dark',
          ][i],
        );
        expect(tester.takeException(), isNull);
      }
      await chooseTheme('自动');
      expect(SpUtil.getString('hero_theme'), 'system');
      expect(currentBrightness(), Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(currentBrightness(), Brightness.light);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
      controller.dispose();
    },
  );
}
