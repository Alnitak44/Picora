import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/plugin_page.dart';
import 'package:picora/hero/plugins/plugin_manager.dart';
import 'package:picora/hero/plugins/plugin_package.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';
import 'package:picora/hero/repositories_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

PicoraPluginPackage sample() => PicoraPluginPackage.decode(
  File('assets/plugins/telegraph-image.picora-plugin.zip').readAsBytesSync(),
);

Uint8List packageBytes({
  Map<String, dynamic>? metadata,
  Map<String, dynamic>? program,
  Map<String, List<int>?> changes = const {},
}) {
  final source = sample();
  final files = <String, List<int>>{...source.files};
  final meta = {...source.metadata, 'id': 'test.picora.package', ...?metadata};
  files['plugin.json'] = utf8.encode(jsonEncode(meta));
  if (program != null) {
    files['uploader.json'] = utf8.encode(jsonEncode(program));
  }
  for (final entry in changes.entries) {
    if (entry.value == null) {
      files.remove(entry.key);
    } else {
      files[entry.key] = entry.value!;
    }
  }
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await Directory('artifacts').create(recursive: true);
  });

  test(
    'example ZIP includes separate metadata, program, tutorial and provider icon',
    () {
      final package = sample();
      expect(package.manifest.version, '1.1.0');
      expect(package.readme, contains('上传鉴权'));
      expect(package.repository, startsWith('https://github.com/'));
      expect(package.toHostSpec().iconBytes, isNotEmpty);
      expect(package.toHostSpec().iconFormat, 'svg');
      expect(package.resource('../plugin.json'), isNull);
      expect(package.resource('plugin.json'), isNull);
    },
  );

  test(
    'missing metadata, README, entry, icon and unsupported runtime fail clearly',
    () {
      for (final filename in [
        'plugin.json',
        'readme.md',
        'uploader.json',
        'assets/icon.svg',
      ]) {
        expect(
          () => PicoraPluginPackage.decode(
            packageBytes(changes: {filename: null}),
          ),
          throwsA(isA<HeroFailure>()),
          reason: filename,
        );
      }
      for (final meta in [
        {'runtime': 'node'},
        {'packageVersion': 2},
        {'entry': '../secret.json'},
        {'icon': '../icon.svg'},
        {'repository': 'javascript:alert(1)'},
      ]) {
        expect(
          () => PicoraPluginPackage.decode(packageBytes(metadata: meta)),
          throwsA(isA<HeroFailure>()),
          reason: meta.toString(),
        );
      }
      expect(
        () => PicoraPluginPackage.decode(
          packageBytes(
            changes: {
              'readme.md': [255],
            },
          ),
        ),
        throwsA(isA<HeroFailure>()),
      );
    },
  );

  test(
    'traversal, absolute, Windows and duplicate case paths are rejected',
    () {
      for (final path in [
        '../outside.txt',
        '/outside.txt',
        r'C:\outside.txt',
        r'assets\icon.png',
        'assets/../outside.txt',
        'assets//x.txt',
        'README.md',
      ]) {
        expect(
          () => PicoraPluginPackage.decode(
            packageBytes(
              changes: {
                path: [1],
              },
            ),
          ),
          throwsA(isA<HeroFailure>()),
          reason: path,
        );
      }
    },
  );

  test(
    'invalid ZIP, oversized zip, entry, README and excess entries are rejected',
    () {
      expect(
        () => PicoraPluginPackage.decode([1, 2, 3]),
        throwsA(isA<HeroFailure>()),
      );
      expect(
        () => PicoraPluginPackage.decode(
          Uint8List(PicoraPluginPackage.maxZipBytes + 1),
        ),
        throwsA(isA<HeroFailure>()),
      );
      expect(
        () => PicoraPluginPackage.decode(
          packageBytes(
            changes: {
              'assets/large.bin': Uint8List(
                PicoraPluginPackage.maxFileBytes + 1,
              ),
            },
          ),
        ),
        throwsA(isA<HeroFailure>()),
      );
      expect(
        () => PicoraPluginPackage.decode(
          packageBytes(changes: {'readme.md': List.filled(512 * 1024 + 1, 65)}),
        ),
        throwsA(isA<HeroFailure>()),
      );
      expect(
        () => PicoraPluginPackage.decode(
          packageBytes(
            changes: {
              for (var i = 0; i < 129; i++) 'assets/file-$i.txt': [65],
            },
          ),
        ),
        throwsA(isA<HeroFailure>()),
      );
    },
  );

  test('symlinks and CRC mismatches are rejected', () {
    final linked = Archive()
      ..add(ArchiveFile.string('assets/link', '../outside')..mode = 0xa1ff);
    expect(
      () => PicoraPluginPackage.decode(ZipEncoder().encode(linked)),
      throwsA(isA<HeroFailure>()),
    );
    final original = ArchiveFile.string('readme.md', 'uncompressed-tutorial')
      ..compression = CompressionType.none;
    final bytes = Uint8List.fromList(
      ZipEncoder().encode(Archive()..add(original)),
    );
    final header =
        (ZipDirectory()..read(InputMemoryStream(bytes))).fileHeaders.single;
    final offset =
        header.localHeaderOffset + 30 + utf8.encode(header.filename).length;
    bytes[offset] ^= 1;
    expect(
      () => PicoraPluginPackage.decode(bytes),
      throwsA(isA<HeroFailure>()),
    );
  });

  test('forged ZIP size cannot bypass actual decompression limit', () {
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'assets/large.bin',
          Uint8List(PicoraPluginPackage.maxFileBytes + 1),
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final header =
        (ZipDirectory()..read(InputMemoryStream(bytes))).fileHeaders.single;
    final data = ByteData.sublistView(bytes);
    data.setUint32(header.localHeaderOffset + 22, 1, Endian.little);
    for (var i = 0; i < bytes.length - 4; i++) {
      if (data.getUint32(i, Endian.little) == ZipFileHeader.signature) {
        data.setUint32(i + 24, 1, Endian.little);
        break;
      }
    }
    expect(
      () => PicoraPluginPackage.decode(bytes),
      throwsA(
        isA<HeroFailure>().having(
          (e) => e.toString(),
          'message',
          contains('实际解压大小'),
        ),
      ),
    );
  });

  test(
    'resource text/base64 templates are available to upload program',
    () async {
      final program =
          jsonDecode(utf8.decode(sample().files['uploader.json']!))
              as Map<String, dynamic>;
      program['upload']['headers']['X-Resource'] =
          r'${assetText(assets/token.txt)}';
      program['upload']['headers']['X-Resource-Base64'] =
          r'${base64(assets/token.txt)}';
      final package = PicoraPluginPackage.decode(
        packageBytes(
          program: program,
          changes: {'assets/token.txt': utf8.encode('hello-resource')},
        ),
      );
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.headers['X-Resource'], 'hello-resource');
              expect(
                options.headers['X-Resource-Base64'],
                base64Encode(utf8.encode('hello-resource')),
              );
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {'src': '/image.png'},
                  ],
                ),
              );
            },
          ),
        );
      final root = await Directory('artifacts').createTemp('resource-test-');
      try {
        final image = await File('${root.path}/image.png').writeAsBytes([1, 2]);
        final result = await PluginHttpRuntime(dio: dio).upload(
          package.manifest,
          path: image.path,
          name: 'image.png',
          config: {'baseUrl': 'https://example.com'},
        );
        expect(result[0], 'success');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'legacy migration, ZIP update and reinstall preserve independent configs',
    () async {
      await Directory('artifacts').create(recursive: true);
      final root = await Directory('artifacts').createTemp('package-manager-');
      try {
        final legacy = PicoraPluginPackage.decode(packageBytes()).manifest;
        final directory = await Directory(
          '${root.path}/picora-plugins',
        ).create();
        await File(
          '${directory.path}/${legacy.id}.json',
        ).writeAsString(legacy.encode());
        final registry = UploaderRegistry();
        final manager = PicoraPluginManager(
          registry: registry,
          storageRoot: root,
        );
        await manager.initialize();
        expect(File('${directory.path}/${legacy.id}.zip').existsSync(), isTrue);
        expect(
          File('${directory.path}/${legacy.id}.json.legacy').existsSync(),
          isTrue,
        );
        final spec = manager.packageFor(legacy.id).toHostSpec();
        final first = await manager.saveRepository(spec, '主站', {
          'baseUrl': 'https://a.example',
        });
        final second = await manager.saveRepository(spec, '备用站', {
          'baseUrl': 'https://b.example',
        });
        expect(first.slot, isNot(second.slot));
        await manager.setEnabled(legacy.id, false);
        expect(
          () => registry.upload(
            spec.id,
            path: 'unused',
            name: 'unused',
            config: {},
          ),
          throwsA(isA<HeroFailure>()),
        );
        await manager.installPackage(
          packageBytes(metadata: {'version': '2.0.0'}),
        );
        expect(manager.packageFor(legacy.id).manifest.version, '2.0.0');
        expect(manager.isEnabled(legacy.id), isTrue);
        await manager.initialize(force: true);
        expect(manager.packageFor(legacy.id).manifest.version, '2.0.0');
        expect((await manager.readRepositories()).map((e) => e.id), [
          first.id,
          second.id,
        ]);
        expect(
          () => manager.installPackage([1, 2, 3]),
          throwsA(isA<HeroFailure>()),
        );
        expect(manager.packageFor(legacy.id).manifest.version, '2.0.0');
        expect(() => manager.remove(legacy.id), throwsA(isA<HeroFailure>()));
        await manager.deleteRepository(first);
        await manager.deleteRepository(second);
        await manager.remove(legacy.id);
        await manager.initialize(force: true);
        expect(manager.installed.any((e) => e.id == legacy.id), isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'long provider header and tutorial render at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final package = sample();
      final controller = PicoraController()..initializing = false;
      Widget app(Widget page) => MaterialApp(
        theme: heroTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 780),
            textScaler: TextScaler.linear(1.5),
          ),
          child: page,
        ),
      );
      await tester.pumpWidget(
        app(
          RepositoryEditor(controller: controller, spec: package.toHostSpec()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(PluginReadmePage(package: package, controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('插件主页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plugin center tutorial entry opens local README', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = await tester.runAsync(() async {
      await Directory('artifacts').create(recursive: true);
      return Directory('artifacts').createTemp('plugin-widget-');
    });
    final registry = UploaderRegistry();
    final manager = PicoraPluginManager(registry: registry, storageRoot: root);
    await tester.runAsync(() => manager.initialize());
    final controller = PicoraController(
      uploaderRegistry: registry,
      pluginManager: manager,
    )..initializing = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.dark),
        home: PluginCenterPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('使用教程'));
    await tester.tap(find.text('使用教程'));
    await tester.pumpAndSettle();
    expect(find.text('插件主页'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => root!.delete(recursive: true));
  });
}
