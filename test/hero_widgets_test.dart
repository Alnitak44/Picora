import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:fluro/fluro.dart';
import 'package:picora/app/hero_app.dart';
import 'package:picora/app/hero_theme.dart';
import 'package:picora/app/camera_permission.dart';
import 'package:picora/app/controller.dart';
import 'package:picora/app/models.dart';
import 'package:picora/app/plugin_page.dart';
import 'package:picora/app/repositories_page.dart';
import 'package:picora/app/upload_page.dart';
import 'package:picora/legacy/router/application.dart';
import 'package:picora/app/plugins/uploader_registry.dart';
import 'package:permission_handler/permission_handler.dart';
import 'cloud_delete_fixture.dart';

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

PicoraController exampleController({
  bool images = true,
  UploaderRegistry? uploaderRegistry,
}) {
  const config = RepositoryConfig(
    host: 'aliyun',
    slot: 'A',
    name: '阿里云 OSS · 主图床',
    values: {'bucket': 'creative-images', 'area': 'oss-cn-hangzhou'},
  );
  final controller = PicoraController(uploaderRegistry: uploaderRegistry)
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
  const authSpec = HostSpec(
    'plugin.example',
    'Example',
    '示例图床',
    'EX',
    Color(0xFF6377E8),
    [HostField('baseUrl', '图床地址')],
    authModes: [
      PluginAuthChoice(id: 'guest', label: '游客', fields: []),
      PluginAuthChoice(
        id: 'token',
        label: 'API Token',
        fields: [HostField('token', 'Token', required: true, secret: true)],
      ),
      PluginAuthChoice(
        id: 'password',
        label: '账号密码',
        fields: [
          HostField('account', '账号', required: true),
          HostField('password', '密码', required: true, secret: true),
        ],
      ),
    ],
  );
  test('normalization keeps only the selected auth mode fields', () {
    expect(
      PicoraController.normalizeValues(authSpec, {
        'authMode': 'token',
        'baseUrl': 'https://cdn.example.test',
        'token': 'secret-token',
        'account': 'stale-account',
        'password': 'stale-password',
      }),
      {
        'baseUrl': 'https://cdn.example.test',
        'token': 'secret-token',
        'authMode': 'token',
      },
    );
  });
  testWidgets('repository editor switches fields with the auth mode', (
    tester,
  ) async {
    final controller = PicoraController()..initializing = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: RepositoryEditor(controller: controller, spec: authSpec),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-mode')), findsOneWidget);
    expect(find.text('Token *'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('auth-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API Token').last);
    await tester.pumpAndSettle();
    expect(find.text('Token *'), findsOneWidget);
    expect(find.text('账号 *'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('auth-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号密码').last);
    await tester.pumpAndSettle();
    expect(find.text('账号 *'), findsOneWidget);
    expect(find.text('密码 *'), findsOneWidget);
    expect(find.text('Token *'), findsNothing);
  });
  testWidgets('plugin input rules filter typing and reject stored values', (
    tester,
  ) async {
    const spec = HostSpec(
      'plugin.input',
      'Input Example',
      '示例图床',
      'IN',
      Color(0xFF6377E8),
      [
        HostField(
          'path',
          '目录',
          required: true,
          inputPattern: '[a-z/]',
          inputMessage: '只能使用小写字母和斜杠',
        ),
      ],
    );
    const existing = RepositoryConfig(
      host: 'plugin.input',
      slot: 'A',
      name: '已有配置',
      values: {'path': 'ABC'},
    );
    final controller = PicoraController()
      ..initializing = false
      ..repositories = [existing];
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: RepositoryEditor(
          controller: controller,
          spec: spec,
          existing: existing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(find.text('只能使用小写字母和斜杠'), findsOneWidget);

    final pathField = find.byType(TextFormField).at(1);
    await tester.enterText(pathField, 'ABC-def/');
    expect(tester.widget<TextFormField>(pathField).controller!.text, 'def/');
  });
  testWidgets('plugin uninstall dialog counts down before confirming', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: const PluginUninstallDialog(
          pluginName: 'Demo',
          configNames: ['配置 A'],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('3 秒后确认'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 秒后确认'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 秒后确认'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('确认卸载'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    final scheme = Theme.of(
      tester.element(find.byType(PluginUninstallDialog)),
    ).colorScheme;
    expect(button.style!.backgroundColor!.resolve({}), scheme.error);
  });
  testWidgets('plugin uninstall can skip the countdown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: const PluginUninstallDialog(
          pluginName: 'Demo',
          configNames: [],
          countdown: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认卸载'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
  test('Android uses the predictive back transition', () {
    final builders = heroTheme(Brightness.light).pageTransitionsTheme.builders;
    final transition = builders[TargetPlatform.android];
    expect(transition, isA<PredictiveBackPageTransitionsBuilder>());
    expect(transition!.transitionDuration, const Duration(milliseconds: 220));
    expect(
      transition.reverseTransitionDuration,
      const Duration(milliseconds: 180),
    );
  });
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
      await tester.drag(
        find.byKey(const PageStorageKey('settings')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(find.text('上传后删除原图'), findsOneWidget);
      expect(find.text('完成上传后删除本地图片'), findsOneWidget);
      expect(find.text('同步删除云端文件'), findsNothing);
      expect(find.text('同步删除本地原图'), findsNothing);
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
    'camera upload asks for permission and offers app settings when denied',
    (tester) async {
      var requested = 0, openedSettings = 0;
      final controller = exampleController(images: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: heroTheme(Brightness.light),
          home: Scaffold(
            body: UploadPage(
              controller: controller,
              openRepositories: () {},
              openAlbum: () {},
              cameraPermission: CameraPermissionGate(
                status: () async => PermissionStatus.denied,
                request: () async {
                  requested++;
                  return PermissionStatus.permanentlyDenied;
                },
                openSettings: () async {
                  openedSettings++;
                  return true;
                },
                isMobile: () => true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('拍照上传'));
      await tester.pumpAndSettle();
      expect(requested, 1);
      expect(find.text('需要相机权限'), findsOneWidget);
      await tester.tap(find.text('前往设置'));
      await tester.pumpAndSettle();
      expect(openedSettings, 1);
      controller.dispose();
    },
  );
  testWidgets('album view indicator follows the selected tab', (tester) async {
    final controller = exampleController();
    await initialize(tester, controller);
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    for (final tab in const [
      ('列表', Icons.view_list_outlined),
      ('瀑布流', Icons.dashboard_outlined),
      ('网格', Icons.grid_view_rounded),
    ]) {
      await tester.tap(find.byTooltip(tab.$1));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('album-view-indicator'))).dx,
        closeTo(tester.getCenter(find.byIcon(tab.$2)).dx, .5),
        reason: '遮罩未对齐到 ${tab.$1}',
      );
    }
    expect(find.byTooltip('列表'), findsOneWidget);
    await tester.tap(find.byTooltip('网格'));
    await tester.pumpAndSettle();
    debugDisableShadows = true;
    controller.dispose();
  });
  testWidgets('album pinch adjusts columns from blank area', (tester) async {
    final controller = exampleController();
    await initialize(tester, controller);
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    final before = tester
        .getSize(find.byKey(const ValueKey('album-card-aliyun:0')))
        .width;
    const anchor = Offset(195, 700);
    final left = await tester.startGesture(anchor - const Offset(100, 0));
    final right = await tester.startGesture(anchor + const Offset(100, 0));
    await tester.pump();
    await left.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(find.text('2 列'), findsOneWidget);
    await left.moveBy(const Offset(20, 0));
    await right.moveBy(const Offset(-20, 0));
    await tester.pumpAndSettle();
    await screenshot(tester, 'album-pinch-soft');
    for (var i = 0; i < 17; i++) {
      await left.moveBy(const Offset(5, 0));
      await right.moveBy(const Offset(-5, 0));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await screenshot(tester, 'album-pinch');
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('album-card-aliyun:0'))).width,
      lessThan(before),
    );
    SpUtil.putInt('hero_album_columns', 2);
    debugDisableShadows = true;
    controller.dispose();
  });
  testWidgets('album grid keeps full width at every pinch level', (
    tester,
  ) async {
    final controller = exampleController();
    await initialize(tester, controller);
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('album-card-aliyun:0'));

    int currentColumns() {
      for (var n = 2; n <= 6; n++) {
        if (find.byKey(ValueKey('album-grid-$n')).evaluate().isNotEmpty) {
          return n;
        }
      }
      fail('grid uses an unexpected column count');
    }

    void expectFlushLeft(int columns) {
      expect(currentColumns(), columns);
      expect(tester.getTopLeft(card).dx, closeTo(16, .5));
      expect(
        tester.getSize(card).width,
        closeTo((358 - (columns - 1) * 12) / columns, .5),
      );
    }

    expectFlushLeft(2);
    final center = tester.getCenter(card);
    final left = await tester.startGesture(center - const Offset(100, 0));
    final right = await tester.startGesture(center + const Offset(100, 0));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await left.moveBy(const Offset(4, 0));
      await right.moveBy(const Offset(-4, 0));
      await tester.pump();
      // 放大预览只允许溢出裁切，不能向内缩进留下两侧空白
      expect(tester.getTopLeft(card).dx, lessThanOrEqualTo(16.001));
    }
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    final settled = currentColumns();
    expect(settled, greaterThan(2));
    expectFlushLeft(settled);
    expect(SpUtil.getInt('hero_album_columns'), settled);
    SpUtil.putInt('hero_album_columns', 2);
    debugDisableShadows = true;
    controller.dispose();
  });
  testWidgets('album view switch never overlaps two layouts', (tester) async {
    final controller = exampleController();
    await initialize(tester, controller);
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    double opacityOf(String key) {
      final ancestors = find.ancestor(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Opacity),
      );
      if (ancestors.evaluate().isEmpty) return 0;
      return tester.widget<Opacity>(ancestors.first).opacity;
    }

    await tester.tap(find.byTooltip('列表'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      final grid = opacityOf('album-grid-false');
      final list = opacityOf('album-list-false');
      expect(
        (grid > .2 ? 1 : 0) + (list > .2 ? 1 : 0),
        lessThanOrEqualTo(1),
        reason: 'grid=$grid list=$list',
      );
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-list-false')), findsOneWidget);
    SpUtil.putString('hero_album_view', 'grid');
    debugDisableShadows = true;
    controller.dispose();
  });
  testWidgets(
    'gallery layouts, search, multi-select and default target selector',
    (tester) async {
      final controller = exampleController();
      await initialize(tester, controller);
      await screenshot(tester, 'upload');
      expect(find.text('blue_hour.png'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-1')));

      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('album-card-aliyun:0'))).width,
        closeTo(173, .1),
      );
      await screenshot(tester, 'album-grid');
      final center = tester.getCenter(
        find.byKey(const ValueKey('album-card-aliyun:0')),
      );
      final left = await tester.startGesture(center - const Offset(100, 0));
      final right = await tester.startGesture(center + const Offset(100, 0));
      await tester.pump();
      for (var i = 0; i < 17; i++) {
        await left.moveBy(const Offset(5, 0));
        await right.moveBy(const Offset(-5, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-grid-6')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('album-card-aliyun:0'))).width,
        closeTo((358 - 60) / 6, .1),
      );
      await screenshot(tester, 'album-grid-zoomed');

      final zoomOutLeft = await tester.startGesture(
        center - const Offset(15, 0),
      );
      final zoomOutRight = await tester.startGesture(
        center + const Offset(15, 0),
      );
      await tester.pump();
      for (var i = 0; i < 17; i++) {
        await zoomOutLeft.moveBy(const Offset(-5, 0));
        await zoomOutRight.moveBy(const Offset(5, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await zoomOutLeft.up();
      await zoomOutRight.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album-grid-2')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('album-card-aliyun:0'))).width,
        closeTo(173, .1),
      );
      await tester.tap(find.byTooltip('网格'));
      await tester.pumpAndSettle();
      expect(find.text('blue_hour.png'), findsOneWidget);
      await tester.tap(find.byTooltip('瀑布流'));

      await tester.pumpAndSettle();
      await screenshot(tester, 'album-masonry');
      expect(
        tester.getSize(find.byKey(const ValueKey('album-card-aliyun:0'))).width,
        closeTo(358, .1),
      );
      await tester.tap(find.byTooltip('列表'));

      await tester.pump(const Duration(milliseconds: 80));
      await screenshot(tester, 'album-switch-mid');
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
  testWidgets(
    'system back dismisses the sheet before exiting album selection',
    (tester) async {
      final controller = exampleController();
      await initialize(tester, controller);
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('blue_hour.png'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1'), findsOneWidget);
      await tester.tap(find.text('全部相册'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('已选 1'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('结束多选'), findsNothing);
      expect(find.text('已选 1'), findsNothing);
      expect(find.byTooltip('多选图片'), findsOneWidget);
      await tester.longPress(find.text('blue_hour.png'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-2')));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('nav-2'))),
      )!;
      expect(route.popDisposition, isNot(RoutePopDisposition.doNotPop));
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('结束多选'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
      controller.dispose();
    },
  );

  testWidgets(
    'details offer cloud delete only for supporting hosts and retain the record',
    (tester) async {
      final registry = TestDeleteRegistry();
      final controller = exampleController(uploaderRegistry: registry);
      await initialize(tester, controller, size: const Size(320, 780));
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await tester.pumpAndSettle();
      Future<void> details() async {
        await tester.tap(find.text('blue_hour.png').first);
        await tester.pumpAndSettle();
      }

      await details();
      final button = find.byKey(const ValueKey('delete-cloud-image'));
      expect(button, findsOneWidget);
      await Scrollable.ensureVisible(tester.element(button));
      await tester.pumpAndSettle();
      await screenshot(tester, 'album-cloud-delete');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(registry.calls, isEmpty);
      expect(find.text('删除这张云端图片？'), findsOneWidget);
      await tester.tap(find.text('确认删除云端图片'));
      await tester.pumpAndSettle();
      expect(registry.calls, hasLength(1));
      expect(controller.images, hasLength(6));
      await details();
      expect(
        find.descendant(of: button, matching: find.text('云端图片已删除')),
        findsOneWidget,
      );
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      registry.supported = false;
      await details();
      expect(button, findsNothing);
      expect(find.text('删除上传记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
      controller.dispose();
    },
  );

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
  testWidgets('horizontal drag previews a tab and commits it on release', (
    tester,
  ) async {
    final controller = exampleController();
    await initialize(tester, controller);
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    Color? iconColor(int index) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey('nav-$index')),
            matching: find.byType(Icon),
          ),
        )
        .color;

    expect(pager.page, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('nav-0'))),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('nav-2'))));
    await tester.pumpAndSettle();
    expect(pager.page, 0);
    expect(iconColor(0), heroMuted);
    expect(iconColor(2), Colors.white);
    expect(find.textContaining('松开前往'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(pager.page, 2);
    expect(iconColor(0), heroMuted);
    expect(iconColor(2), Colors.white);
    expect(tester.takeException(), isNull);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('navigation indicator stays inside the bar at both ends', (
    tester,
  ) async {
    final controller = exampleController();
    await initialize(tester, controller);
    final surface = find.byKey(const ValueKey('nav-surface'));
    final indicator = find.byKey(const ValueKey('nav-indicator'));
    final bounds = tester.getRect(surface);

    await tester.tap(find.byKey(const ValueKey('nav-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getRect(indicator).right, lessThanOrEqualTo(bounds.right));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getRect(indicator).left, greaterThanOrEqualTo(bounds.left));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'bottom navigation labels can be hidden and restored from appearance settings',
    (tester) async {
      final controller = exampleController();
      await initialize(tester, controller);
      Finder navLabel(int index, String label) => find.descendant(
        of: find.byKey(ValueKey('nav-$index')),
        matching: find.text(label),
      );
      expect(navLabel(0, '上传'), findsOneWidget);
      final expandedHeight = tester
          .getSize(find.byKey(const ValueKey('nav-0')))
          .height;

      await tester.tap(find.byKey(const ValueKey('nav-3')));
      await tester.pumpAndSettle();
      final settingRow = find.ancestor(
        of: find.text('底部导航文字'),
        matching: find.byType(ListTile),
      );
      final toggle = find.descendant(
        of: settingRow,
        matching: find.byType(Switch),
      );
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(controller.showNavigationLabels, false);
      expect(SpUtil.getBool('hero_show_navigation_labels'), false);
      for (final (index, label) in ['上传', '相册', '仓库', '设置'].indexed) {
        expect(navLabel(index, label), findsNothing);
        expect(find.byKey(ValueKey('nav-$index')), findsOneWidget);
      }
      final compactHeight = tester
          .getSize(find.byKey(const ValueKey('nav-0')))
          .height;
      expect(compactHeight, lessThan(expandedHeight));
      expect(compactHeight, greaterThanOrEqualTo(48));
      await screenshot(tester, 'navigation-icons-only');

      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-3')));
      await tester.pumpAndSettle();
      expect(navLabel(3, '设置'), findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(controller.showNavigationLabels, true);
      expect(SpUtil.getBool('hero_show_navigation_labels'), true);
      expect(navLabel(0, '上传'), findsOneWidget);
      expect(navLabel(3, '设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
      controller.dispose();
    },
  );
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
