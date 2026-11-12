import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'diagnostics.dart';
import 'github_mirrors.dart';
import 'plugins/plugin_catalog.dart';

class MirrorProbeResult {
  final GitHubMirror mirror;
  final Duration? elapsed;
  final String? error;
  const MirrorProbeResult(this.mirror, {this.elapsed, this.error});
  bool get available => elapsed != null && error == null;
}

class GitHubMirrorProbe {
  final Dio dio;
  final Duration timeout;
  GitHubMirrorProbe({Dio? dio, this.timeout = const Duration(seconds: 8)})
    : dio = dio ?? Dio();

  Future<MirrorProbeResult> probe(
    GitHubMirror mirror, {
    CancelToken? cancelToken,
  }) async {
    final cancel = cancelToken ?? CancelToken();
    final watch = Stopwatch()..start();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      cancel.cancel('probe timeout');
    });
    try {
      await _fetch(mirror, cancel, watch).timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          cancel.cancel('probe timeout');
          throw TimeoutException('probe timeout');
        },
      );
      return MirrorProbeResult(mirror, elapsed: watch.elapsed);
    } catch (error, stack) {
      final message = timedOut
          ? '超时'
          : cancel.isCancelled
          ? '已取消'
          : error is TimeoutException ||
                error is DioException &&
                    {
                      DioExceptionType.connectionTimeout,
                      DioExceptionType.sendTimeout,
                      DioExceptionType.receiveTimeout,
                    }.contains(error.type)
          ? '超时'
          : error is HeroFailure
          ? error.message
          : error is FormatException
          ? '目录响应无效'
          : '连接失败';
      if (message != '已取消') {
        HeroDiagnostics.instance.record(
          'GitHub 镜像测速',
          HeroFailure(message),
          stack: stack,
          context: {'mirror': mirror.id},
        );
      }
      return MirrorProbeResult(mirror, error: message);
    } finally {
      timer.cancel();
      watch.stop();
    }
  }

  Future<void> _fetch(
    GitHubMirror mirror,
    CancelToken cancel,
    Stopwatch watch,
  ) async {
    var uri = GitHubMirrors.instance.resolve(
      Uri.parse(PluginCatalogService.indexUrl),
      mirror: mirror,
    );
    for (var hop = 0; ; hop++) {
      if (cancel.isCancelled) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: uri.toString()),
          reason: 'cancelled',
        );
      }
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('probe timeout');
      final response = await dio.fetch<ResponseBody>(
        RequestOptions(
          path: uri.toString(),
          method: 'GET',
          headers: {'Accept': 'application/json', 'Cache-Control': 'no-cache'},
          responseType: ResponseType.stream,
          connectTimeout: remaining,
          receiveTimeout: remaining,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (_) => true,
          cancelToken: cancel,
        ),
      );
      final body = response.data;
      if (body == null) throw const HeroFailure('目录响应为空');
      final status = response.statusCode ?? 0;
      if ({301, 302, 303, 307, 308}.contains(status)) {
        await body.stream.listen((_) {}).cancel();
        final location = response.headers.value('location');
        if (hop >= 3 || location == null) throw const HeroFailure('重定向失败');
        final target = uri.resolve(location);
        if (target.scheme != 'https' ||
            target.host.isEmpty ||
            target.userInfo.isNotEmpty) {
          throw const HeroFailure('重定向地址无效');
        }
        uri = target;
        continue;
      }
      if (status != 200) {
        await body.stream.listen((_) {}).cancel();
        throw HeroFailure('HTTP $status');
      }
      final bytes = BytesBuilder(copy: false);
      final stream = StreamIterator<List<int>>(body.stream);
      unawaited(
        cancel.whenCancel
            .then((_) => stream.cancel())
            .catchError((Object _) {}),
      );
      try {
        while (await stream.moveNext().timeout(timeout - watch.elapsed)) {
          if (bytes.length + stream.current.length >
              PluginCatalogService.maxIndexBytes) {
            throw const HeroFailure('目录响应过大');
          }
          bytes.add(stream.current);
        }
      } finally {
        await stream.cancel();
      }
      if (cancel.isCancelled) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: uri.toString()),
          reason: 'cancelled',
        );
      }
      PluginCatalog.parse(utf8.decode(bytes.takeBytes()));
      return;
    }
  }
}
