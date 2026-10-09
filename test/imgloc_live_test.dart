import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picora/hero/plugins/plugin_package.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';

class _LiveHttp extends HttpOverrides {}

void main() {
  test(
    'ImgLoc live automatic token upload (explicit opt-in)',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final archive = Archive();
        final root = Directory('test/fixtures/imgloc');
        for (final file in root.listSync(recursive: true).whereType<File>()) {
          final path = file.path
              .substring(root.path.length + 1)
              .replaceAll(r'\', '/');
          archive.add(ArchiveFile.bytes(path, file.readAsBytesSync()));
        }
        final plugin = PicoraPluginPackage.decode(
          ZipEncoder().encode(archive),
        ).manifest;
        final file = File('artifacts/imgloc-live-pixel.png');
        await file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jAqkAAAAASUVORK5CYII=',
          ),
        );
        final dio = Dio();
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () =>
              HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:7890',
        );
        try {
          final runtime = PluginHttpRuntime(dio: dio);
          final result = await runtime.upload(
            plugin,
            path: file.absolute.path,
            name: 'picora-protocol-v2-test.png',
            config: const {},
            configurationId: 'live-protocol-test',
          );
          expect(result[0], 'success');
          expect(Uri.parse(result[2] as String).scheme, 'https');
          await File('artifacts/imgloc-live-result.json').writeAsString(
            jsonEncode({
              'time': DateTime.now().toUtc().toIso8601String(),
              'url': result[2],
              'pluginVersion': plugin.version,
            }),
          );
          // Tokens and response bodies are deliberately excluded from the output.
        } finally {
          dio.close(force: true);
        }
      }, _LiveHttp());
    },
    skip: !const bool.fromEnvironment('PICORA_LIVE_IMGLOC'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
