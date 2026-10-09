import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import 'package:picora/album/album_sql.dart';
import 'package:picora/utils/common_functions.dart';
import 'package:picora/utils/deleter.dart';
import 'package:picora/utils/uploader.dart';

import '../diagnostics.dart';
import 'plugin_manifest.dart';
import 'plugin_protocol.dart';

typedef ProviderUpload =
    Future<dynamic> Function({
      required String path,
      required String name,
      required Map<String, dynamic> config,
    });

typedef ProviderDelete =
    Future<dynamic> Function({
      required Map<String, dynamic> deleteMap,
      required Map<String, dynamic> config,
    });

class ProviderAdapter {
  final ProviderUpload upload;
  final ProviderDelete? delete;
  final bool enabled;
  final PicoraPluginManifest? manifest;

  const ProviderAdapter({
    required this.upload,
    required this.delete,
    this.enabled = true,
    this.manifest,
  });
}

class UploaderRegistry {
  final Map<String, ProviderAdapter> _providers = {};
  final PluginHttpRuntime runtime;

  UploaderRegistry({PluginHttpRuntime? runtime})
    : runtime = runtime ?? PluginHttpRuntime() {
    for (final entry in uploadFunc.entries) {
      final table = hostToTableNameMap[entry.key];
      final inheritedDelete = table == null ? null : deleteFunc[table];
      _providers[entry.key] = ProviderAdapter(
        upload: ({required path, required name, required config}) async =>
            entry.value(path: path, name: name, configMap: config),
        delete: inheritedDelete == null
            ? null
            : ({required deleteMap, required config}) async =>
                  inheritedDelete(deleteMap: deleteMap, configMap: config),
      );
    }
    _providers['picgo'] = ProviderAdapter(upload: _uploadToPicGo, delete: null);
  }

  void syncPlugins(
    Iterable<PicoraPluginManifest> manifests,
    bool Function(String id) isEnabled,
  ) {
    runtime.clearCredentials();
    _providers.removeWhere((key, _) => key.startsWith('plugin.'));
    for (final manifest in manifests) {
      final enabled = isEnabled(manifest.id);
      _providers[manifest.hostId] = ProviderAdapter(
        enabled: enabled,
        manifest: manifest,
        upload: ({required path, required name, required config}) =>
            runtime.upload(manifest, path: path, name: name, config: config),
        delete: manifest.delete == null
            ? null
            : ({required deleteMap, required config}) => runtime.delete(
                manifest,
                deleteMap: deleteMap,
                config: config,
              ),
      );
    }
  }

  bool contains(String host) => _providers.containsKey(host);
  bool supportsDelete(String host) => _providers[host]?.delete != null;

  Future<dynamic> upload(
    String host, {
    required String path,
    required String name,
    required Map<String, dynamic> config,
    String? configurationId,
  }) async {
    final provider = _providers[host];
    if (provider == null) {
      throw HeroFailure(
        host.startsWith('plugin.')
            ? '该配置对应的插件未安装，请前往插件中心的模块仓库下载'
            : '未找到上传器：$host',
      );
    }
    if (!provider.enabled) throw const HeroFailure('该插件已停用，请先在插件中心启用');
    if (provider.manifest != null) {
      return runtime.upload(
        provider.manifest!,
        path: path,
        name: name,
        config: config,
        configurationId: configurationId,
      );
    }
    return provider.upload(path: path, name: name, config: config);
  }

  Future<dynamic> delete(
    String host, {
    required Map<String, dynamic> deleteMap,
    required Map<String, dynamic> config,
    String? configurationId,
    bool allowCloudDelete = false,
  }) async {
    final provider = _providers[host];
    if (provider == null) {
      throw HeroFailure(
        host.startsWith('plugin.')
            ? '该配置对应的插件未安装，请前往插件中心的模块仓库下载'
            : '未找到上传器：$host',
      );
    }
    if (!provider.enabled) throw const HeroFailure('该插件已停用，无法删除云端文件');
    if (provider.delete == null) {
      throw const HeroFailure('此图床未提供云端删除接口，请关闭同步删除云端文件');
    }
    if (provider.manifest != null) {
      return runtime.delete(
        provider.manifest!,
        deleteMap: deleteMap,
        config: config,
        configurationId: configurationId,
        allowCloudDelete: allowCloudDelete,
      );
    }
    return provider.delete!(deleteMap: deleteMap, config: config);
  }

