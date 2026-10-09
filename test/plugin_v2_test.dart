import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/plugins/plugin_manifest.dart';
import 'package:picora/hero/plugins/plugin_package.dart';
import 'package:picora/hero/plugins/plugin_manager.dart';
import 'package:picora/hero/plugins/uploader_registry.dart';

Map<String, dynamic> program() =>
    jsonDecode(File('test/fixtures/imgloc/uploader.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> metadata() =>
    jsonDecode(File('test/fixtures/imgloc/plugin.json').readAsStringSync())
        as Map<String, dynamic>;
PicoraPluginManifest manifest([Map<String, dynamic>? value]) {
  final json = {...value ?? program(), ...metadata()}
    ..remove('packageVersion')
    ..remove('runtime')
    ..remove('entry')
    ..remove('icon')
    ..remove('repository');
  return PicoraPluginManifest.fromJson(json);
}

Uint8List archiveBytes({
  Map<String, dynamic>? meta,
  Map<String, dynamic>? body,
}) {
  final archive = Archive();
  archive.add(
    ArchiveFile.bytes(
      'plugin.json',
      utf8.encode(jsonEncode(meta ?? metadata())),
    ),
  );
  archive.add(
    ArchiveFile.bytes(
      'uploader.json',
      utf8.encode(jsonEncode(body ?? program())),
    ),
  );
  archive.add(ArchiveFile.bytes('readme.md', utf8.encode('# ImgLoc')));
  archive.add(
    ArchiveFile.bytes(
      'assets/icon.svg',
      File('test/fixtures/imgloc/assets/icon.svg').readAsBytesSync(),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Response<Object?> reply(
  RequestOptions o,
  Object? data, {
  int status = 200,
  String? location,
}) => Response<Object?>(
  requestOptions: o,
  data: data,
  statusCode: status,
  headers: Headers.fromMap({
    if (location != null) 'location': [location],
  }),
);
Dio transport(FutureOr<Response<Object?>> Function(RequestOptions) handle) {
  final dio = Dio(
    BaseOptions(
      headers: {'Leaked-Global': 'global-secret'},
      queryParameters: {'global': 'secret'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) async {
        try {
          h.resolve(await handle(o));
        } on DioException catch (e) {
          h.reject(e);
        }
      },
    ),
  );
  return dio;
}

Future<dynamic> upload(
  PluginHttpRuntime runtime, {
  PicoraPluginManifest? plugin,
  String group = 'A',
  Map<String, dynamic> config = const {},
}) => runtime.upload(
  plugin ?? manifest(),
  path: File('artifacts/plugin-v2.png').absolute.path,
  name: 'pixel.png',
  config: config,
  configurationId: group,
);
Map<String, dynamic> credentials(String token, {Object ttl = 3600}) => {
  'ok': true,
  'token': token,
  'ttl': ttl,
};
Map<String, dynamic> uploaded() => {
  'ok': true,
  'url': 'https://i.imgs.ovh/test.png',
  'deleteKey': 'one-image',
};
Map<String, dynamic> deletable() {
  final p = program();
  p['permissions']['deleteUploadedFile'] = true;
  p['upload']['response']['deleteKey'] = 'deleteKey';
  p['delete'] = {
    'method': 'POST',
    'url': 'https://imgloc.com/delete',
    'body': {
      'type': 'json',
      'fields': {'key': r'${upload.deleteKey}'},
    },
    'response': {
      'success': {'path': 'ok', 'equals': true},
      'errorMessage': 'message',
    },
  };
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await Directory('artifacts').create(recursive: true);
    await File(
      'artifacts/plugin-v2.png',
    ).writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
  });

  test(
    'ZIP v2 keeps prepare/cache/conditions through parse, serialization and legacy wrapping',
    () {
      final package = PicoraPluginPackage.decode(archiveBytes());
      expect(package.manifest.prepare.single.request.response, isNull);
      expect(package.manifest.prepare.single.cache!.ttlFrom, 'ttl');
      final wrapped = PicoraPluginPackage.fromLegacy(
        PicoraPluginManifest.parse(package.manifest.encode()),
      );
      expect(wrapped.metadata['runtime'], 'http-v2');
      expect(wrapped.manifest.toJson(), package.manifest.toJson());
    },
  );

  test(
    'installer rejects incompatible runtime/schema, unsupported capability and unknown program fields',
    () {
      for (final data in [
        program()..['schemaVersion'] = 1,
        program()..['requires'] = ['arbitrary-js'],
        program()..['unknown'] = {},
      ]) {
        expect(
          () => PicoraPluginPackage.decode(archiveBytes(body: data)),
          throwsA(isA<HeroFailure>()),
        );
      }
      expect(
        () => PicoraPluginPackage.decode(
          archiveBytes(meta: metadata()..['runtime'] = 'http-v1'),
        ),
        throwsA(isA<HeroFailure>()),
      );
    },
  );

  test(
    'installer rejects file/global config reads, missing prior export and unrestricted hosts',
    () {
      for (final variable in [
        r'${file.bytes}',
        r'${config.otherAccount}',
        r'${steps.future.token}',
      ]) {
        final p = program();
        p['prepare'][0]['headers'] = {'X-Test': variable};
        expect(
          () => manifest(p),
          throwsA(isA<HeroFailure>()),
          reason: variable,
        );
      }
      for (final host in ['*', '*.com', 'config.password']) {
        final p = program();
        p['permissions']['network'] = [host];
        expect(() => manifest(p), throwsA(isA<HeroFailure>()), reason: host);
      }
      final p = program();
      p['prepare'].add(p['prepare'].first);
      expect(() => manifest(p), throwsA(isA<HeroFailure>()));
    },
  );

  test(
    'installer disallows broad retries, file sends outside upload and delete with account credentials',
    () {
      for (final refresh in [
        {
          'steps': ['auth'],
          'statuses': [500],
        },
        {
          'steps': ['auth'],
          'statuses': [403],
        },
        {
          'steps': ['auth'],
          'statuses': [200],
          'condition': {'path': 'ok', 'equals': false},
        },
        {
          'steps': ['auth'],
          'statuses': [401],
          'maxAttempts': 2,
        },
      ]) {
        final p = program();
        p['upload']['refreshCredentials'] = refresh;
        expect(() => manifest(p), throwsA(isA<HeroFailure>()));
      }
      final p = program();
      p['prepare'][0]['body'] = {'type': 'binary'};
      expect(() => manifest(p), throwsA(isA<HeroFailure>()));
      final d = deletable();
      d['config'] = [
        {'key': 'admin', 'label': 'Admin', 'type': 'secret'},
      ];
      d['delete']['headers'] = {'Authorization': r'${config.admin}'};
      expect(() => manifest(d), throwsA(isA<HeroFailure>()));
      final all = deletable();
      all['delete']['body']['fields'] = {'all': true};
      expect(() => manifest(all), throwsA(isA<HeroFailure>()));
    },
  );

  test(
    'ImgLoc obtains token then posts image without manual token or inherited global credentials',
    () async {
      final calls = <String>[];
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          calls.add(o.method);
          expect(o.followRedirects, false);
          expect(o.headers.containsKey('Leaked-Global'), false);
          expect(o.queryParameters.containsKey('global'), false);
          if (o.method == 'GET') {
            expect(
              o.uri.toString(),
              'https://imgloc.com/upload.php?action=token',
            );
            expect(o.data, isNull);
            return reply(o, credentials('private-ticket'));
          }
          final form = o.data as FormData;
          expect(form.files.single.key, 'image');
          expect(form.fields.single.value, 'private-ticket');
          return reply(o, uploaded());
        }),
      );
      expect((await upload(runtime))[2], 'https://i.imgs.ovh/test.png');
      expect(calls, ['GET', 'POST']);
    },
  );

  test(
    'concurrent uploads share a single credential fetch in one config group',
    () async {
      var gets = 0, posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) async {
          if (o.method == 'GET') {
            gets++;
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return reply(o, credentials('ticket'));
          }
          posts++;
          return reply(o, uploaded());
        }),
      );
      await Future.wait(List.generate(5, (_) => upload(runtime)));
      expect(gets, 1);
      expect(posts, 5);
      await upload(runtime);
      expect(gets, 1);
      await upload(runtime, group: 'B');
      expect(gets, 2);
      runtime.clearCredentials();
      await upload(runtime);
      expect(gets, 3);
    },
  );

  test(
    'plugin version and configuration changes cannot reuse another credential',
    () async {
      var gets = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'GET') {
            gets++;
            return reply(o, credentials('ticket'));
          }
          return reply(o, uploaded());
        }),
      );
      final p = program();
      p['config'] = [
        {'key': 'account', 'label': 'Account'},
      ];
      final m = manifest(p);
      await upload(
        runtime,
        plugin: m,
        config: {'account': 'a', 'otherSecret': 'discarded'},
      );
      await upload(
        runtime,
        plugin: m,
        config: {'account': 'a', 'otherSecret': 'different'},
      );
      expect(gets, 1);
      await upload(runtime, plugin: m, config: {'account': 'b'});
      expect(gets, 2);
      final changed = m.toJson()..['version'] = '1.1.1';
      await upload(
        runtime,
        plugin: PicoraPluginManifest.fromJson(changed),
        config: {'account': 'b'},
      );
      expect(gets, 3);
      final other = m.toJson()..['id'] = 'other.imgloc.plugin';
      await upload(
        runtime,
        plugin: PicoraPluginManifest.fromJson(other),
        config: {'account': 'b'},
      );
      expect(gets, 4);
    },
  );

  test(
    'TTL cache refreshes 30 seconds early; zero TTL is not retained',
    () async {
      var now = DateTime.utc(2026), gets = 0;
      final runtime = PluginHttpRuntime(
        clock: () => now,
        dio: transport((o) {
          if (o.method == 'GET') {
            gets++;
            return reply(o, credentials('ticket', ttl: 120));
          }
          return reply(o, uploaded());
        }),
      );
      await upload(runtime);
      now = now.add(const Duration(seconds: 89));
      await upload(runtime);
      expect(gets, 1);
      now = now.add(const Duration(seconds: 1));
      await upload(runtime);
      expect(gets, 2);
      final zero = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'GET') {
            gets++;
            return reply(o, credentials('ticket', ttl: 0));
          }
          return reply(o, uploaded());
        }),
      );
      await upload(zero);
      await upload(zero);
      expect(gets, 4);
    },
  );

  test(
    'bad TTL, missing token and business failure stop before upload and are never cached',
    () async {
      for (final data in [
        credentials('ticket', ttl: 'forever'),
        {'ok': true, 'ttl': 3600},
        {'ok': false, 'token': 'ticket', 'ttl': 3600, 'message': 'not allowed'},
      ]) {
        var gets = 0, posts = 0;
        final runtime = PluginHttpRuntime(
          dio: transport((o) {
            if (o.method == 'GET') {
              gets++;
              return reply(o, data);
            }
            posts++;
            return reply(o, uploaded());
          }),
        );
        await expectLater(upload(runtime), throwsA(isA<HeroFailure>()));
        await expectLater(upload(runtime), throwsA(isA<HeroFailure>()));
        expect(gets, 2);
        expect(posts, 0);
      }
    },
  );

  test(
    'explicit credential rejection refreshes and retries exactly once',
    () async {
      var gets = 0, posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'GET') {
            gets++;
            return reply(o, credentials('ticket-$gets'));
          }
          posts++;
          return posts == 1
              ? reply(o, {'ok': false, 'message': 'token expired'}, status: 403)
              : reply(o, uploaded());
        }),
      );
      expect((await upload(runtime))[0], 'success');
      expect(gets, 2);
      expect(posts, 2);
    },
  );

  test(
    'concurrent stale failures merge refresh without revoking a new credential',
    () async {
      var gets = 0, posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) async {
          if (o.method == 'GET') {
            gets++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return reply(o, credentials('ticket-$gets'));
          }
          posts++;
          final token = (o.data as FormData).fields.single.value;
          if (token == 'ticket-1') {
            await Future<void>.delayed(
              Duration(milliseconds: posts == 1 ? 10 : 50),
            );
            return reply(o, {
              'ok': false,
              'message': 'token expired',
            }, status: 403);
          }
          return reply(o, uploaded());
        }),
      );
      await Future.wait([upload(runtime), upload(runtime)]);
      expect(gets, 2);
      expect(posts, 4);
    },
  );

  test(
    'second credential failure stops; quota/5xx/business false with URL never retry',
    () async {
      for (final (status, data) in [
        (403, {'ok': false, 'message': 'token expired'}),
        (403, {'ok': false, 'message': 'quota exceeded'}),
        (500, {'ok': false, 'message': 'token error'}),
        (
          200,
          {
            'ok': false,
            'url': 'https://i.imgs.ovh/already-created.png',
            'message': 'token expired',
          },
        ),
      ]) {
        var posts = 0, gets = 0;
        final runtime = PluginHttpRuntime(
          dio: transport((o) {
            if (o.method == 'GET') {
              gets++;
              return reply(o, credentials('ticket-$gets'));
            }
            posts++;
            return reply(o, data, status: status);
          }),
        );
        await expectLater(upload(runtime), throwsA(isA<HeroFailure>()));
        expect(
          posts,
          status == 403 && data['message'] == 'token expired' ? 2 : 1,
        );
      }
    },
  );

  test(
    'upload timeout has no automatic retry and diagnostics never contain the token',
    () async {
      var posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'GET') return reply(o, credentials('hidden-ticket'));
          posts++;
          throw DioException(
            requestOptions: o,
            type: DioExceptionType.receiveTimeout,
            message: 'server echoed hidden-ticket',
            response: reply(o, {'secret': 'hidden-ticket'}),
          );
        }),
      );
      try {
        await upload(runtime);
        fail('should fail');
      } catch (e, stack) {
        expect(e, isA<PluginExecutionFailure>());
        HeroDiagnostics.instance.record('upload', e, stack: stack);
        final log = jsonEncode(HeroDiagnostics.instance.entries.first);
        expect(log, isNot(contains('hidden-ticket')));
        expect(log, contains('receiveTimeout'));
        expect(log, contains('upload'));
      }
      expect(posts, 1);
    },
  );

  test(
    'arbitrary exported secret name is redacted from mapped business error',
    () async {
      final p = program();
      p['prepare'][0]['response']['exports'] = {
        'ticket': {'path': 'token', 'type': 'string'},
      };
      p['upload']['body']['fields']['token'] = r'${steps.auth.ticket}';
      final runtime = PluginHttpRuntime(
        dio: transport(
          (o) => o.method == 'GET'
              ? reply(o, credentials('secret-not-named-token'))
              : reply(o, {
                  'ok': false,
                  'message': 'Bad secret-not-named-token',
                }),
        ),
      );
      try {
        await upload(runtime, plugin: manifest(p));
        fail('should fail');
      } catch (e, stack) {
        HeroDiagnostics.instance.record('upload', e, stack: stack);
        expect(
          jsonEncode(HeroDiagnostics.instance.entries.first),
          isNot(contains('secret-not-named-token')),
        );
      }
    },
  );

  test(
    'deletion is denied by default, cannot change plugin/config, and checks business success',
    () async {
      var deletes = 0;
      final plugin = manifest(deletable());
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'GET') return reply(o, credentials('ticket'));
          if (o.uri.path == '/delete') {
            deletes++;
            expect(o.data, {'key': 'one-image'});
            return reply(o, {'ok': false, 'message': 'cannot delete'});
          }
          return reply(o, uploaded());
        }),
      );
      final result = await upload(runtime, plugin: plugin);
      final row = {
        'pictureKey': result[3],
        'name': 'pixel.png',
        'path': r'C:\secret\other-account',
      };
      Future<dynamic> remove({
        bool allowed = false,
        String group = 'A',
        Map<String, dynamic>? record,
      }) => runtime.delete(
        plugin,
        deleteMap: record ?? row,
        config: {},
        configurationId: group,
        allowCloudDelete: allowed,
      );
      await expectLater(remove(), throwsA(isA<HeroFailure>()));
      await expectLater(
        remove(allowed: true, group: 'B'),
        throwsA(isA<HeroFailure>()),
      );
      final spoof = jsonDecode(result[3]) as Map<String, dynamic>;
      spoof['plugin'] = 'another.plugin';
      await expectLater(
        remove(allowed: true, record: {'pictureKey': jsonEncode(spoof)}),
        throwsA(isA<HeroFailure>()),
      );
      expect(deletes, 0);
      await expectLater(remove(allowed: true), throwsA(isA<HeroFailure>()));
      expect(deletes, 1);
      final missing = jsonDecode(result[3]) as Map<String, dynamic>
        ..remove('deleteKey');
      await expectLater(
        remove(allowed: true, record: {'pictureKey': jsonEncode(missing)}),
        throwsA(isA<HeroFailure>()),
      );
      expect(deletes, 1);
    },
  );

  test(
    'plugin update revokes the destructive permission while preserving enabled state',
    () async {
      final root = await Directory('artifacts').createTemp('v2-manager-');
      try {
        final manager = PicoraPluginManager(
          registry: UploaderRegistry(),
          storageRoot: root,
        );
        final bytes = archiveBytes(body: deletable());
        await manager.installPackage(bytes);
        expect(manager.isCloudDeleteAllowed('com.imgloc.picora'), false);
        await manager.setCloudDeleteAllowed('com.imgloc.picora', true);
        await manager.setEnabled('com.imgloc.picora', false);
        await manager.installPackage(bytes);
        expect(manager.isCloudDeleteAllowed('com.imgloc.picora'), false);
        expect(manager.isEnabled('com.imgloc.picora'), false);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'redirects default off and every enabled hop checks host and HTTP permission',
    () async {
      for (final target in [
        'https://evil.example/token',
        'http://imgloc.com/token',
        'https://user:pass@imgloc.com/token',
      ]) {
        var calls = 0;
        final p = program();
        p['prepare'][0]['followRedirects'] = true;
        final runtime = PluginHttpRuntime(
          dio: transport((o) {
            calls++;
            return reply(o, null, status: 302, location: target);
          }),
        );
        await expectLater(
          upload(runtime, plugin: manifest(p)),
          throwsA(isA<HeroFailure>()),
        );
        expect(calls, 1);
      }
      final p = program();
      p['prepare'][0].remove('followRedirects');
      p['upload'].remove('followRedirects');
      final m = manifest(p);
      expect(m.upload.followRedirects, false);
      expect(m.prepare.single.request.followRedirects, false);
    },
  );

  test(
    'cross-origin GET strips all custom headers and initial query',
    () async {
      final p = program();
      p['permissions']['network'] = ['imgloc.com', 'auth.imgloc.com'];
      p['prepare'][0]['followRedirects'] = true;
      p['prepare'][0]['headers'] = {'X-Unusual-Secret': 'sensitive'};
      p['prepare'][0]['query'] = {'initial': 'first'};
      var calls = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          calls++;
          if (o.method == 'POST') return reply(o, uploaded());
          if (o.uri.host == 'imgloc.com') {
            return reply(
              o,
              null,
              status: 302,
              location: 'https://auth.imgloc.com/token',
            );
          }
          expect(o.headers.containsKey('X-Unusual-Secret'), false);
          expect(o.queryParameters, isEmpty);
          expect(o.uri.query, isEmpty);
          return reply(o, credentials('ticket'));
        }),
      );
      await upload(runtime, plugin: manifest(p));
      expect(calls, 3);
    },
  );

  test(
    'cross-origin redirect cannot carry config credentials in Location',
    () async {
      final p = program();
      p['config'] = [
        {'key': 'password', 'label': 'Password', 'type': 'secret'},
      ];
      p['permissions']['network'] = ['imgloc.com', 'auth.imgloc.com'];
      p['prepare'][0]['followRedirects'] = true;
      var calls = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          calls++;
          return reply(
            o,
            null,
            status: 302,
            location: 'https://auth.imgloc.com/?q=private-password',
          );
        }),
      );
      await expectLater(
        upload(
          runtime,
          plugin: manifest(p),
          config: {'password': 'private-password'},
        ),
        throwsA(isA<HeroFailure>()),
      );
      expect(calls, 1);
    },
  );

  test('cross-origin upload and same-origin 307 cannot replay file', () async {
    for (final target in [
      'https://auth.imgloc.com/upload',
      'https://imgloc.com/new-upload',
    ]) {
      final p = program();
      p['permissions']['network'] = ['imgloc.com', 'auth.imgloc.com'];
      p['upload']['followRedirects'] = true;
      var posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'GET') return reply(o, credentials('ticket'));
          posts++;
          return reply(o, null, status: 307, location: target);
        }),
      );
      await expectLater(
        upload(runtime, plugin: manifest(p)),
        throwsA(isA<HeroFailure>()),
      );
      expect(posts, 1);
    }
  });

  test(
    'same-origin 303 becomes GET without body and redirect loops are bounded',
    () async {
      final p = program();
      p['upload']['followRedirects'] = true;
      var posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.uri.path == '/result') {
            expect(o.method, 'GET');
            expect(o.data, isNull);
            return reply(o, uploaded());
          }
          if (o.method == 'GET') return reply(o, credentials('ticket'));
          posts++;
          return reply(o, null, status: 303, location: '/result');
        }),
      );
      await upload(runtime, plugin: manifest(p));
      expect(posts, 1);
      p['prepare'][0]['followRedirects'] = true;
      p['prepare'][0]['maxRedirects'] = 2;
      var calls = 0;
      final loop = PluginHttpRuntime(
        dio: transport((o) {
          calls++;
          return reply(o, null, status: 302, location: '/token');
        }),
      );
      await expectLater(
        upload(loop, plugin: manifest(p)),
        throwsA(isA<HeroFailure>()),
      );
      expect(calls, 3);
    },
  );

  test('configured endpoint permission binds scheme, host and port', () async {
    final p = program();
    p['config'] = [
      {'key': 'baseUrl', 'label': 'Endpoint'},
    ];
    p['permissions']['network'] = ['config.baseUrl'];
    var calls = 0;
    final runtime = PluginHttpRuntime(
      dio: transport((o) {
        calls++;
        return reply(o, credentials('ticket'));
      }),
    );
    await expectLater(
      upload(
        runtime,
        plugin: manifest(p),
        config: {'baseUrl': 'https://imgloc.com:8443'},
      ),
      throwsA(isA<HeroFailure>()),
    );
    expect(calls, 0);
  });

  test(
    'actual streamed responses obey body size limit before upload',
    () async {
      var posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.method == 'POST') {
            posts++;
            return reply(o, uploaded());
          }
          return reply(
            o,
            ResponseBody(
              Stream.fromIterable([Uint8List(600000), Uint8List(600000)]),
              200,
            ),
          );
        }),
      );
      await expectLater(upload(runtime), throwsA(isA<HeroFailure>()));
      expect(posts, 0);
    },
  );

  test(
    'clearing cache while credential request is in flight discards response',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var posts = 0;
      final runtime = PluginHttpRuntime(
        dio: transport((o) async {
          if (o.method == 'GET') {
            started.complete();
            await release.future;
            return reply(o, credentials('ticket'));
          }
          posts++;
          return reply(o, uploaded());
        }),
      );
      final pending = upload(runtime);
      final expectation = expectLater(pending, throwsA(isA<HeroFailure>()));
      await started.future;
      runtime.clearCredentials();
      release.complete();
      await expectation;
      expect(posts, 0);
    },
  );

  test(
    'ordered requests only expose declared exports to later requests',
    () async {
      final p = program();
      p['prepare'].add({
        'id': 'next',
        'method': 'GET',
        'url': 'https://imgloc.com/check',
        'headers': {'X-Ticket': r'${steps.auth.token}'},
        'response': {
          'exports': {
            'ticket': {'path': 'replacement', 'type': 'string'},
          },
        },
      });
      p['upload']['body']['fields']['token'] = r'${steps.next.ticket}';
      final runtime = PluginHttpRuntime(
        dio: transport((o) {
          if (o.uri.path == '/check') {
            expect(o.headers['X-Ticket'], 'ticket');
            return reply(o, {'replacement': 'second'});
          }
          if (o.method == 'GET') return reply(o, credentials('ticket'));
          expect((o.data as FormData).fields.single.value, 'second');
          return reply(o, uploaded());
        }),
      );
      await upload(runtime, plugin: manifest(p));
    },
  );
}
