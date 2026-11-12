import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picora/app/controller.dart';
import 'package:picora/app/diagnostics.dart';
import 'package:picora/app/hero_theme.dart';
import 'package:picora/app/models.dart';
import 'package:picora/app/plugin_repository_page.dart';
import 'package:picora/app/plugin_page.dart';
import 'package:picora/app/plugin_tags.dart';
import 'package:picora/app/plugin_update_badge.dart';
import 'package:picora/app/plugins/plugin_catalog.dart';
import 'package:picora/app/plugins/plugin_manager.dart';
import 'package:picora/app/plugins/plugin_manifest.dart';
import 'package:picora/app/plugins/plugin_package.dart';
import 'package:picora/app/plugins/uploader_registry.dart';
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
  'mark': 'TG',
  'tags': <String>[],
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

class PendingCatalogService extends PluginCatalogService {
  final completer = Completer<PluginCatalog>();

  @override
  Future<PluginCatalog> load({bool forceRefresh = false}) => completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await Directory('artifacts').create(recursive: true);
    root = await Directory('artifacts').createTemp('plugin-tests-');
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

  test('plugin tags map to visible attributes', () {
    final json = entryJson(telegraphPackage());
    final withoutTags = {...json}..remove('tags');
    expect(PluginCatalogEntry.fromJson(withoutTags).tags, isNull);
    expect(PluginCatalogEntry.fromJson(json).tags, isEmpty);
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': ['token'],
      }).tags,
      {PluginTag.token},
    );
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': ['account'],
      }).tags,
      {PluginTag.account},
    );
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': ['token', 'account', 'custom-url'],
      }).tags,
      {PluginTag.token, PluginTag.account, PluginTag.customUrl},
    );
    for (final invalid in [
      'token',
      ['unknown'],
      [1],
      ['token', 'token'],
    ]) {
      expect(
        () => PluginCatalogEntry.fromJson({...json, 'tags': invalid}),
        throwsA(isA<HeroFailure>()),
      );
    }
  });

  test('config roles derive tags while unknown roles stay compatible', () {
    HostField field(
      String key, {
      String type = 'text',
      String? role,
      bool required = false,
    }) => HostField(
      key,
      key,
      secret: type == 'secret',
      required: required,
      role: role,
    );

    expect(<HostField>[].derivedTags, isEmpty);
    expect(<HostField>[].derivedRequiresAuth, isFalse);
    expect([field('token', type: 'secret', role: 'token')].derivedTags, {
      PluginTag.token,
    });
    expect(
      [
        field('user', role: 'account'),
        field('pass', type: 'secret'),
      ].derivedTags,
      {PluginTag.account},
    );
    expect([field('baseUrl', role: 'endpoint')].derivedTags, {
      PluginTag.customUrl,
    });
    expect(
      [
        field('token', type: 'secret', role: 'token'),
        field('baseUrl', role: 'endpoint'),
      ].derivedTags,
      {PluginTag.token, PluginTag.customUrl},
    );
    expect([field('apiKey', type: 'secret', required: true)].derivedTags, {
      PluginTag.token,
    });
    expect([field('account', required: true)].derivedTags, {PluginTag.account});
    expect([field('baseUrl', required: true)].derivedTags, {
      PluginTag.customUrl,
    });
    expect(
      [field('username'), field('password', type: 'secret')].derivedTags,
      isEmpty,
    );
    // Unknown roles are ignored, but a required secret still needs credentials.
    final future = [
      field('cookie', type: 'secret', role: 'cookie', required: true),
    ];
    expect(future.derivedTags, isEmpty);
    expect(future.derivedRequiresAuth, isTrue);
    expect([field('path', required: true)].derivedRequiresAuth, isFalse);
    expect(
      [field('key', type: 'secret', required: true)].derivedRequiresAuth,
      isTrue,
    );
    expect([field('key', type: 'secret', required: true)].derivedTags, {
      PluginTag.token,
    });
  });

  test('catalog requiresAuth prefers the generated field', () {
    final json = entryJson(telegraphPackage());
    expect(
      PluginCatalogEntry.fromJson({...json, 'tags': []}).requiresAuth,
      isFalse,
    );
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': ['token'],
      }).requiresAuth,
      isTrue,
    );
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': [],
        'requiresAuth': true,
      }).requiresAuth,
      isTrue,
    );
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': ['custom-url'],
      }).requiresAuth,
      isFalse,
    );
  });

  test('cloud delete is derived from the delete request', () {
    Map<String, dynamic> program() {
      final body =
          jsonDecode(
                File('test/fixtures/imgloc/uploader.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final meta =
          jsonDecode(
                File('test/fixtures/imgloc/plugin.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      return {...body, ...meta}
        ..remove('packageVersion')
        ..remove('runtime')
        ..remove('entry')
        ..remove('icon')
        ..remove('repository');
    }

    expect(
      PicoraPluginManifest.fromJson(program()).derivedTags,
      isNot(contains(PluginTag.cloudDelete)),
    );
    final deletable = program();
    deletable['permissions']['deleteUploadedFile'] = true;
    deletable['upload']['response']['deleteKey'] = 'deleteKey';
    deletable['delete'] = {
      'method': 'POST',
      'url': 'https://imgloc.com/delete',
      'body': {
        'type': 'json',
        'fields': {'key': r'${upload.deleteKey}'},
      },
    };
    final manifest = PicoraPluginManifest.fromJson(deletable);
    expect(manifest.derivedTags, contains(PluginTag.cloudDelete));
    expect(manifest.derivedRequiresAuth, isFalse);

    final json = entryJson(telegraphPackage());
    final entry = PluginCatalogEntry.fromJson({
      ...json,
      'tags': ['cloud-delete'],
    });
    expect(entry.tags, {PluginTag.cloudDelete});
    expect(entry.requiresAuth, isFalse);
  });

  test('prerelease versions are tagged as beta', () {
    final preview = telegraphPackage(version: '1.2.0-beta.1');
    final json = entryJson(preview);
    expect(PluginCatalogEntry.fromJson(json).tags, {PluginTag.beta});
    expect(
      PluginCatalogEntry.fromJson({
        ...json,
        'tags': ['token'],
      }).tags,
      {PluginTag.token, PluginTag.beta},
    );
    expect(
      PluginCatalogEntry.fromJson({...json, 'tags': []}).requiresAuth,
      isFalse,
    );
    expect(preview.manifest.derivedTags, contains(PluginTag.beta));
    expect(
      PluginCatalogEntry.fromJson(entryJson(telegraphPackage())).tags,
      isNot(contains(PluginTag.beta)),
    );
  });

  test('installed updates are listed first and other order is preserved', () {
    final source = entryJson(telegraphPackage());
    PluginCatalogEntry entry(String id) =>
        PluginCatalogEntry.fromJson({...source, 'id': id, 'version': '1.2.0'});
    final catalog = PluginCatalog([
      entry('test.uninstalled'),
      entry('test.update'),
      entry('test.current'),
      entry('test.newer-local'),
      entry('test.second-update'),
    ], DateTime.utc(2026, 10, 14));
    final versions = {
      'test.update': '1.1.0',
      'test.current': '1.2.0',
      'test.newer-local': '1.3.0',
      'test.second-update': '1.2.0-beta.1',
    };
    expect(catalog.orderedForInstalled(versions).map((entry) => entry.id), [
      'test.update',
      'test.second-update',
      'test.uninstalled',
      'test.current',
      'test.newer-local',
    ]);
    expect(
      catalog.orderedForInstalled({}).map((entry) => entry.id),
      catalog.entries.map((entry) => entry.id),
    );
    versions['test.update'] = '1.2.0';
    expect(catalog.orderedForInstalled(versions).map((entry) => entry.id), [
      'test.second-update',
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

  test('catalog cache from before auth tags is ignored', () async {
    final source = indexSource(entryJson(telegraphPackage()));
    await File('${root.path}/picora-plugin-index.json').writeAsString(
      jsonEncode({
        'fetchedAt': DateTime.utc(2026, 10, 8).toIso8601String(),
        'route': PluginCatalogService.indexUrl,
        'source': source,
      }),
    );
    var calls = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              statusCode: 200,
              data: utf8.encode(source),
            ),
          );
        },
      ),
    );
    final catalog = await PluginCatalogService(
      dio: dio,
      storageRoot: root,
      now: () => DateTime.utc(2026, 11, 11),
    ).load();
    expect(calls, 1);
    expect(catalog.entries.single.tags, isEmpty);
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
      await manager.remove(package.manifest.id, deleteRepositories: true);
      expect(await manager.readRepositories(), isEmpty);
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
      final latestJson = {
        ...entryJson(latest),
        'tags': ['token'],
      };
      final catalog = PluginCatalog([
        PluginCatalogEntry.fromJson({
          ...entryJson(installed),
          'id': 'test.example',
          'name': 'Another Plugin',
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
          PluginRepositoryPage(
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
      expect(find.widgetWithText(PluginTagChip, '需认证'), findsOneWidget);
      expect(find.widgetWithText(PluginTagChip, 'Token'), findsOneWidget);
      expect(find.textContaining('更新至'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Telegraph-Image')).dy,
        lessThan(tester.getTopLeft(find.text('Another Plugin')).dy),
      );
      final updateButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '更新'),
      );
      expect(
        updateButton.style?.backgroundColor?.resolve({}),
        pluginUpdateColor,
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Another');
      await tester.pumpAndSettle();
      expect(find.text('可更新'), findsNothing);
      expect(find.text('Another Plugin'), findsOneWidget);
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
      expect(find.text('无需认证'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => manager.installPackage(latest.bytes));
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('可更新'), findsNothing);
      await tester.pumpWidget(
        app(
          PluginRepositoryPage(
            controller: controller,
            review: (_) async => false,
            service: FixedCatalogService(catalog),
            appVersionLoader: () async => '1.0.6',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('更新'), findsNothing);
      expect(
        find.byKey(const ValueKey('plugin-installed-status')),
        findsOneWidget,
      );
      expect(find.widgetWithText(PluginTagChip, '需认证'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Another Plugin')).dy,
        lessThan(tester.getTopLeft(find.text('Telegraph-Image')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('plugin rows support narrow screens, large text and search', (
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
          child: PluginRepositoryPage(
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
    expect(find.widgetWithText(PluginTagChip, '无需认证'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), '无需认证');
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Token');
    await tester.pumpAndSettle();
    expect(find.text('没有找到插件'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('没有找到插件'), findsOneWidget);
    expect(find.text('Telegraph-Image'), findsNothing);
  });

  testWidgets('plugin repository filters by install state and tags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registry = UploaderRegistry();
    final manager = PicoraPluginManager(registry: registry, storageRoot: root);
    final installed = telegraphPackage();
    await tester.runAsync(() => manager.installPackage(installed.bytes));
    final controller = PicoraController(
      uploaderRegistry: registry,
      pluginManager: manager,
    )..initializing = false;
    addTearDown(controller.dispose);
    final catalog = PluginCatalog([
      PluginCatalogEntry.fromJson({
        ...entryJson(installed),
        'tags': ['custom-url'],
      }),
      PluginCatalogEntry.fromJson({
        ...entryJson(installed),
        'id': 'test.auth',
        'name': 'Auth Plugin',
        'tags': ['token'],
      }),
    ], DateTime.utc(2026, 11, 12));
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: PluginRepositoryPage(
          controller: controller,
          review: (_) async => false,
          service: FixedCatalogService(catalog),
          appVersionLoader: () async => '1.0.0-debug',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsOneWidget);
    expect(find.text('Auth Plugin'), findsOneWidget);
    expect(find.byKey(const ValueKey('plugin-filter-tag-token')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plugin-filter-available')));
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsNothing);
    expect(find.text('Auth Plugin'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plugin-filter-installed')));
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsOneWidget);
    expect(find.text('Auth Plugin'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plugin-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plugin-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plugin-filter-tag-token')));
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsNothing);
    expect(find.text('Auth Plugin'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plugin-filter-auth-optional')));
    await tester.pumpAndSettle();
    expect(find.text('没有找到插件'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plugin-filter-reset-tags')));
    await tester.pumpAndSettle();
    expect(find.text('Telegraph-Image'), findsOneWidget);
    expect(find.text('Auth Plugin'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plugin-filter-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plugin-filter-tag-token')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin repository shows a skeleton while loading', (
    tester,
  ) async {
    final service = PendingCatalogService();
    final controller = PicoraController()..initializing = false;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: PluginRepositoryPage(
          controller: controller,
          review: (_) async => false,
          service: service,
          appVersionLoader: () async => '1.0.0-debug',
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('plugin-repository-skeleton')),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);

    service.completer.complete(
      PluginCatalog([
        PluginCatalogEntry.fromJson(entryJson(telegraphPackage())),
      ], DateTime.utc(2026, 11, 12)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('plugin-repository-skeleton')),
      findsNothing,
    );
    expect(find.text('Telegraph-Image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