  Future<dynamic> _uploadToPicGo({
    required String path,
    required String name,
    required Map<String, dynamic> config,
  }) async {
    final server = _requiredConfig(
      config,
      'serverUrl',
    ).replaceAll(RegExp(r'/+$'), '');
    final base = Uri.tryParse(server);
    if (base == null ||
        !['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty) {
      throw const HeroFailure('PicGo Server 地址无效');
    }
    final query = <String, dynamic>{};
    for (final key in ['uploader', 'configName', 'configId']) {
      final value = _optionalConfig(config, key);
      if (value != null) query[key] = value;
    }
    final secret = _optionalConfig(config, 'secret');
    final timeout =
        int.tryParse(_optionalConfig(config, 'timeoutSeconds') ?? '') ?? 90;
    final dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: timeout.clamp(5, 300)),
        sendTimeout: Duration(seconds: timeout.clamp(5, 300)),
        receiveTimeout: Duration(seconds: timeout.clamp(5, 300)),
        validateStatus: (_) => true,
      ),
    );
    final response = await dio.post<Object?>(
      '$server/upload',
      queryParameters: query,
      data: FormData.fromMap({
        'files': await MultipartFile.fromFile(path, filename: name),
      }),
      options: Options(
        headers: secret == null ? null : {'Authorization': 'Bearer $secret'},
      ),
    );
    final data = _jsonValue(response.data);
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300 ||
        data is! Map ||
        data['success'] != true) {
      throw HeroFailure(
        'PicGo Server 上传失败（HTTP ${response.statusCode ?? '-'}）',
      );
    }
    String? url;
    String? thumbnail;
    final items = data['items'];
    if (items is List && items.isNotEmpty && items.first is Map) {
      final item = items.first as Map;
      url = _nonEmpty(item['url']) ?? _nonEmpty(item['imgUrl']);
      thumbnail = _nonEmpty(item['imgUrl']) ?? url;
    }
    final result = data['result'];
    if (url == null && result is List && result.isNotEmpty) {
      url = _nonEmpty(result.first);
    }
    url ??= _nonEmpty(result);
    if (url == null) throw const HeroFailure('PicGo Server 未返回图片链接');
    thumbnail ??= url;
    return [
      'success',
      getFormatedUrl(url, name),
      url,
      jsonEncode({'bridge': 'picgo', 'url': url}),
      thumbnail,
      url,
    ];
  }
}

class PluginHttpRuntime {
  final Dio dio;
  final DateTime Function() clock;
  final Map<String, _CredentialEntry> _credentials = {};
  final Map<String, Future<_CredentialEntry>> _pending = {};
  int _generation = 0;
  static const maxResponseBytes = 1024 * 1024;
  PluginHttpRuntime({Dio? dio, DateTime Function()? clock})
    : dio = dio ?? Dio(),
      clock = clock ?? DateTime.now;
  void clearCredentials() {
    _generation++;
    _credentials.clear();
    _pending.clear();
  }

  Map<String, dynamic> _configuration(
    PicoraPluginManifest manifest,
    Map<String, dynamic> supplied,
  ) {
    final result = <String, dynamic>{};
    for (final field in manifest.fields) {
      final value = supplied[field.key] ?? field.defaultValue ?? '';
      if (value is! String && value is! num && value is! bool) {
        throw const HeroFailure('配置只能包含标量');
      }
      if (value.toString().length > 16384) throw const HeroFailure('配置字段过长');
      if (field.required && value.toString().trim().isEmpty) {
        throw HeroFailure('请填写${field.label}');
      }
      result[field.key] = value;
    }
    return result;
  }

