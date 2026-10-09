import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picora/hero/app_updates.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/github_mirrors.dart';
import 'package:picora/hero/github_mirror_page.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/module_repository_page.dart';
import 'package:picora/hero/plugins/plugin_catalog.dart';
import 'package:picora/hero/plugins/plugin_manager.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';

import 'app_update_test.dart' show releaseJson, mockDio;
import 'plugin_catalog_test.dart'
    show entryJson, indexSource, FixedCatalogService;
import 'plugin_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mirrors = GitHubMirrors.instance;
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await SpUtil.remove(GitHubMirrors.preferenceKey);
    await Directory('artifacts').create(recursive: true);
    root = await Directory('artifacts').createTemp('mirror-tests-');
  });
  tearDown(() async {
    await SpUtil.remove(GitHubMirrors.preferenceKey);
    await root.delete(recursive: true);
  });

  test('all presets prefix public GitHub URLs and default to direct', () async {
    final sources = [
      PluginCatalogService.indexUrl,
      AppUpdateService.latestUrl,
      'https://github.com/Alnitak44/Picora/releases/download/v1.0.2/Picora-arm64-release.apk',
    ];
    expect(mirrors.selected.id, 'direct');
    for (final preset in GitHubMirrors.presets) {
      await mirrors.select(preset.id);
      for (final source in sources) {
        expect(
          mirrors.resolve(Uri.parse(source)).toString(),
          preset.baseUrl == null ? source : '${preset.baseUrl}$source',
        );
      }
    }
  });

  test(
    'custom mirrors persist, support subpaths and editing; removing active resets direct',
    () async {
      await mirrors.saveCustom(name: '', url: ' https://mirror.example/proxy ');
      final entry = mirrors.options.last;
      expect(entry.name, 'mirror.example');
      await mirrors.select(entry.id);
      final source = Uri.parse(PluginCatalogService.indexUrl);
      expect(
        GitHubMirrors().resolve(source).toString(),
        'https://mirror.example/proxy/$source',
      );
      await mirrors.saveCustom(
        id: entry.id,
        name: '新线路',
        url: 'https://new.example/',
      );
      expect(mirrors.selected.id, entry.id);
      expect(mirrors.selected.name, '新线路');
      expect(mirrors.resolve(source).host, 'new.example');
      await expectLater(
        mirrors.saveCustom(name: '重复', url: 'https://new.example'),
        throwsA(isA<HeroFailure>()),
      );
      await mirrors.remove(entry.id);
      expect(mirrors.selected.id, 'direct');
      expect(mirrors.options.length, 4);
      await expectLater(mirrors.remove('gh2i'), throwsA(isA<HeroFailure>()));
    },
  );

  test(
    'invalid roots and tampered preferences cannot construct unsafe URLs',
    () async {
      for (final url in [
        'http://proxy.example/',
        'file:///tmp/',
        'https://user:pass@proxy.example/',
        'https://proxy.example/?token=x',
        'https://proxy.example/#x',
        'https://proxy.example/https://github.com/',
        'https://github.com/',
      ]) {
        expect(
          () => GitHubMirrors.normalizeBase(url),
          throwsA(isA<HeroFailure>()),
          reason: url,
        );
      }
      await SpUtil.putString(
        GitHubMirrors.preferenceKey,
        jsonEncode({
          'selected': 'custom-bad',
          'custom': [
            {'id': 'custom-bad', 'name': '恶意', 'url': 'http://unsafe.example'},
          ],
        }),
      );
      expect(mirrors.selected.id, 'direct');
      expect(mirrors.options.length, 4);
    },
  );

  test('non-GitHub and credential-bearing requests bypass mirrors', () async {
    await mirrors.select('ghproxy');
    for (final source in [
      'https://github.com.evil.example/file.zip',
      'https://uploads.example/upload',
      'https://gh-proxy.com/https://github.com/a/b',
      'http://github.com/a/b',
      'https://github.com:8443/a/b',
      'https://user:secret@github.com/a/b',
      'https://github.com/a/b?token=secret',
      'https://github.com/a/b#secret',
    ]) {
      final uri = Uri.parse(source);
      expect(mirrors.resolve(uri), uri);
    }
    final uri = Uri.parse(AppUpdateService.latestUrl);
    for (final header in ['Authorization', 'cookie', 'pRoXy-AuThOrIzAtIoN']) {
      expect(mirrors.resolve(uri, headers: {header: 'secret'}), uri);
    }
  });

  test(
    'catalog and ZIP use selected route, re-fetch after switching, retain checksum verification',
    () async {
      final package = telegraphPackage();
      final entry = PluginCatalogEntry.fromJson(entryJson(package));
      final requests = <String>[];
      final dio = mockDio((request, handler) {
        requests.add(request.uri.toString());
        handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: request.uri.toString().endsWith('index.json')
                ? utf8.encode(indexSource(entryJson(package)))
                : package.bytes,
          ),
        );
      });
      final service = PluginCatalogService(dio: dio, storageRoot: root);
      final manager = PicoraPluginManager(
        registry: UploaderRegistry(),
        storageRoot: root,
        downloadDio: dio,
      );
      await mirrors.select('gh2i');
      await service.load();
      await service.load();
      expect(requests.length, 1);
      await mirrors.select('ghproxy');
      await service.load();
      // Fresh disk cache also belongs to its download route.
      final reopened = PluginCatalogService(dio: dio, storageRoot: root);
      await reopened.load();
      expect(requests.length, 2);
      await mirrors.select('akams');
      final switched = PluginCatalogService(dio: dio, storageRoot: root);
      await switched.load();
      expect(requests.length, 3);
      expect(
        requests[2],
        'https://github.akams.cn/${PluginCatalogService.indexUrl}',
      );
      await mirrors.select('ghproxy');
      final downloaded = await service.download(entry, manager);
      expect(downloaded.manifest.id, entry.id);
      expect(requests[0], 'https://gh.2i.gs/${PluginCatalogService.indexUrl}');
      expect(
        requests[1],
        'https://gh-proxy.com/${PluginCatalogService.indexUrl}',
      );
      expect(requests[3], 'https://gh-proxy.com/${entry.downloadUrl}');
      expect(() => entry.verify([0, 1, 2]), throwsA(isA<HeroFailure>()));
      // Canonical identities remain GitHub URLs.
      expect(entry.downloadUrl.host, 'github.com');
    },
  );

  test(
    'release API accepts text JSON and clears cache/ETag when route changes',
    () async {
      final requests = <RequestOptions>[];
      final service = AppUpdateService(
        dio: mockDio((request, handler) {
          requests.add(request);
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: jsonEncode(releaseJson()),
              headers: Headers.fromMap({
                'etag': ['test-etag'],
              }),
            ),
          );
        }),
      );
      await mirrors.select('gh2i');
      final release = await service.latest();
      expect(release!.apks.single.url.host, 'github.com');
      expect(release.apks.single.sha256, List.filled(64, 'a').join());
      await service.latest();
      expect(requests.length, 1);
      await service.latest(forceRefresh: true);
      expect(requests.last.headers['If-None-Match'], 'test-etag');
      await mirrors.select('ghproxy');
      await service.latest();
      expect(requests.length, 3);
      expect(
        requests.last.uri.toString(),
        'https://gh-proxy.com/${AppUpdateService.latestUrl}',
      );
      expect(requests.last.headers.containsKey('If-None-Match'), isFalse);
    },
  );

  test('mirror 404 is an error rather than a missing release', () async {
    final service = AppUpdateService(
      dio: mockDio((request, handler) {
        handler.resolve(Response(requestOptions: request, statusCode: 404));
      }),
    );
    await mirrors.select('akams');
    await expectLater(service.latest(), throwsA(isA<HeroFailure>()));
    await mirrors.select('direct');
    expect(await service.latest(), isNull);
  });

  testWidgets(
    'mirror UI selects routes and adds a custom entry on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: heroTheme(Brightness.dark),
          home: const GitHubMirrorPage(),
        ),
      );
      await tester.tap(find.text('gh.2i.gs'));
      await tester.pumpAndSettle();
      expect(mirrors.selected.id, 'gh2i');
      await tester.tap(find.byTooltip('添加镜像'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '自定义线路');
      await tester.enterText(
        find.byType(TextField).last,
        'https://custom.example/path/',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(mirrors.options.last.name, '自定义线路');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline catalog shows the requested network/mirror/retry message',
    (tester) async {
      final controller = PicoraController()..initializing = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: heroTheme(Brightness.dark),
          home: ModuleRepositoryPage(
            controller: controller,
            review: (_) async => false,
            service: FixedCatalogService(
              PluginCatalog([], DateTime.now(), refreshError: 'offline'),
            ),
            appVersionLoader: () async => '1.0.2',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('插件获取失败，请检查网络、前往设置切换镜像或点击右上角重试。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
