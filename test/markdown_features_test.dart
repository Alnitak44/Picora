import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/filename_template.dart';
import 'package:picora/hero/filename_template_sheet.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/markdown_documents.dart';
import 'package:picora/hero/markdown_images.dart';
import 'package:picora/hero/markdown_migration.dart';
import 'package:picora/hero/markdown_migration_page.dart';
import 'package:picora/hero/models.dart';

class FeaturePaths extends PathProviderPlatform {
  final String path;
  FeaturePaths(this.path);
  @override
  Future<String> getApplicationSupportPath() async => path;
}

class FakeDocuments extends MarkdownDocumentService {
  final List<Uint8List> outputs = [];
  bool cancelSave = false;
  @override
  Future<MarkdownSourceFile?> pick() async => MarkdownSourceFile(
    'content://test/original',
    '笔记.md',
    Uint8List.fromList(utf8.encode('![图](https://old.example/a.png)\r\n')),
  );
  @override
  Future<String?> saveNew(String name, Uint8List bytes) async {
    outputs.add(bytes);
    return cancelSave ? null : 'content://test/output';
  }
}

class FakeMigrationController extends PicoraController {
  @override
  Future<MarkdownMigrationResult> migrateMarkdown(
    String text,
    RepositoryConfig destination,
    MigrationCancellation cancellation, {
    MarkdownMigrator? migrator,
  }) async => MarkdownMigrationResult(
    MarkdownImageDocument.parse(text),
    {'https://old.example/a.png': 'https://new.example/a.png'},
    [],
    false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUpAll(() async {
    HttpOverrides.global = null;
    await Directory('artifacts').create(recursive: true);
    root = await Directory('artifacts').createTemp('markdown-tests-');
    PathProviderPlatform.instance = FeaturePaths(root.absolute.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDownAll(() async {
    await root.delete(recursive: true);
  });

  test(
    'nested list images are included while quoted and nested fences remain untouched',
    () {
      const text =
          '- item\n    ![real](https://old.test/list.png)\n'
          '    ```md\n    ![code](https://ignored.test/code.png)\n    ```\n'
          '> ```md\n> ![quote code](https://ignored.test/quote.png)\n> ```\n'
          '> ![quoted image](https://old.test/quote.png)\n';
      final parsed = MarkdownImageDocument.parse(text);
      expect(parsed.remoteUris.map((e) => e.toString()), [
        'https://old.test/list.png',
        'https://old.test/quote.png',
      ]);
    },
  );
  test(
    'filename hashes describe actual bytes, preserve extension and repeated dots',
    () async {
      final file = await File(
        '${root.path}/photo.original.jpg',
      ).writeAsString('abc');
      final result = await renderFilenameTemplate(
        file,
        '{filename}_{date}_{year}_{Y}{m}{d}_{h}{i}{s}_{ms}_{md5}_{md5-16}_{sha256}',
        now: DateTime(2026, 10, 6, 8, 9, 10, 12),
      );
      expect(
        result,
        'photo.original_2026-10-06_2026_20261006_080910_012_'
        '900150983cd24fb0d6963f7d28e17f72_900150983cd24fb0_'
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.jpg',
      );
      expect(validateFilenameTemplate('../{filename}'), isNotNull);
      expect(validateFilenameTemplate('{unknown}'), isNotNull);
      expect(validateFilenameTemplate('{str-100000}'), isNotNull);
      expect(validateFilenameTemplate('{str-0}'), isNotNull);
      final random = await renderFilenameTemplate(file, '{uuid}_{str-8}');
      expect(random, matches(RegExp(r'^[0-9a-f]{32}_[A-Za-z0-9]{8}\.jpg$')));
    },
  );

  test(
    'inline images retain titles, escaped parentheses, CRLF and ordinary hyperlinks',
    () {
      const text =
          '# 标题\r\n![a](https://old.test/a.png "保留标题")\r\n'
          r'![b](https://old.test/b\(1\).png)'
          '\r\n'
          '[普通链接](https://old.test/a.png)\r\n'
          '[![带链接图](<https://old.test/a.png>)](https://old.test/a.png)\r\n';
      final parsed = MarkdownImageDocument.parse(text);
      expect(parsed.images, hasLength(3));
      expect(parsed.remoteUris.map((e) => e.toString()), [
        'https://old.test/a.png',
        'https://old.test/b(1).png',
      ]);
      final output = parsed.replace({
        'https://old.test/a.png': 'https://new.test/image(2).png',
      });
      expect(
        output,
        contains('![a](https://new.test/image%282%29.png "保留标题")'),
      );
      expect(output, contains('[普通链接](https://old.test/a.png)'));
      expect(
        output,
        contains(
          '[![带链接图](<https://new.test/image%282%29.png>)](https://new.test/image%282%29.png)',
        ),
      );
      expect(output.split('\r\n').length, text.split('\r\n').length);
    },
  );

  test(
    'reference images resolve explicit, collapsed and shortcut labels without changing text links',
    () {
      const text =
          '![照片][ID]\n![ID][]\n![id]\n[普通][ID]\n\n'
          '[ID]: <https://old.test/a.png> "标题"\n';
      final parsed = MarkdownImageDocument.parse(text);
      expect(parsed.images, hasLength(3));
      final result = parsed.replace({
        'https://old.test/a.png': 'https://new.test/a.png',
      });
      expect(result, contains('![照片](<https://new.test/a.png> "标题")'));
      expect(result, contains('[普通][ID]'));
      expect(result, contains('[ID]: <https://old.test/a.png> "标题"'));
    },
  );

  test(
    'HTML image src handles entities and does not mistake data-src or code for images',
    () {
      const text =
          '<img data-src="https://ignored.test/a.png" src="https://old.test/a.png?a=1&amp;b=2" alt="图">\n'
          '`![code](https://ignored.test/b.png)`\n'
          '```md\n![example](https://ignored.test/c.png)\n```\n'
          '~~~\n<img src="https://ignored.test/d.png">\n~~~\n'
          '<!-- ![comment](https://ignored.test/e.png) -->\n'
          '    ![indented code](https://ignored.test/f.png)\n'
          r'\![escaped](https://ignored.test/g.png)'
          '\n'
          '![local](./images/local.png)\n![inline](data:image/png;base64,AAA)\n';
      final parsed = MarkdownImageDocument.parse(text);
      expect(parsed.images, hasLength(3));
      expect(
        parsed.remoteUris.single.toString(),
        'https://old.test/a.png?a=1&b=2',
      );
      final result = parsed.replace({
        'https://old.test/a.png?a=1&b=2': 'https://new.test/a.png?a=3&b=4',
      });
      expect(
        result,
        contains(
          'data-src="https://ignored.test/a.png" src="https://new.test/a.png?a=3&amp;b=4"',
        ),
      );
      expect(result, contains('![example](https://ignored.test/c.png)'));
    },
  );

  test(
    'many duplicate image references are replaced without touching unrelated text',
    () {
      final text = List.filled(5000, '![a](https://old.test/a.png)\n').join();
      final document = MarkdownImageDocument.parse(text);
      expect(document.remoteUris, hasLength(1));
      expect(
        document.replace({'https://old.test/a.png': 'https://new.test/a.png'}),
        List.filled(5000, '![a](https://new.test/a.png)\n').join(),
      );
    },
  );

  test(
    'migration deduplicates downloads, continues after stale links and captures HTTP diagnostics',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final counts = <String, int>{};
      final png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3];
      server.listen((request) async {
        try {
          counts.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
          if (request.uri.path == '/gone.png') {
            request.response.statusCode = 410;
          } else if (request.uri.path == '/blocked.png') {
            request.response.statusCode = 403;
          } else if (request.uri.path == '/html.png') {
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.write('<html>Login required</html>');
          } else {
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.add(png);
          }
          await request.response.close();
        } catch (_) {}
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final source =
            '![a]($base/ok.png)\n![dup]($base/ok.png)\n'
            '![gone]($base/gone.png)\n![blocked]($base/blocked.png)\n![html]($base/html.png)';
        var uploads = 0;
        final result = await MarkdownMigrator().migrate(
          source,
          imageDirectory: Directory('${root.path}/images'),
          cancellation: MigrationCancellation(),
          targetId: 'aliyun:B',
          upload: (file) async {
            uploads++;
            expect(await file.readAsBytes(), png);
            return 'https://new.test/ok.png';
          },
        );
        expect(uploads, 1);
        expect(counts['/ok.png'], 1);
        expect(result.successful, 1);
        expect(result.replacedOccurrences, 2);
        expect(result.issues, hasLength(3));
        expect(result.issues.map((e) => e.message).join(), contains('410'));
        expect(result.text, contains('![gone]($base/gone.png)'));
        expect(result.text, contains('![a](https://new.test/ok.png)'));
        expect(result.issues.first.diagnostics['network']['status'], 410);
        expect(result.report(), contains('诊断编号'));
        expect(result.report(), contains('"stack"'));
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'image size limits and download timeout are explicit and leave source untouched',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        try {
          if (request.uri.path == '/slow.png') {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(List.filled(100, 65));
          await request.response.close();
        } catch (_) {}
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final source = '![large]($base/large.png)\n![slow]($base/slow.png)';
        final result =
            await MarkdownMigrator(
              downloader: MarkdownImageDownloader(
                maxBytes: 64,
                timeout: const Duration(milliseconds: 150),
              ),
            ).migrate(
              source,
              imageDirectory: Directory('${root.path}/limited'),
              cancellation: MigrationCancellation(),
              upload: (_) async =>
                  throw StateError('Must not upload failed downloads'),
            );
        expect(result.text, source);
        expect(result.issues, hasLength(2));
        expect(result.issues.first.message, contains('超过'));
        expect(result.issues.last.message, contains('超时'));
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'cancellation keeps completed uploads and avoids remaining downloads',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var downloaded = 0;
      server.listen((request) async {
        downloaded++;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([137, 80, 78, 71, 13, 10, 26, 10]);
        await request.response.close();
      });
      final cancellation = MigrationCancellation();
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final result = await MarkdownMigrator().migrate(
          '![a]($base/a.png)\n![b]($base/b.png)',
          imageDirectory: Directory('${root.path}/cancelled'),
          cancellation: cancellation,
          upload: (_) async {
            cancellation.cancel();
            return 'https://new.test/a.png';
          },
        );
        expect(result.cancelled, isTrue);
        expect(result.successful, 1);
        expect(result.remaining, 1);
        expect(downloaded, 1);
        expect(result.text, contains('![b]($base/b.png)'));
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'document output preserves BOM/CRLF and overwrite uses original URI, checksum and backup',
    () async {
      final bytes = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('# 中文\r\n![a](https://old.test/a.png)\r\n'),
      ]);
      final source = MarkdownSourceFile(
        'content://documents/original',
        'note.md',
        bytes,
      );
      final converted = source.encode(
        source.text.replaceAll('old.test', 'new.test'),
      );
      expect(converted.take(3), [0xef, 0xbb, 0xbf]);
      expect(utf8.decode(converted), contains('\r\n'));
      Map? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MarkdownDocumentService.channel, (
            call,
          ) async {
            if (call.method == 'overwriteMarkdown') {
              received = call.arguments as Map;
              return null;
            }
            return null;
          });
      final service = MarkdownDocumentService();
      await service.overwrite(source, converted);
      expect(received!['uri'], 'content://documents/original');
      expect(received!['expectedMd5'], md5.convert(bytes).toString());
      expect(received!['bytes'], converted);
      expect(await File(service.backupPath!).readAsBytes(), bytes);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MarkdownDocumentService.channel,
            (_) async => throw PlatformException(code: 'DOCUMENT_CHANGED'),
          );
      await expectLater(
        service.overwrite(source, converted),
        throwsA(
          isA<HeroFailure>().having(
            (e) => e.message,
            'message',
            contains('已被其他程序修改'),
          ),
        ),
      );
      expect(await File(service.backupPath!).readAsBytes(), bytes);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MarkdownDocumentService.channel, null);
    },
  );

  testWidgets(
    'filename variable replaces the active text selection at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: heroTheme(Brightness.dark),
          home: const Scaffold(
            body: FilenameTemplateSheet(initial: 'pre_old_post'),
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 7,
      );
      await tester.ensureVisible(find.text('{date}'));
      await tester.tap(find.text('{date}'));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'pre_{date}_post');
      expect(field.controller!.selection.extentOffset, 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown screen saves migrated output and remains usable at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const destination = RepositoryConfig(
        host: 'aliyun',
        slot: 'B',
        name: '备用图床',
        values: {},
      );
      final controller = FakeMigrationController()
        ..target = destination
        ..repositories = [destination]
        ..initializing = false;
      final documents = FakeDocuments();
      await tester.pumpWidget(
        MaterialApp(
          theme: heroTheme(Brightness.dark),
          home: MarkdownMigrationPage(
            controller: controller,
            documents: documents,
          ),
        ),
      );
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始替换'));
      await tester.tap(find.text('开始替换'));
      await tester.pumpAndSettle();
      expect(documents.outputs, hasLength(1));
      expect(
        utf8.decode(documents.outputs.single),
        '![图](https://new.example/a.png)\r\n',
      );
      expect(find.text('Markdown 已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled save protects unsaved migration when leaving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const destination = RepositoryConfig(
      host: 'aliyun',
      slot: 'A',
      name: '目标图床',
      values: {},
    );
    final controller = FakeMigrationController()
      ..target = destination
      ..repositories = [destination]
      ..initializing = false;
    final documents = FakeDocuments()..cancelSave = true;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: heroTheme(Brightness.light),
        home: const Scaffold(body: Text('上传首页')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MarkdownMigrationPage(controller: controller, documents: documents),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始替换'));
    await tester.tap(find.text('开始替换'));
    await tester.pumpAndSettle();
    expect(find.text('Markdown 已保存'), findsNothing);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('处理结果尚未保存'), findsOneWidget);
    await tester.tap(find.text('继续保存结果'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownMigrationPage), findsOneWidget);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃结果并离开'));
    await tester.pumpAndSettle();
    expect(find.text('上传首页'), findsOneWidget);
    expect(find.byType(MarkdownMigrationPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