  Future<dynamic> upload(
    PicoraPluginManifest manifest, {
    required String path,
    required String name,
    required Map<String, dynamic> config,
    String? configurationId,
  }) async {
    final scoped = _configuration(manifest, config), file = File(path);
    if (!await file.exists()) throw const HeroFailure('待上传文件不存在');
    if (await file.length() > 100 * 1024 * 1024) {
      throw const HeroFailure('插件上传文件不能超过 100 MB');
    }
    final context = _TemplateContext(
      config: scoped,
      upload: const {},
      filePath: path,
      fileName: name,
      fileBytes: await file.readAsBytes(),
      resources: manifest.resources,
    );
    final scope = _fingerprint({
      'plugin': manifest.toJson(),
      'resources': manifest.resources.map(
        (k, v) => MapEntry(k, sha256.convert(v).toString()),
      ),
      'configurationId': configurationId ?? const Uuid().v4(),
      'config': scoped,
    });
    final used = <String, _CredentialEntry>{}, generation = _generation;
    await _prepare(manifest, context, scope, used, configurationId, generation);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (generation != _generation) throw const HeroFailure('插件或配置已变更，请重新上传');
      final response = await _execute(
        manifest,
        manifest.upload,
        context,
        includeFile: true,
        step: 'upload',
        configurationId: configurationId,
      );
      final data = response.data, spec = manifest.upload.response!;
      if (!spec.accepts(response.statusCode, data)) {
        final refresh = manifest.upload.refreshCredentials;
        if (attempt == 0 &&
            refresh != null &&
            refresh.matches(response.statusCode, data) &&
            _nonEmpty(readPluginPath(data, spec.urlPath)) == null) {
          // Do not invalidate a fresh credential produced by a concurrent upload.
          for (final id in refresh.steps) {
            final stale = used[id];
            if (stale != null && identical(_credentials[stale.key], stale)) {
              _credentials.remove(stale.key);
            }
          }
          await _prepare(
            manifest,
            context,
            scope,
            used,
            configurationId,
            generation,
          );
          continue;
        }
        throw _failure(
          manifest,
          manifest.upload,
          response,
          context,
          'upload',
          configurationId,
        );
      }
      final raw = readPluginPath(data, spec.urlPath);
      if (raw is! String || raw.isEmpty || raw.length > 16384) {
        throw _problem(
          manifest,
          'upload',
          configurationId,
          'result',
          '上传响应缺少图片链接；结果未知，请先检查图床',
        );
      }
      final url = _absoluteUrl(raw, response.requestOptions.uri);
      final thumb = spec.thumbnailPath == null
          ? null
          : readPluginPath(data, spec.thumbnailPath!);
      final thumbnail = thumb is String && thumb.isNotEmpty
          ? _absoluteUrl(thumb, response.requestOptions.uri)
          : url;
      final deleteKey = spec.deleteKeyPath == null
          ? null
          : readPluginPath(data, spec.deleteKeyPath!);
      if (deleteKey != null &&
          (deleteKey is! String && deleteKey is! num ||
              deleteKey.toString().isEmpty ||
              deleteKey.toString().length > 4096)) {
        throw _problem(
          manifest,
          'upload',
          configurationId,
          'result',
          '删除凭证必须对应单张图片，上传结果请到图床核对',
        );
      }
      final rawDeleteUrl = spec.deleteUrlPath == null
          ? null
          : readPluginPath(data, spec.deleteUrlPath!);
      String? deleteUrl;
      if (rawDeleteUrl != null) {
        if (rawDeleteUrl is! String || rawDeleteUrl.length > 16384) {
          throw const HeroFailure('无效的删除链接');
        }
        deleteUrl = _absoluteUrl(rawDeleteUrl, response.requestOptions.uri);
        _checkUri(manifest, Uri.parse(deleteUrl), context);
      }
      final key = jsonEncode({
        'plugin': manifest.id,
        'url': url,
        if (configurationId != null) 'configurationId': configurationId,
        'configurationRevision': _fingerprint(scoped),
        if (deleteKey != null) 'deleteKey': deleteKey,
        if (deleteUrl != null) 'deleteUrl': deleteUrl,
      });
      return ['success', getFormatedUrl(url, name), url, key, thumbnail, url];
    }
    throw const HeroFailure('凭证刷新后上传仍失败');
  }

  Future<void> _prepare(
    PicoraPluginManifest manifest,
    _TemplateContext context,
    String scope,
    Map<String, _CredentialEntry> used,
    String? configurationId,
    int generation,
  ) async {
    context.steps.clear();
    for (final step in manifest.prepare) {
      final key = _fingerprint({
        'scope': scope,
        'step': step.id,
        'previous': context.steps,
      });
      var entry = step.cache == null ? null : _credentials[key];
      if (entry == null || !clock().isBefore(entry.refreshAt)) {
        if (_pending.length >= 128 && !_pending.containsKey(key)) {
          throw const HeroFailure('凭证请求过多');
        }
        final active = _pending[key];
        if (active != null) {
          entry = await active;
        } else {
          final future = _fetchCredential(
            manifest,
            step,
            context,
            key,
            configurationId,
            generation,
          );
          _pending[key] = future;
          try {
            entry = await future;
          } finally {
            if (identical(_pending[key], future)) _pending.remove(key);
          }
        }
      }
      if (generation != _generation) throw const HeroFailure('插件或配置已变更，凭证已丢弃');
      context.steps[step.id] = entry.values;
      used[step.id] = entry;
      for (final field in step.request.responseRules.exports.entries) {
        if (field.value.secret) {
          context.sensitive.add(entry.values[field.key]?.toString() ?? '');
        }
      }
    }
  }

  Future<_CredentialEntry> _fetchCredential(
    PicoraPluginManifest manifest,
    PluginPrepareSpec step,
    _TemplateContext original,
    String key,
    String? configurationId,
    int generation,
  ) async {
    final context = _TemplateContext(
      config: original.config,
      upload: const {},
      filePath: '',
      fileName: '',
      fileBytes: const [],
      resources: manifest.resources,
      steps: Map.from(original.steps),
      sensitive: original.sensitive,
    );
    final response = await _execute(
      manifest,
      step.request,
      context,
      includeFile: false,
      step: step.id,
      configurationId: configurationId,
    );
    final rules = step.request.responseRules;
    if (!rules.accepts(response.statusCode, response.data)) {
      throw _failure(
        manifest,
        step.request,
        response,
        context,
        step.id,
        configurationId,
      );
    }
    final values = <String, dynamic>{};
    for (final field in rules.exports.entries) {
      final definition = field.value;
      final value = definition.source == 'header'
          ? response.headers.value(definition.path)
          : readPluginPath(response.data, definition.path);
      if (value == null && !definition.required) continue;
      final valid = switch (definition.type) {
        'string' => value is String && value.isNotEmpty && value.length <= 4096,
        'number' => value is num && value.isFinite,
        'boolean' => value is bool,
        _ => false,
      };
      if (!valid) {
        throw _problem(
          manifest,
          step.id,
          configurationId,
          'export',
          '前置请求缺少有效导出字段：${field.key}',
        );
      }
      values[field.key] = value;
      if (definition.secret) context.sensitive.add(value.toString());
    }
    var ttl = 0;
    final cache = step.cache;
    if (cache != null) {
      final raw =
          cache.ttlSeconds ?? readPluginPath(response.data, cache.ttlFrom!);
      if (raw is! num || !raw.isFinite || raw < 0) {
        throw _problem(
          manifest,
          step.id,
          configurationId,
          'ttl',
          '前置响应的凭证 TTL 无效',
        );
      }
      ttl = raw.clamp(0, cache.maxTtlSeconds).floor();
    }
    final early = cache == null
        ? 0
        : cache.refreshBeforeSeconds.clamp(0, ttl ~/ 2);
    final entry = _CredentialEntry(
      key,
      Map.unmodifiable(values),
      clock().add(Duration(seconds: ttl - early)),
    );
    if (ttl > 0 && generation == _generation) {
      if (_credentials.length >= 128) {
        _credentials.remove(_credentials.keys.first);
      }
      _credentials[key] = entry;
    }
    return entry;
  }

  Future<dynamic> delete(
    PicoraPluginManifest manifest, {
    required Map<String, dynamic> deleteMap,
    required Map<String, dynamic> config,
    String? configurationId,
    bool allowCloudDelete = false,
  }) async {
    if (!allowCloudDelete ||
        !manifest.permissions.deleteUploadedFile ||
        manifest.delete == null) {
      throw const HeroFailure('该插件的云端删除权限未开启；上传记录已保留');
    }
    Map<String, dynamic> record;
    try {
      record = Map<String, dynamic>.from(
        jsonDecode(deleteMap['pictureKey']?.toString() ?? ''),
      );
    } catch (_) {
      throw const HeroFailure('上传记录缺少插件删除信息');
    }
    if (record['plugin'] != manifest.id ||
        record['configurationId'] != null &&
            record['configurationId'] != configurationId ||
        manifest.schemaVersion == 2 &&
            (configurationId == null ||
                record['configurationId'] != configurationId ||
                record['configurationRevision'] is! String)) {
      throw const HeroFailure('删除记录与插件或配置组不匹配；上传记录已保留');
    }
    final upload = <String, dynamic>{};
    for (final key in ['url', 'deleteKey', 'deleteUrl']) {
      final value = record[key];
      if (value != null) {
        if (value is! String && value is! num ||
            value.toString().isEmpty ||
            value.toString().length > 16384) {
          throw const HeroFailure('删除凭证只能对应单张图片');
        }
        upload[key] = value;
      }
    }
    final scoped = _configuration(manifest, config);
    if (record['configurationRevision'] != null &&
        record['configurationRevision'] != _fingerprint(scoped)) {
      throw const HeroFailure('原配置已修改，已停止云端删除；上传记录已保留');
    }
    final context = _TemplateContext(
      config: scoped,
      upload: upload,
      filePath: '',
      fileName: '',
      fileBytes: const [],
      resources: manifest.schemaVersion == 1 ? manifest.resources : const {},
    );
    final response = await _execute(
      manifest,
      manifest.delete!,
      context,
      includeFile: false,
      step: 'delete',
      configurationId: configurationId,
    );
    if (!manifest.delete!.responseRules.accepts(
      response.statusCode,
      response.data,
    )) {
      throw _failure(
        manifest,
        manifest.delete!,
        response,
        context,
        'delete',
        configurationId,
      );
    }
    return ['success'];
  }

  void _checkUri(
    PicoraPluginManifest manifest,
    Uri uri,
    _TemplateContext context, {
    Uri? initial,
  }) {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.toString().length > 32768) {
      throw const HeroFailure('插件生成了无效的请求地址');
    }
    if (uri.scheme == 'http' && !manifest.permissions.allowInsecureHttp) {
      throw const HeroFailure('插件未获得明文 HTTP 权限');
    }
    var allowed = false;
    for (final permission in manifest.permissions.networkHosts) {
      if (permission.startsWith('config.')) {
        final input = context.config[permission.substring(7)]?.toString() ?? '';
        final endpoint = Uri.tryParse(
          RegExp(r'^https?://').hasMatch(input) ? input : 'https://$input',
        );
        if (endpoint != null &&
            endpoint.userInfo.isEmpty &&
            _sameOrigin(uri, endpoint)) {
          allowed = true;
        }
      } else if (permission == '*') {
        if (initial == null || _sameOrigin(uri, initial)) allowed = true;
      } else if (permission == uri.host.toLowerCase() ||
          permission.startsWith('*.') &&
              uri.host.toLowerCase().endsWith(permission.substring(1))) {
        allowed = true;
      }
    }
    if (!allowed) throw const HeroFailure('插件请求目标不在已授予的网络权限内');
  }

  Future<Response<Object?>> _execute(
    PicoraPluginManifest manifest,
    PluginRequestSpec request,
    _TemplateContext context, {
    required bool includeFile,
    required String step,
    required String? configurationId,
  }) async {
    try {
      var uri = Uri.parse((await context.render(request.url)).toString());
      _checkUri(manifest, uri, context);
      final initial = uri;
      var headers = <String, dynamic>{}, query = <String, dynamic>{};
      for (final item in request.headers.entries) {
        final value = (await context.render(item.value)).toString();
        if (value.length > 16384 || RegExp(r'[\r\n\x00]').hasMatch(value)) {
          throw const HeroFailure('请求头含有控制字符');
        }
        if (value.isNotEmpty) {
          headers[item.key] = value;
          context.sensitive.add(value);
        }
      }
      for (final item in request.query.entries) {
        query[item.key] = await context.render(item.value);
      }
      final fields =
          await context.render(request.body.fields) as Map<String, dynamic>;
      Object? body;
      switch (request.body.type) {
        case 'multipart':
          if (!includeFile) throw const HeroFailure('此操作不能读取或发送文件');
          body = FormData.fromMap({
            ...fields,
            request.body.fileField: MultipartFile.fromBytes(
              context.fileBytes,
              filename: context.fileName,
              contentType: DioMediaType.parse(
                lookupMimeType(context.fileName) ?? 'application/octet-stream',
              ),
            ),
          });
        case 'json':
          body = fields;
          headers.putIfAbsent('Content-Type', () => Headers.jsonContentType);
        case 'form':
          body = fields;
          headers.putIfAbsent(
            'Content-Type',
            () => Headers.formUrlEncodedContentType,
          );
        case 'binary':
          if (!includeFile) throw const HeroFailure('此操作不能读取或发送文件');
          body = context.fileBytes;
          headers.putIfAbsent(
            'Content-Type',
            () =>
                lookupMimeType(context.fileName) ?? 'application/octet-stream',
          );
        case 'none':
          body = null;
      }
      var method = request.method;
      final stopwatch = Stopwatch()..start();
      for (var hop = 0; ; hop++) {
        final remaining =
            Duration(seconds: request.timeoutSeconds) - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw const HeroFailure('请求超时；未自动重传，请检查图床结果');
        }
        final cancel = CancelToken(),
            timer = Timer(remaining, () => cancel.cancel('plugin deadline'));
        Response<Object?> response;
        try {
          final options = RequestOptions(
            path: uri.toString(),
            queryParameters: query,
          );
          _checkUri(manifest, options.uri, context, initial: initial);
          // Construct fresh options; never inherit a global credential or query.
          response = await dio.fetch<Object?>(
            RequestOptions(
              path: uri.toString(),
              method: method,
              headers: headers,
              queryParameters: query,
              data: body,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true,
              responseType: ResponseType.stream,
              connectTimeout: remaining,
              sendTimeout: remaining,
              receiveTimeout: remaining,
              cancelToken: cancel,
            ),
          );
          final data = response.data;
          if (data is ResponseBody) {
            final bytes = <int>[];
            final iterator = StreamIterator(data.stream);
            try {
              while (true) {
                final left =
                    Duration(seconds: request.timeoutSeconds) -
                    stopwatch.elapsed;
                if (left <= Duration.zero) {
                  throw TimeoutException('plugin deadline');
                }
                if (!await iterator.moveNext().timeout(left)) break;
                final chunk = iterator.current;
                if (bytes.length + chunk.length > maxResponseBytes) {
                  cancel.cancel('plugin response size limit');
                  throw const HeroFailure('插件响应超过 1 MB');
                }
                bytes.addAll(chunk);
              }
            } finally {
              await iterator.cancel();
            }
            response.data = _jsonValue(utf8.decode(bytes));
          } else {
            if (utf8.encode(jsonEncode(data)).length > maxResponseBytes) {
              throw const HeroFailure('插件响应超过 1 MB');
            }
            response.data = _jsonValue(data);
          }
        } finally {
          timer.cancel();
        }
        final status = response.statusCode;
        if (!{301, 302, 303, 307, 308}.contains(status) ||
            !request.followRedirects) {
          return response;
        }
        if (hop >= request.maxRedirects) throw const HeroFailure('超过重定向次数限制');
        final location = response.headers.value('location');
        if (location == null) throw const HeroFailure('重定向响应缺少 Location');
        final target = response.requestOptions.uri.resolve(location);
        _checkUri(manifest, target, context, initial: initial);
        if (!_sameOrigin(uri, target)) {
          if (!{'GET', 'HEAD'}.contains(method) || body != null) {
            throw const HeroFailure('拒绝跨来源发送凭证或上传文件');
          }
          if (context.secrets.any(
            (s) =>
                target.toString().contains(s) ||
                target.toString().contains(Uri.encodeComponent(s)) ||
                target.toString().contains(base64Encode(utf8.encode(s))),
          )) {
            throw const HeroFailure('拒绝向重定向目标传递凭证');
          }
          headers = {};
        }
        if (body != null) {
          if (status == 303 ||
              (status == 301 || status == 302) && method == 'POST') {
            method = 'GET';
            body = null;
            headers.removeWhere(
              (k, _) =>
                  {'content-type', 'content-length'}.contains(k.toLowerCase()),
            );
          } else {
            throw const HeroFailure('拒绝按重定向要求重发请求体，以免重复上传');
          }
        }
        uri = target;
        query = {};
      }
    } on PluginExecutionFailure {
      rethrow;
    } on DioException catch (error) {
      throw _problem(
        manifest,
        step,
        configurationId,
        error.type.name,
        step == 'upload' ? '上传连接失败或超时；结果未知，未自动重传，请先检查图床' : '请求连接失败或超时，请稍后重试',
        status: error.response?.statusCode,
      );
    } on TimeoutException {
      throw _problem(
        manifest,
        step,
        configurationId,
        'receiveTimeout',
        step == 'upload' ? '上传响应超时；结果未知，未自动重传，请先检查图床' : '前置请求超时',
      );
    } on HeroFailure catch (error) {
      throw _problem(
        manifest,
        step,
        configurationId,
        'validation',
        context.sanitize(error.message),
      );
    } catch (_) {
      throw _problem(
        manifest,
        step,
        configurationId,
        'response',
        '插件请求或响应格式无效',
      );
    }
  }

  PluginExecutionFailure _failure(
    PicoraPluginManifest manifest,
    PluginRequestSpec request,
    Response<Object?> response,
    _TemplateContext context,
    String step,
    String? configurationId,
  ) {
    final rules = request.responseRules;
    final raw = rules.errorMessagePath == null
        ? null
        : readPluginPath(response.data, rules.errorMessagePath!);
    final code = rules.errorCodePath == null
        ? null
        : readPluginPath(response.data, rules.errorCodePath!);
    final detail = raw is String && raw.length <= 1000
        ? context.sanitize(raw)
        : context.sanitize(
            request.errorMessages[response.statusCode] ?? '服务器拒绝了请求',
          );
    return _problem(
      manifest,
      step,
      configurationId,
      'business',
      detail,
      status: response.statusCode,
      code: code is String || code is num
          ? context.sanitize(code.toString()).split('').take(64).join()
          : null,
    );
  }

  PluginExecutionFailure _problem(
    PicoraPluginManifest manifest,
    String step,
    String? configurationId,
    String kind,
    String message, {
    int? status,
    String? code,
  }) => PluginExecutionFailure('${manifest.name}：$message', {
    'plugin': manifest.id,
    'configuration': configurationId,
    'step': step,
    'kind': kind,
    if (status != null) 'status': status,
    if (code != null) 'errorCode': code,
  });
}

