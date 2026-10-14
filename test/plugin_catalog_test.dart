import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/module_repository_page.dart';
import 'package:picora/hero/plugin_page.dart';
import 'package:picora/hero/plugin_update_badge.dart';
import 'package:picora/hero/plugins/plugin_catalog.dart';
import 'package:picora/hero/plugins/plugin_manager.dart';
import 'package:picora/hero/plugins/plugin_package.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_fixture.dart';

Map<String, dynamic> entryJson(PicoraPluginPackage package) => {
  'id': package.manifest.id,
  'name': package.manifest.name,
  'description': package.manifest.description,
  'author': package.manifest.author,
  'version': package.manifest.version,
  'runtime': 'http-v1',
  'packageVersion': 1,
  'minAppVersion': '1.0.0',
  'example': true,
  'mark': 'TG',
  'repository': package.repository,
  'downloadUrl':
      'https://github.com/Alnitak44/picora-plugin-telegraph-image/releases/download/v1.1.2/telegraph-image-1.1.2.picora-plugin.zip',
  'size': package.bytes.length,
  'sha256': sha256.convert(package.bytes).toString(),
};
String indexSource(Map<String, dynamic> entry) => jsonEncode({
  'schemaVersion': 1,
  'plugins': [entry],
});

class FixedCatalogService extends PluginCatalogService {
  final PluginCatalog catalog;
  FixedCatalogService(this.catalog);
  @override
  Future<PluginCatalog> load({bool forceRefresh = false}) async => catalog;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await Directory('artifacts').create(recursive: true);
    root = await Directory('artifacts').createTemp('module-tests-');
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'catalog verifies ZIP size, checksum, identity and semantic versions',
    () {
      final package = telegraphPackage();
      final json = entryJson(package);
      final entry = PluginCatalogEntry.fromJson(json);
      expect(entry.verify(package.bytes).manifest.id, entry.id);
      expect(entry.supports('1.0.0-debug'), isTrue);
      expect(entry.isUpdateFor('1.1.0'), isTrue);
      expect(entry.isUpdateFor(package.manifest.version), isFalse);
      for (final changes in [
        {'size': package.bytes.length + 1},
        {'sha256': '0' * 64},
        {'id': 'other.plugin'},
        {'version': '9.0.0'},
        {'author': 'Another Author'},
      ]) {
        expect(
          () => PluginCatalogEntry.fromJson({
            ...json,
            ...changes,
          }).verify(package.bytes),
          throwsA(isA<HeroFailure>()),
        );
      }
      expect(() => entry.verify([1, 2, 3]), throwsA(isA<HeroFailure>()));
    },
  );

  test('example designation comes from the catalog, not package metadata', () {
    final package = telegraphPackage();
    expect(package.metadata.containsKey('example'), isFalse);
    final json = entryJson(package);
    expect(PluginCatalogEntry.fromJson(json).example, isTrue);
    expect(
      PluginCatalogEntry.fromJson({...json, 'example': false}).example,
      isFalse,
    );
    expect(
      PluginCatalogEntry.fromJson(
        json,
      ).verify(package.bytes).metadata.containsKey('example'),
      isFalse,
    );
  });

  test('catalog examples are pinned while other entry order is preserved', () {
    final source = entryJson(telegraphPackage());
    PluginCatalogEntry entry(String id, bool example) =>
        PluginCatalogEntry.fromJson({...source, 'id': id, 'example': example});
    final entries = [
      entry('test.zebra', false),
      entry('test.example', true),
      entry('test.alpha', false),
      entry('test.another-example', true),
    ];
    final catalog = PluginCatalog(entries, DateTime.utc(2026, 10, 11));
    expect(catalog.orderedEntries.map((entry) => entry.id), [
      'test.example',
      'test.another-example',
      'test.zebra',
      'test.alpha',
    ]);
    expect(catalog.entries, orderedEquals(entries));
    expect(
      catalog.orderedEntries
          .where((entry) => entry.id.contains('alpha'))
          .map((entry) => entry.id),
      ['test.alpha'],
    );
  });

  test('updates precede examples and keep stable order within each group', () {
    final source = entryJson(telegraphPackage());
    PluginCatalogEntry entry(String id, {bool example = false}) =>
        PluginCatalogEntry.fromJson({
          ...source,
          'id': id,
          'example': example,
          'version': '1.2.0',
        });
    final catalog = PluginCatalog([
      entry('test.uninstalled'),
      entry('test.example', example: true),
      entry('test.update'),
      entry('test.current'),
      entry('test.newer-local'),
      entry('test.update-example', example: true),
      entry('test.second-update'),
    ], DateTime.utc(2026, 10, 14));
    final versions = {
      'test.update': '1.1.0',
      'test.current': '1.2.0',
      'test.newer-local': '1.3.0',
      'test.update-example': '1.0.0',
      'test.second-update': '1.2.0-beta.1',
    };
    expect(catalog.orderedForInstalled(versions).map((entry) => entry.id), [
      'test.update-example',
      'test.update',
      'test.second-update',
      'test.example',
      'test.uninstalled',
      'test.current',
      'test.newer-local',
    ]);
    expect(
      catalog.orderedForInstalled({}),
      orderedEquals(catalog.orderedEntries),
    );
    versions['test.update'] = '1.2.0';
    expect(catalog.orderedForInstalled(versions).map((entry) => entry.id), [
      'test.update-example',
      'test.second-update',
      'test.example',
      'test.uninstalled',
      'test.update',
      'test.current',
      'test.newer-local',
    ]);
  });

  test('malformed and duplicate catalog entries are rejected', () {
    final json = entryJson(telegraphPackage());
    for (final changes in [
      {'downloadUrl': 'http://github.com/file.zip'},
      {'packageVersion': 2},
      {'runtime': 'node'},
      {'sha256': 'invalid'},
      {'size': 0},
      {'minAppVersion': 'latest'},
      {'version': '1.01.0'},
    ]) {
      expect(
        () => PluginCatalogEntry.fromJson({...json, ...changes}),
        throwsA(anything),
      );
    }
    expect(
      () => PluginCatalog.parse(
        jsonEncode({
          'schemaVersion': 1,
          'plugins': [json, json],
        }),
      ),
      throwsA(isA<HeroFailure>()),
    );
    expect(
      () => PluginCatalog.parse('<html>proxy</html>'),
      throwsFormatException,
    );
  });

  test(
    'catalog cache persists and failed refresh keeps last validated index',
    () async {
      var calls = 0;
      var time = DateTime.utc(2026, 10, 8);
      final source = indexSource(entryJson(telegraphPackage()));
      Dio network({bool fail = false}) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              calls++;
              if (fail) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionTimeout,
                  ),
                );
              } else {
                handler.resolve(
                  Response<List<int>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: utf8.encode(source),
                  ),
                );
              }
            },
          ),
        );
        return dio;
      }

      final first = PluginCatalogService(
        dio: network(),
        storageRoot: root,
        now: () => time,
      );
      final original = await first.load();
      expect((await first.load()), same(original));
      expect(calls, 1);
      final offline = PluginCatalogService(
        dio: network(fail: true),
        storageRoot: root,
        now: () => time,
      );
      expect(
        (await offline.load()).entries.single.id,
        original.entries.single.id,
      );
      expect(calls, 1);
      time = time.add(const Duration(hours: 13));
      final fallback = await offline.load();
      expect(fallback.offline, isTrue);
      expect(fallback.fetchedAt, original.fetchedAt);
      expect(fallback.entries.single.version, original.entries.single.version);
      expect(calls, 2);
    },
  );

  test('network failure without a cache is reported', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          ),
        ),
      ),
    );
    await expectLater(
      PluginCatalogService(dio: dio, storageRoot: root).load(),
      throwsA(isA<DioException>()),
    );
  });

  test(
    'old bundled configurations survive until same-ID download restores them',
    () async {
      final package = telegraphPackage();
      final file = File('${root.path}/picora-plugin-repositories.json');
      await file.writeAsString(
        jsonEncode([
          {
            'host': package.manifest.hostId,
            'slot': 'B',
            'name': '原图床',
            'values': {
              'baseUrl': 'https://old.example',
              'password': 'keep-secret',
            },
          },
        ]),
      );
      await SpUtil.putBool('hero_plugin_enabled_${package.manifest.id}', false);
      final registry = UploaderRegistry();
      final manager = PicoraPluginManager(
        storageRoot: root,
        registry: registry,
      );
      await manager.initialize();
      expect(manager.installed, isEmpty);
      final before = (await manager.readRepositories()).single;
      expect(before.values['password'], 'keep-secret');
      await expectLater(
        manager.saveRepository(before.spec, '覆盖', {}),
        throwsA(isA<HeroFailure>()),
      );
      await manager.installPackage(package.bytes);
      final after = (await manager.readRepositories()).single;
      expect(after.id, before.id);
      expect(after.values, before.values);
      expect(manager.isEnabled(package.manifest.id), isFalse);
      expect(registry.contains(package.manifest.hostId), isTrue);
      await expectLater(
        manager.remove(package.manifest.id),
        throwsA(isA<HeroFailure>()),
      );
      await manager.deleteRepository(after);
      await manager.remove(package.manifest.id);
      await manager.initialize(force: true);
      expect(manager.installed, isEmpty);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('update cards and installed badges refresh in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = UploaderRegistry();
      final manager = PicoraPluginManager(
        registry: registry,
        storageRoot: root,
      );
      final installed = telegraphPackage();
      final latest = telegraphPackage(version: '1.2.0');
      await tester.runAsync(() => manager.installPackage(installed.bytes));
      final controller = PicoraController(
        uploaderRegistry: registry,
        pluginManager: manager,
      )..initializing = false;
      addTearDown(controller.dispose);
      final latestJson = {...entryJson(latest), 'example': false};
      final catalog = PluginCatalog([
        PluginCatalogEntry.fromJson({
          ...entryJson(installed),
          'id': 'test.example',
          'name': 'Pinned Example',
        }),
        PluginCatalogEntry.fromJson(latestJson),
      ], DateTime.utc(2026, 10, 14));
      Widget app(Widget page) => MaterialApp(
        theme: heroTheme(brightness),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1100),
            textScaler: TextScaler.linear(1.5),
          ),
          child: page,
        ),
      );
      await tester.pumpWidget(
        app(
          ModuleRepositoryPage(
            controller: controller,
            review: (_) async => false,
            service: FixedCatalogService(catalog),
            appVersionLoader: () async => '1.0.6',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('可更新'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);
      expect(find.textContaining('更新至'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Telegraph-Image')).dy,
        lessThan(tester.getTopLeft(find.text('Pinned Example')).dy),
      );
      final updateButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '更新'),
      );
      expect(
        updateButton.style?.backgroundColor?.resolve({}),
        pluginUpdateColor,
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Pinned');
      await tester.pumpAndSettle();
      expect(find.text('可更新'), findsNothing);
      expect(find.text('Pinned Example'), findsOneWidget);
      await tester.pumpWidget(
        app(
          PluginCenterPage(
            controller: controller,
            service: FixedCatalogService(catalog),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('可更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => manager.installPackage(latest.bytes));
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('可更新'), findsNothing);
      await tester.pumpWidget(
        app(
          ModuleRepositoryPage(
            controller: controller,
            review: (_) async => false,
            service: FixedCatalogService(catalog),
            appVersionLoader: () async => '1.0.6',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('更新'), findsNothing);
      expect(find.text('已安装'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Pinned Example')).dy,
        lessThan(tester.getTopLeft(find.text('Telegraph-Image')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('module cards support narrow screens, large text and search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = PluginCatalog([
      PluginCatalogEntry.fromJson(entryJson(telegraphPackage())),
    ], DateTime.utc(2026, 10, 8));
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(1.5),
          ),
          child: ModuleRepositoryPage(
            controller: PicoraController()..initializing = false,
            review: (_) async => false,
            service: FixedCatalogService(catalog),
            appVersionLoader: () async => '1.0.0-debug',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('没有找到插件'), findsOneWidget);
    expect(find.text('Telegraph-Image'), findsNothing);
  });
}
