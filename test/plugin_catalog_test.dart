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
  'repository':
      'https://github.com/Alnitak44/Picora/tree/main/plugins/telegraph-image',
  'downloadUrl':
      'https://github.com/Alnitak44/picora-plugins/releases/download/telegraph-image-v1.1.1/telegraph-image-1.1.1.picora-plugin.zip',
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
      expect(entry.isUpdateFor('1.1.1'), isFalse);
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
