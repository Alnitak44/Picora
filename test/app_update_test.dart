import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picora/hero/app_updates.dart';
import 'package:picora/hero/controller.dart';
import 'package:picora/hero/diagnostics.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/hero/settings_page.dart';

Map<String, dynamic> releaseJson({
  String tag = 'v1.1.0',
  String name = 'Picora-arm64-release.apk',
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/Alnitak44/Picora/releases/tag/$tag',
  'draft': false,
  'prerelease': false,
  'body': '## 更新\n修复上传问题。',
  'assets': <dynamic>[
    <String, dynamic>{
      'name': name,
      'state': 'uploaded',
      'browser_download_url':
          'https://github.com/Alnitak44/Picora/releases/download/$tag/$name',
      'size': 123456,
      'digest': 'sha256:${List.filled(64, 'a').join()}',
    },
  ],
};

Dio mockDio(void Function(RequestOptions, RequestInterceptorHandler) request) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: request));
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'semantic precedence handles numeric segments, prereleases and metadata',
    () {
      final ordered = [
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
        '1.0.1',
        '1.9.0',
        '1.10.0',
        '2.0.0',
      ];
      for (var i = 1; i < ordered.length; i++) {
        expect(
          AppVersion.parse(
            ordered[i],
          ).compareTo(AppVersion.parse(ordered[i - 1])),
          greaterThan(0),
        );
      }
      expect(
        AppVersion.parse(
          'v1.0.0+2002',
        ).compareTo(AppVersion.parse('1.0.0+2001')),
        0,
      );
      for (final invalid in ['main', '1.0', '01.0.0', '1.0.0-beta.01']) {
        expect(() => AppVersion.parse(invalid), throwsFormatException);
      }
    },
  );

  test('debug suffix does not create a same-version or downgrade update', () {
    final release = AppRelease.fromJson(releaseJson(tag: 'v1.0.0'));
    expect(release.isNewerThan('1.0.0-debug'), isFalse);
    expect(release.isNewerThan('1.0.0-debug+2002'), isFalse);
    expect(release.isNewerThan('1.0.1'), isFalse);
    expect(release.isNewerThan('1.0.0-rc.1-debug'), isTrue);
    expect(release.isNewerThan('0.9.0-debug'), isTrue);
  });

  test('APK selection checks ABI and keeps API digest', () {
    final release = AppRelease.fromJson(releaseJson());
    expect(release.apkFor('arm64-v8a')?.sha256, List.filled(64, 'a').join());
    expect(release.apkFor('x86_64'), isNull);
    final generic = AppRelease.fromJson(releaseJson(name: 'Picora.apk'));
    expect(generic.apkFor('x86_64')?.name, 'Picora.apk');
    final multiple = releaseJson();
    (multiple['assets'] as List).add(
      Map<String, dynamic>.from((multiple['assets'] as List).first),
    );
    expect(AppRelease.fromJson(multiple).apkFor('arm64-v8a'), isNull);
  });

  test('invalid URLs, drafts, prereleases and digests are rejected', () {
    for (final patch in [
      {'draft': true},
      {'prerelease': true},
      {'tag_name': 'main'},
      {'tag_name': 'v1.1.0-beta.1'},
      {'html_url': 'https://github.com/another/project/releases/tag/v1.1.0'},
    ]) {
      expect(
        () => AppRelease.fromJson({...releaseJson(), ...patch}),
        throwsA(isA<HeroFailure>()),
      );
    }
    for (final patch in [
      {
        'browser_download_url':
            'http://github.com/Alnitak44/Picora/releases/download/v1.1.0/app.apk',
      },
      {'browser_download_url': 'https://example.com/app.apk'},
      {'digest': 'sha256:invalid'},
      {'size': 0},
    ]) {
      final data = releaseJson();
      (data['assets'] as List)[0] = {
        ...((data['assets'] as List).first as Map),
        ...patch,
      };
      expect(() => AppRelease.fromJson(data), throwsA(isA<HeroFailure>()));
    }
    final noDigest = releaseJson();
    ((noDigest['assets'] as List).first as Map)['digest'] = null;
    expect(AppRelease.fromJson(noDigest).apkFor('arm64-v8a')?.sha256, isNull);
  });

  test('Release with no APK is still available through its page', () {
    final release = AppRelease.fromJson({...releaseJson(), 'assets': []});
    expect(release.isNewerThan('1.0.0'), isTrue);
    expect(release.apkFor('arm64-v8a'), isNull);
  });

  test(
    'latest reads the Release API, caches and revalidates with ETag',
    () async {
      var calls = 0;
      var time = DateTime(2026, 10, 8);
      final service = AppUpdateService(
        now: () => time,
        dio: mockDio((options, handler) {
          expect(options.uri.toString(), AppUpdateService.latestUrl);
          expect(options.headers.containsKey('Authorization'), isFalse);
          calls++;
          if (calls == 1) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: releaseJson(),
                headers: Headers.fromMap({
                  'etag': ['"release-1"'],
                }),
              ),
            );
          } else {
            expect(options.headers['If-None-Match'], '"release-1"');
            handler.resolve(Response(requestOptions: options, statusCode: 304));
          }
        }),
      );
      final first = await service.latest();
      expect((await service.latest()), same(first));
      expect(calls, 1);
      expect(await service.latest(forceRefresh: true), same(first));
      expect(calls, 2);
      time = time.add(const Duration(hours: 7));
      await service.latest();
      expect(calls, 3);
    },
  );

  test(
    '404 means no stable release and clears previously cached data',
    () async {
      var calls = 0;
      final service = AppUpdateService(
        dio: mockDio((options, handler) {
          calls++;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: calls == 1 ? 200 : 404,
              data: calls == 1 ? releaseJson() : {'message': 'Not Found'},
            ),
          );
        }),
      );
      expect(await service.latest(), isNotNull);
      expect(await service.latest(forceRefresh: true), isNull);
      expect(await service.latest(), isNull);
      expect(calls, 2);
    },
  );

  test('rate limits and timeout never masquerade as no update', () async {
    for (final status in [403, 429, 500]) {
      final service = AppUpdateService(
        dio: mockDio((options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: status),
            ),
          );
        }),
      );
      await expectLater(service.latest(), throwsA(isA<DioException>()));
    }
    final service = AppUpdateService(
      dio: mockDio((options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          ),
        );
      }),
    );
    await expectLater(service.latest(), throwsA(isA<DioException>()));
  });

  test('malformed API responses do not populate the release cache', () async {
    var calls = 0;
    final service = AppUpdateService(
      dio: mockDio((options, handler) {
        calls++;
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: calls == 1 ? '<html>proxy error</html>' : releaseJson(),
          ),
        );
      }),
    );
    await expectLater(service.latest(), throwsA(isA<HeroFailure>()));
    expect(await service.latest(), isNotNull);
    expect(calls, 2);
  });

  Future<void> settings(WidgetTester tester, AppUpdateService updates) async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: heroTheme(Brightness.light),
        home: Scaffold(
          body: SettingsPage(
            controller: PicoraController()..initializing = false,
            openRepositories: () {},
            updateService: updates,
            appInfoLoader: () async => PackageInfo(
              appName: 'Picora',
              packageName: 'io.github.alnitak44.picora',
              version: '1.0.0-debug',
              buildNumber: '2002',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('检查更新'), 400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings offers newer release with notes and download action', (
    tester,
  ) async {
    await settings(
      tester,
      AppUpdateService(
        dio: mockDio((options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: releaseJson(),
            ),
          );
        }),
      ),
    );
    expect(find.text('发现新版本 v1.1.0'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
    expect(find.text('打开发布页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings distinguishes no release from a current version', (
    tester,
  ) async {
    await settings(
      tester,
      AppUpdateService(
        dio: mockDio((options, handler) {
          handler.resolve(Response(requestOptions: options, statusCode: 404));
        }),
      ),
    );
    expect(find.text('尚无正式发布版本'), findsOneWidget);
    expect(find.textContaining('已是最新版本'), findsNothing);
  });

  testWidgets('settings reports GitHub failure rather than latest version', (
    tester,
  ) async {
    await settings(
      tester,
      AppUpdateService(
        dio: mockDio((options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: 429),
            ),
          );
        }),
      ),
    );
    expect(find.textContaining('GitHub 请求受限'), findsOneWidget);
    expect(find.textContaining('已是最新版本'), findsNothing);
  });
}
