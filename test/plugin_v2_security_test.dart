import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';
import 'plugin_v2_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Directory('artifacts').create(recursive: true);
    await File(
      'artifacts/plugin-v2.png',
    ).writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
  });

  test(
    'changed configuration refuses old image deletion before any network request',
    () async {
      var calls = 0;
      final p = fixture.deletable();
      p['config'] = [
        {'key': 'account', 'label': 'Account'},
      ];
      final plugin = fixture.manifest(p);
      final runtime = PluginHttpRuntime(
        dio: fixture.transport((o) {
          calls++;
          return o.method == 'GET'
              ? fixture.reply(o, fixture.credentials('ticket'))
              : fixture.reply(o, fixture.uploaded());
        }),
      );
      final result = await fixture.upload(
        runtime,
        plugin: plugin,
        config: {'account': 'old'},
      );
      final before = calls;
      await expectLater(
        runtime.delete(
          plugin,
          deleteMap: {'pictureKey': result[3]},
          config: {'account': 'new'},
          configurationId: 'A',
          allowCloudDelete: true,
        ),
        throwsA(isA<HeroFailure>()),
      );
      expect(calls, before);
    },
  );

  test(
    'Basic auth encoded value cannot leak in redirect Location or mapped errors',
    () async {
      final p = fixture.program();
      p['config'] = [
        {'key': 'username', 'label': 'Username'},
        {'key': 'password', 'label': 'Password', 'type': 'secret'},
      ];
      p['permissions']['network'] = ['imgloc.com', 'auth.imgloc.com'];
      p['prepare'][0]['followRedirects'] = true;
      p['prepare'][0]['headers'] = {
        'Authorization': r'${basicAuth(config.username,config.password)}',
      };
      var calls = 0;
      final encoded = base64Encode(utf8.encode('user:pass'));
      final runtime = PluginHttpRuntime(
        dio: fixture.transport((o) {
          calls++;
          return fixture.reply(
            o,
            null,
            status: 302,
            location: 'https://auth.imgloc.com/?session=$encoded',
          );
        }),
      );
      await expectLater(
        fixture.upload(
          runtime,
          plugin: fixture.manifest(p),
          config: {'username': 'user', 'password': 'pass'},
        ),
        throwsA(isA<HeroFailure>()),
      );
      expect(calls, 1);
    },
  );

  test('oversized full query URL is rejected before transmission', () async {
    final p = fixture.program();
    p['prepare'][0]['query'] = {'a': 'x' * 16384, 'b': 'x' * 16384};
    var calls = 0;
    final runtime = PluginHttpRuntime(
      dio: fixture.transport((o) {
        calls++;
        return fixture.reply(o, fixture.credentials('ticket'));
      }),
    );
    await expectLater(
      fixture.upload(runtime, plugin: fixture.manifest(p)),
      throwsA(isA<HeroFailure>()),
    );
    expect(calls, 0);
  });

  test('overly deep or large program is rejected at install', () {
    final p = fixture.program();
    Object value = 'leaf';
    for (var i = 0; i < 30; i++) {
      value = {'nested': value};
    }
    p['upload']['body']['fields']['deep'] = value;
    expect(() => fixture.manifest(p), throwsA(isA<HeroFailure>()));
    final large = fixture.program();
    large['upload']['body']['fields']['items'] = List.filled(5001, 'value');
    expect(() => fixture.manifest(large), throwsA(isA<HeroFailure>()));
  });

  test(
    'successful stream response decodes JSON and enforces business condition',
    () async {
      final runtime = PluginHttpRuntime(
        dio: fixture.transport((o) {
          final data = o.method == 'GET'
              ? fixture.credentials('ticket')
              : fixture.uploaded();
          return fixture.reply(
            o,
            ResponseBody.fromString(jsonEncode(data), 200),
          );
        }),
      );
      expect((await fixture.upload(runtime))[0], 'success');
    },
  );
}