class _CredentialEntry {
  final String key;
  final Map<String, dynamic> values;
  final DateTime refreshAt;
  const _CredentialEntry(this.key, this.values, this.refreshAt);
}

class PluginExecutionFailure extends HeroFailure
    implements SafeDiagnosticFailure {
  @override
  final Map<String, dynamic> diagnosticDetails;
  const PluginExecutionFailure(super.message, this.diagnosticDetails);
}

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;
String _fingerprint(Object? value) {
  Object? canonical(Object? node) {
    if (node is Map) {
      final keys = node.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(node[key])};
    }
    if (node is List) return node.map(canonical).toList();
    return node;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();
}

class _TemplateContext {
  final Map<String, dynamic> config, upload;
  final Map<String, Map<String, dynamic>> steps;
  final Set<String> sensitive;
  Iterable<String> get secrets => sensitive.where((s) => s.isNotEmpty);
  String sanitize(String message) {
    var result = message;
    final values = secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in values) {
      for (final form in {
        value,
        Uri.encodeComponent(value),
        base64Encode(utf8.encode(value)),
      }) {
        result = result.replaceAll(form, '[REDACTED]');
      }
    }
    return HeroDiagnostics.redact(result).toString();
  }

  final String filePath, fileName;
  final List<int> fileBytes;
  final Map<String, List<int>> resources;
  late final String _uuid = const Uuid().v4();
  late final int _millis = DateTime.now().millisecondsSinceEpoch;

  _TemplateContext({
    required this.config,
    required this.upload,
    required this.filePath,
    required this.fileName,
    required this.fileBytes,
    this.resources = const {},
    Map<String, Map<String, dynamic>>? steps,
    Set<String>? sensitive,
  }) : steps = steps ?? {},
       sensitive =
           sensitive ??
           {
             ...config.values
                 .map((v) => v.toString())
                 .where((s) => s.isNotEmpty),
             ...upload.values
                 .map((v) => v.toString())
                 .where((s) => s.isNotEmpty),
           };

  Future<Object?> render(Object? value) async {
    if (value is List) return Future.wait(value.map(render));
    if (value is Map) {
      final output = <String, dynamic>{};
      for (final entry in value.entries) {
        output[entry.key.toString()] = await render(entry.value);
      }
      return output;
    }
    if (value is! String) return value;
    final exact = RegExp(r'^\$\{([^}]+)\}$').firstMatch(value);
    if (exact != null) {
      final result = _evaluate(exact.group(1)!.trim());
      if (result is String && result.isNotEmpty) sensitive.add(result);
      return result;
    }
    return value.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (match) {
      final result = _evaluate(match.group(1)!.trim());
      final rendered = result is List<int>
          ? base64Encode(result)
          : result.toString();
      if (rendered.isNotEmpty) sensitive.add(rendered);
      return rendered;
    });
  }

  Object _evaluate(String expression) {
    final function = RegExp(
      r'^(base64|sha256|hmacSha256|basicAuth|normalizeBaseUrl|assetText|urlEncode)\((.*)\)$',
    ).firstMatch(expression);
    if (function != null) {
      final name = function.group(1)!;
      final args = function
          .group(2)!
          .split(',')
          .map((item) => _resolve(item.trim()))
          .toList();
      if (name == 'urlEncode' && args.length == 1) {
        return Uri.encodeComponent(args.single.toString());
      }
      if (name == 'base64' && args.length == 1) {
        return base64Encode(_bytes(args.single));
      }
      if (name == 'assetText' && args.length == 1) {
        return utf8.decode(_bytes(args.single));
      }
      if (name == 'sha256' && args.length == 1) {
        return sha256.convert(_bytes(args.single)).toString();
      }
      if (name == 'hmacSha256' && args.length == 2) {
        return Hmac(
          sha256,
          _bytes(args.first),
        ).convert(_bytes(args.last)).toString();
      }
      if (name == 'basicAuth' && args.length == 2) {
        final username = args.first.toString();
        final password = args.last.toString();
        if (username.isEmpty && password.isEmpty) return '';
        if (username.isEmpty || password.isEmpty) {
          throw const HeroFailure('上传用户名和密码需要同时填写；未开启上传鉴权时两项都留空');
        }
        if (username.contains(':') ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch('$username$password')) {
          throw const HeroFailure('上传用户名不能包含冒号，用户名和密码不能包含控制字符');
        }
        final encoded = base64Encode(utf8.encode('$username:$password'));
        sensitive.add(encoded);
        return 'Basic $encoded';
      }
      if (name == 'normalizeBaseUrl' && args.length == 1) {
        return _normalizeBaseUrl(args.single.toString());
      }
      throw HeroFailure('插件模板函数参数无效：$expression');
    }
    return _resolve(expression);
  }

  Object _resolve(String key) {
    if (key.startsWith('assets/')) {
      final bytes = resources[key];
      if (bytes == null) throw HeroFailure('插件资源不存在：$key');
      return bytes;
    }
    if (key == 'uuid') return _uuid;
    if (key == 'time.millis') return _millis;
    if (key == 'time.unix') return _millis ~/ 1000;
    if (key == 'file.path') return filePath;
    if (key == 'file.name') return fileName;
    if (key == 'file.bytes') return fileBytes;
    if (key == 'file.base64') return base64Encode(fileBytes);
    if (key == 'file.mime') {
      return lookupMimeType(filePath) ?? 'application/octet-stream';
    }
    if (key.startsWith('steps.')) {
      final parts = key.split('.');
      final value = steps[parts[1]]?[parts[2]];
      if (value == null) throw const HeroFailure('前置变量未取得');
      return value;
    }
    if (key.startsWith('config.')) {
      return _clean(config[key.substring(7)]);
    }
    if (key.startsWith('upload.')) {
      if ((key == 'upload.deleteKey' || key == 'upload.deleteUrl') &&
          _nonEmpty(upload[key.substring(7)]) == null) {
        throw const HeroFailure('此记录没有单张图片删除凭证，已停止删除');
      }
      return _clean(upload[key.substring(7)]);
    }
    throw HeroFailure('插件模板变量不存在：$key');
  }

  Object _clean(Object? value) =>
      value == null || value == 'None' || value == 'undetermined' ? '' : value;

  List<int> _bytes(Object value) =>
      value is List<int> ? value : utf8.encode(value.toString());
}

