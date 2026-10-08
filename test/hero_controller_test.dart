import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/models.dart';
import 'package:picora/hero/config_exchange.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/utils/global.dart';
import 'package:picora/picture_host_configure/configure_store/configure_store_file.dart';
import 'package:picora/picture_host_configure/configure_store/configure_template.dart';
import 'package:picora/hero/markdown_migration.dart';

class TestPaths extends PathProviderPlatform {
  final String root;
  TestPaths(this.root);
  @override
  Future<String> getApplicationDocumentsPath() async => root;
  @override
  Future<String> getApplicationSupportPath() async => root;
  @override
  Future<String> getTemporaryPath() async => '$root/tmp';
}

const configA = RepositoryConfig(
  host: 'aliyun',
  slot: 'A',
  name: '工作图库',
  values: {
    'keyId': 'test-id',
    'keySecret': 'test-secret',
    'bucket': 'work',
    'area': 'oss-cn-hangzhou',
  },
);
const configB = RepositoryConfig(
  host: 'github',
  slot: 'A',
  name: '博客图片',
  values: {
    'githubusername': 'demo',
    'repo': 'images',
    'token': 'Bearer test',
    'branch': 'main',
    'storePath': 'None',
    'customDomain': 'None',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    HttpOverrides.global =
        null; // Only the loopback HTTP fixture is used in this suite.
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    sqfliteFfiInit();
    dir = await Directory('artifacts/test-data').create(recursive: true);
    PathProviderPlatform.instance = TestPaths(dir.absolute.path);
    await Directory('${dir.path}/tmp').create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  setUp(() async {
    Global.isCopyLink = false;
    Global.isCompress = false;
    Global.isTimeStamp = false;
    Global.isRandomName = false;
    Global.isCustomRename = false;
    Global.isDeleteLocal = false;
    Global.isDeleteCloud = false;
    Global.imageDB = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    Global.imageDBExtend = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    for (final table in ['aliyun', 'github']) {
      await Global.imageDB!.execute(
        'CREATE TABLE $table (id INTEGER PRIMARY KEY, path TEXT, name TEXT, url TEXT, PBhost TEXT, pictureKey TEXT, hostSpecificArgA TEXT, hostSpecificArgB TEXT, hostSpecificArgC TEXT, hostSpecificArgD TEXT, hostSpecificArgE TEXT)',
      );
    }
  });
  tearDown(() async {
    await Global.imageDB!.close();
    await Global.imageDBExtend!.close();
  });
  test('schemas preserve every inherited provider configuration field', () {
    for (final spec in hostSpecs.where((item) => !item.isPlugin)) {
      expect(
        spec.fields.map((f) => f.key).toSet(),
        ConfigureTemplate.psHostNameToTemplate[spec.id]!.keys
            .where((k) => k != 'remarkName')
            .toSet(),
        reason: spec.id,
      );
    }
  });
  test('config conversion round trips GitHub, OSS and S3', () {
    for (final config in [
      configA,
      configB,
      RepositoryConfig(
        host: 'aws',
        slot: 'B',
        name: 'S3',
        values: {
          'accessKeyId': 'id',
          'secretAccessKey': 'secret',
          'bucket': 'bucket',
          'endpoint': 's3.example.com',
          'isEnableSSL': true,
          'isS3PathStyle': false,
        },
      ),
    ]) {
      final parsed = ConfigExchange.parse(
        ConfigExchange.exportPicGo(config),
      ).single;
      final normalized = PicoraController.normalizeValues(parsed.$1, parsed.$3);
      for (final entry in config.values.entries) {
        expect(
          normalized[entry.key],
          entry.value,
          reason: '${config.host}.${entry.key}',
        );
      }
    }
  });
  test('imports reject incomplete configurations before persisting', () {
    expect(
      () => ConfigExchange.parse('{"picBed":{"aliyun":{"bucket":"b"}}}'),
      throwsA(isA<HeroFailure>()),
    );
  });
  test('OpenList export uses the new name and accepts legacy AList keys', () {
    const config = RepositoryConfig(
      host: 'alist',
      slot: 'A',
      name: 'OpenList · 主图床',
      values: {'host': 'https://openlist.example.com', 'token': 'test-token'},
    );
    final exported = jsonDecode(ConfigExchange.export([config]));
    expect(exported['repositories'].single['host'], 'openlist');
    expect(ConfigExchange.parse(jsonEncode(exported)).single.$1.id, 'alist');
    expect(
      ConfigExchange.parse(
        '{"repositories":[{"host":"alist","name":"旧配置","values":{"host":"https://example.com","token":"legacy"}}]}',
      ).single.$1.id,
      'alist',
    );
  });
  test('validates HTTP image links', () {
    expect(
      PicoraController.imageUri(' https://example.com/pic.png ').host,
      'example.com',
    );
    for (final input in [
      '',
      'hello',
      'file:///etc/passwd',
      'ftp://example.com/a',
      'https:///image.png',
    ]) {
      expect(
        () => PicoraController.imageUri(input),
        throwsA(isA<HeroFailure>()),
      );
    }
  });
  test(
    'upload snapshots the target and preserves default configuration',
    () async {
      late PicoraController controller;
      controller =
          PicoraController(
              uploadOverride: (host, path, name, values) async {
                expect(host, configA.host);
                expect(values['bucket'], 'work');
                expect(
                  () => controller.selectTarget(configB),
                  throwsA(isA<HeroFailure>()),
                );
                return [
                  'success',
                  'https://cdn.example.com/a.jpg',
                  'https://cdn.example.com/a.jpg',
                  '{}',
                  'https://cdn.example.com/a.jpg',
                ];
              },
            )
            ..target = configA
            ..defaultId = configB.id;
      final uploaded = await controller.uploadFiles(['test.jpg']);
      expect(uploaded.single.host, 'aliyun');
      expect(controller.defaultId, configB.id);
      expect(controller.latest!.name, 'test.jpg');
      expect(controller.busy, false);
      expect(await Global.imageDB!.query('aliyun'), hasLength(1));
      expect(await Global.imageDB!.query('github'), isEmpty);
      controller.dispose();
    },
  );
  test(
    'partial batch records only successful files and can retry the failure',
    () async {
      var reject = true;
      final controller = PicoraController(
        uploadOverride: (host, path, name, values) async {
          if (name == 'bad.png' && reject) return ['failed'];
          return [
            'success',
            'https://cdn.example.com/$name',
            'https://cdn.example.com/$name',
            '{}',
            'https://cdn.example.com/$name',
          ];
        },
      )..target = configA;
      await expectLater(
        controller.uploadFiles(['good.png', 'bad.png']),
        throwsA(isA<HeroFailure>()),
      );
      expect(controller.images, hasLength(1));
      expect(controller.failedPath, 'bad.png');
      expect(controller.busy, false);
      reject = false;
      await controller.uploadFiles([controller.failedPath!]);
      expect(controller.images, hasLength(2));
      expect(controller.latest!.name, 'bad.png');
      controller.dispose();
    },
  );
  test(
    'GitHub copy URL is a usable image URL rather than a repository HTML page',
    () {
      final entry = AlbumEntry({
        'url': 'https://github.com/u/r/blob/main/a.png',
        'hostSpecificArgA': 'https://raw.githubusercontent.com/u/r/main/a.png',
      }, 'github');
      expect(entry.url, 'https://raw.githubusercontent.com/u/r/main/a.png');
    },
  );
  test('nested credentials and signed URL parameters are redacted', () {
    final output = jsonEncode(
      HeroDiagnostics.redact({
        'config': {'secretAccessKey': 'sensitive', 'token': 'private'},
        'url': 'https://example.com/a?X-Amz-Signature=secret&ok=1',
        'message': 'Bearer private',
      }),
    );
    expect(output, isNot(contains('sensitive')));
    expect(output, isNot(contains('private')));
    expect(output, isNot(contains('Signature=secret')));
    expect(output, contains('ok=1'));
  });
  test(
    'deleting a configuration does not resurrect its inherited active file',
    () async {
      Global.setUser('test');
      await ConfigureStoreFile().generateConfigureFile();
      final controller = PicoraController();
      final config = await controller.saveRepository(
        hostSpec('sm.ms'),
        '临时图床',
        {'token': 'test-token'},
      );
      await controller.deleteRepository(config);
      await controller.loadRepositories();
      expect(controller.repositories.where((r) => r.id == config.id), isEmpty);
      controller.dispose();
    },
  );
  test(
    'deleting history preserves the original file when local deletion is off',
    () async {
      final file = await File('${dir.path}/keep.png').writeAsString('fixture');
      final controller = PicoraController(
        uploadOverride: (_, __, ___, ____) async => [
          'success',
          'https://e.com/a',
          'https://e.com/a',
          '{}',
          'https://e.com/a',
        ],
      )..target = configA;
      final uploaded = await controller.uploadFiles([file.path]);
      await controller.removeImages(uploaded);
      expect(await file.exists(), true);
      expect(controller.images, isEmpty);
      expect(await Global.imageDB!.query('aliyun'), isEmpty);
      controller.dispose();
    },
  );
  test('link upload downloads the image and preserves its filename', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZikAAAAASUVORK5CYII=',
        ),
      );
      await request.response.close();
    });
    final controller = PicoraController(
      uploadOverride: (host, path, name, values) async {
        expect(await File(path).exists(), true);
        expect(name, 'remote.png');
        return [
          'success',
          'https://e.com/remote.png',
          'https://e.com/remote.png',
          '{}',
          'https://e.com/remote.png',
        ];
      },
    )..target = configA;
    try {
      final result = await controller.uploadLinks(
        'http://127.0.0.1:${server.port}/remote.png?variant=1',
      );
      expect(result.single.name, 'remote.png');
      expect(controller.busy, false);
    } finally {
      controller.dispose();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
  test('HTML response is rejected without inserting an album entry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>This is not an image.</html>');
      await request.response.close();
    });
    final controller = PicoraController(
      uploadOverride: (_, __, ___, ____) async =>
          throw StateError('must not upload HTML'),
    )..target = configA;
    try {
      await expectLater(
        controller.uploadLinks('http://127.0.0.1:${server.port}/error.png'),
        throwsA(isA<HeroFailure>()),
      );
      expect(controller.images, isEmpty);
      expect(controller.busy, false);
      expect(controller.failure, contains('不是图片'));
    } finally {
      controller.dispose();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
  test('JSON encoded provider logs redact embedded credentials', () {
    final data = HeroDiagnostics.redact({
      'content': jsonEncode({
        'password': 'do-not-export',
        'token': 'do-not-export',
        'host': 'example.com',
      }),
    });
    expect(jsonEncode(data), isNot(contains('do-not-export')));
    expect(jsonEncode(data), contains('example.com'));
  });
  test(
    'Markdown migration locks the selected configuration across downloads and uploads',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([137, 80, 78, 71, 13, 10, 26, 10]);
        await request.response.close();
      });
      var uploads = 0;
      late PicoraController controller;
      controller =
          PicoraController(
              uploadOverride: (host, path, name, values) async {
                expect(controller.busy, isTrue);
                expect(host, configA.host);
                expect(values['bucket'], configA.values['bucket']);
                uploads++;
                controller.target = configB;
                final url = 'https://new.example/$name';
                return ['success', url, url, 'key-$uploads', url];
              },
            )
            ..target = configB
            ..repositories = [configA, configB]
            ..initializing = false;
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final result = await controller.migrateMarkdown(
          '![a]($base/a.png)\n![b]($base/b.png)',
          configA,
          MigrationCancellation(),
        );
        expect(result.successful, 2);
        expect(uploads, 2);
        expect(controller.busy, isFalse);
        expect(
          controller.images.map((e) => e.repositoryId),
          everyElement(configA.id),
        );
        expect(controller.target?.id, configB.id);
        expect(await Global.imageDB!.query('aliyun'), hasLength(2));
        expect(await Global.imageDB!.query('github'), isEmpty);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('shared images are deduplicated and can be dismissed', () {
    final controller = PicoraController();
    controller.receiveSharedPaths(['a.png', 'b.png']);
    controller.receiveSharedPaths(['a.png']);
    expect(controller.pendingSharedPaths, ['a.png', 'b.png']);
    controller.clearSharedPaths();
    expect(controller.pendingSharedPaths, isEmpty);
    controller.dispose();
  });
  test(
    'theme modes persist and an invalid choice cannot replace the saved mode',
    () async {
      final controller = PicoraController();
      final preferences = await SharedPreferences.getInstance();
      for (final choice in ['light', 'system', 'dark']) {
        await controller.setTheme(choice);
        expect(preferences.getString('hero_theme'), choice);
        expect(controller.themeChoice, choice);
      }
      await expectLater(
        controller.setTheme('unknown'),
        throwsA(isA<HeroFailure>()),
      );
      expect(preferences.getString('hero_theme'), 'dark');
      controller.dispose();
    },
  );
}
