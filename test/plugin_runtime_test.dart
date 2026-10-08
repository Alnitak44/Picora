import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/models.dart';
import 'package:picora/hero/plugins/plugin_manager.dart';
import 'package:picora/hero/plugins/plugin_manifest.dart';
import 'package:picora/hero/plugins/plugin_package.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
  });

  Future<PicoraPluginManifest> telegraphManifest() async {
    final data = await rootBundle.load(
      'assets/plugins/telegraph-image.picora-plugin.zip',
    );
    return PicoraPluginPackage.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ).manifest;
  }

  test('all supplied provider icons are bundled', () async {
    for (final id in ['aliyun', 'qiniu', 'tencent', 'upyun', 'github']) {
      final asset = hostSpec(id).iconAsset;
      expect(asset, isNotNull, reason: id);
      final data = await rootBundle.load(asset!);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }
  });

  test(
    'example manifest preserves the Telegraph PicGo plugin behavior',
    () async {
      final manifest = await telegraphManifest();
      expect(manifest.id, 'dev.picora.telegraph-image');
      expect(manifest.name, 'Telegraph-Image');
      expect(manifest.upload.body.type, 'multipart');
      expect(manifest.upload.body.fileField, 'file');
      expect(manifest.upload.followRedirects, false);
      expect(manifest.upload.timeoutSeconds, 60);
      expect(manifest.upload.response!.urlPath, '[0].src');
    },
  );

  test(
    'Telegraph runtime normalizes URL, applies Basic auth and resolves image URL',
    () async {
      final manifest = await telegraphManifest();
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.toString(), 'https://images.example.com/upload');
            expect(options.followRedirects, false);
            expect(options.headers['Authorization'], 'Basic dXNlcjpwYXNz');
            expect(options.headers['Accept'], 'application/json');
            final data = options.data as FormData;
            expect(data.files.single.key, 'file');
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {'src': '/file/test.png'},
                ],
              ),
            );
          },
        ),
      );
      final file = File('artifacts/telegraph-runtime-test.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
      final result = await PluginHttpRuntime(dio: dio).upload(
        manifest,
        path: file.absolute.path,
        name: 'test.png',
        config: {
          'baseUrl': 'images.example.com',
          'username': 'user',
          'password': 'pass',
        },
      );
      expect(result[0], 'success');
      expect(result[2], 'https://images.example.com/file/test.png');
    },
  );

  test('plugin manager registers the example plugin as enabled', () async {
    final registry = UploaderRegistry();
    final directory = Directory('artifacts/plugin-manager-test');
    await directory.create(recursive: true);
    final manager = PicoraPluginManager(
      registry: registry,
      storageRoot: directory,
    );
    await manager.initialize(force: true);
    expect(
      manager.installed.map((item) => item.id),
      contains('dev.picora.telegraph-image'),
    );
    expect(manager.isBundled('dev.picora.telegraph-image'), true);
    expect(registry.contains('plugin.dev.picora.telegraph-image'), true);
  });

  test(
    'Telegraph runtime rejects a partial Basic auth configuration',
    () async {
      final manifest = await telegraphManifest();
      final file = File('artifacts/telegraph-runtime-auth-test.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
      expect(
        () => PluginHttpRuntime().upload(
          manifest,
          path: file.absolute.path,
          name: 'test.png',
          config: {
            'baseUrl': 'https://images.example.com',
            'username': 'user',
            'password': '',
          },
        ),
        throwsA(isA<HeroFailure>()),
      );
    },
  );
}