String _normalizeBaseUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) {
    throw const HeroFailure('请先填写图床基础 URL');
  }
  if (!RegExp(r'^[a-z][a-z\d+.-]*:', caseSensitive: false).hasMatch(value)) {
    value = 'https://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const HeroFailure('图床网址只能使用 HTTP/HTTPS；请勿附带用户名、密码、查询参数或锚点');
  }
  if (RegExp(r'/upload/?$', caseSensitive: false).hasMatch(uri.path)) {
    throw const HeroFailure('请填写图床基础网址，不要在末尾添加 /upload');
  }
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return uri.replace(path: path).toString().replaceAll(RegExp(r'/+$'), '');
}

Object? _jsonValue(Object? value) {
  if (value is String) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
  return value;
}

String _absoluteUrl(String value, Uri requestUri) {
  final uri = Uri.tryParse(value);
  if (uri == null) throw const HeroFailure('插件返回了无效链接');
  final resolved = uri.hasScheme ? uri : requestUri.resolveUri(uri);
  if (!['http', 'https'].contains(resolved.scheme) ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty) {
    throw const HeroFailure('插件返回的图片链接不是 HTTP 或 HTTPS 地址');
  }
  return resolved.toString();
}

String _requiredConfig(Map<String, dynamic> config, String key) {
  final value = _optionalConfig(config, key);
  if (value == null) throw HeroFailure('缺少配置：$key');
  return value;
}

String? _optionalConfig(Map<String, dynamic> config, String key) {
  final value = config[key]?.toString().trim() ?? '';
  return value.isEmpty || value == 'None' || value == 'undetermined'
      ? null
      : value;
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
