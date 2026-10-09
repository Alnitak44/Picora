import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picora/hero/controller.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/plugin_page.dart';
import 'package:picora/hero/plugins/plugin_manager.dart';
import 'package:picora/hero/plugins/plugin_package.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';

import 'plugin_package_test.dart' show packageBytes;

const quote = '这是第三方适配插件，不代表 ImgLoc 官方。';
const tutorial = '''
# 使用教程

支持 **加粗**、*强调* 和 [项目链接](https://github.com/Alnitak44/Picora)。

> 这是第三方适配插件，不代表 ImgLoc 官方。

## 配置

1. 添加图床配置。
2. 选择图片上传，支持中文换行与行内代码 `token`。

```json
{"url":"https://example.com/very/long/path/that/must/scroll/horizontally/image.png","ok":true}
```

| 参数 | 描述 | 示例 |
| --- | --- | --- |
| endpoint | 图床上传地址 | https://example.com/very/long/path/to/upload |
| token | 临时上传凭证 | 自动获取 |

---

正文与引用均应清晰可读。
''';

class DownloadFixture extends PicoraPluginManager {
  final Uint8List bytes;
  DownloadFixture(this.bytes) : super(registry: UploaderRegistry());
  @override
  Future<Uint8List> fetch(Uri uri) async => bytes;
}

Color? spanColor(
  InlineSpan span,
  String needle, [
  TextStyle parent = const TextStyle(),
]) {
  if (span is! TextSpan) return null;
  final style = parent.merge(span.style);
  if (span.text?.contains(needle) == true) return style.color;
  for (final child in span.children ?? <InlineSpan>[]) {
    final color = spanColor(child, needle, style);
    if (color != null) return color;
  }
  return null;
}

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

ThemeData previewTheme(Brightness brightness) {
  final theme = heroTheme(brightness);
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'PicoraPreview'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await Directory('artifacts').create(recursive: true);
    // Optional local fonts make maintainer previews legible; CI needs no fonts.
    for (final entry in {
      'PicoraPreview': 'C:/Windows/Fonts/msyh.ttc',
      'monospace': 'C:/Windows/Fonts/consola.ttf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        final loader = FontLoader(entry.key);
        loader.addFont(
          Future.value(ByteData.sublistView(await file.readAsBytes())),
        );
        await loader.load();
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'README contrast and readable blocks in ${brightness.name} theme',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final package = PicoraPluginPackage.decode(
          packageBytes(changes: {'readme.md': utf8.encode(tutorial)}),
        );
        final controller = PicoraController()..initializing = false;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: previewTheme(brightness),
              home: PluginReadmePage(package: package, controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final quoteFinder = find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.textSpan?.toPlainText().contains(quote) == true,
        );
        expect(quoteFinder, findsOneWidget);
        final text = tester.widget<SelectableText>(quoteFinder);
        final foreground = spanColor(text.textSpan!, quote)!;
        final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
        final styles = markdown.styleSheet!;
        final background =
            (styles.blockquoteDecoration! as BoxDecoration).color!;
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        expect(
          contrast(styles.code!.color!, styles.code!.backgroundColor!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(
            styles.a!.color!,
            heroTheme(brightness).scaffoldBackgroundColor,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(quoteFinder);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'artifacts/markdown-${brightness.name}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets(
      'README wraps prose and scrolls long code/tables with large text in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final package = PicoraPluginPackage.decode(
          packageBytes(changes: {'readme.md': utf8.encode(tutorial)}),
        );
        final controller = PicoraController()..initializing = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: previewTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 780),
                textScaler: TextScaler.linear(1.5),
              ),
              child: PluginReadmePage(package: package, controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
        expect(markdown.styleSheet!.textScaler!.scale(14), 21);
        final horizontal = find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        );
        expect(horizontal, findsNWidgets(2));
        for (final scroll in [horizontal.first, horizontal.last]) {
          await tester.ensureVisible(scroll);
          await tester.pumpAndSettle();
          await tester.dragFrom(
            tester.getBottomLeft(scroll) + const Offset(150, -3),
            const Offset(-100, 0),
          );
          await tester.pumpAndSettle();
          final scrollable = find.descendant(
            of: scroll,
            matching: find.byType(Scrollable),
          );
          final state = tester.state<ScrollableState>(scrollable.first);
          expect(state.position.pixels, greaterThan(0));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'install review keeps permission list and action without redundant explanation',
    (tester) async {
      final package = PicoraPluginPackage.decode(packageBytes());
      final manager = DownloadFixture(package.bytes);
      final controller = PicoraController(
        uploaderRegistry: manager.registry,
        pluginManager: manager,
      )..initializing = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: heroTheme(Brightness.dark),
          home: PluginCenterPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FloatingActionButton, '安装插件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从 URL 安装'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/plugin.zip',
      );
      await tester.tap(find.text('下载并检查'));
      await tester.pumpAndSettle();
      expect(find.text('权限'), findsOneWidget);
      expect(find.text('读取你主动选择上传的文件'), findsOneWidget);
      expect(find.text('允许并安装'), findsOneWidget);
      expect(find.textContaining('插件只接收当前配置'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
