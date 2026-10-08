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

  const ProviderAdapter({
    required this.upload,
    required this.delete,
    this.enabled = true,
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
    _providers.removeWhere((key, _) => key.startsWith('plugin.'));
    for (final manifest in manifests) {
      final enabled = isEnabled(manifest.id);
      _providers[manifest.hostId] = ProviderAdapter(
        enabled: enabled,
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
  }) async {
    final provider = _providers[host];
    if (provider == null) throw HeroFailure('未找到上传器：$host');
    if (!provider.enabled) throw const HeroFailure('该插件已停用，请先在插件中心启用');
    return provider.upload(path: path, name: name, config: config);
  }

  Future<dynamic> delete(
    String host, {
    required Map<String, dynamic> deleteMap,
    required Map<String, dynamic> config,
  }) async {
    final provider = _providers[host];
    if (provider == null) throw HeroFailure('未找到上传器：$host');
    if (!provider.enabled) throw const HeroFailure('该插件已停用，无法删除云端文件');
    if (provider.delete == null) {
      throw const HeroFailure('此图床未提供云端删除接口，请关闭同步删除云端文件');
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

  PluginHttpRuntime({Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 120),
              receiveTimeout: const Duration(seconds: 60),
              validateStatus: (_) => true,
            ),
          );

  Future<dynamic> upload(
    PicoraPluginManifest manifest, {
    required String path,
    required String name,
    required Map<String, dynamic> config,
  }) async {
    final file = File(path);
    if (!await file.exists()) throw const HeroFailure('待上传文件不存在');
    final bytes = await file.readAsBytes();
    final context = _TemplateContext(
      config: config,
      filePath: path,
      fileName: name,
      fileBytes: bytes,
      upload: const {},
      resources: manifest.resources,
    );
    final response = await _execute(
      manifest,
      manifest.upload,
      context,
      includeFile: true,
    );
    final responseSpec = manifest.upload.response!;
    if (!responseSpec.successStatuses.contains(response.statusCode)) {
      final message = manifest.upload.errorMessages[response.statusCode];
      throw HeroFailure(
        message == null
            ? '${manifest.name} 上传失败（HTTP ${response.statusCode ?? '-'}）'
            : '${manifest.name}：$message',
      );
    }
    final data = _jsonValue(response.data);
    final rawUrl = _readPath(data, responseSpec.urlPath);
    if (_nonEmpty(rawUrl) == null) {
      throw HeroFailure('${manifest.name} 响应中没有找到图片链接');
    }
    final requestUri = response.requestOptions.uri;
    final url = _absoluteUrl(_nonEmpty(rawUrl)!, requestUri);
    final rawThumbnail = responseSpec.thumbnailPath == null
        ? null
        : _readPath(data, responseSpec.thumbnailPath!);
    final thumbnail = _nonEmpty(rawThumbnail) == null
        ? url
        : _absoluteUrl(_nonEmpty(rawThumbnail)!, requestUri);
    final deleteKey = responseSpec.deleteKeyPath == null
        ? null
        : _readPath(data, responseSpec.deleteKeyPath!);
    final pictureKey = jsonEncode({
      'plugin': manifest.id,
      'url': url,
      if (deleteKey != null) 'deleteKey': deleteKey,
    });
    return [
      'success',
      getFormatedUrl(url, name),
      url,
      pictureKey,
      thumbnail,
      url,
    ];
  }

  Future<dynamic> delete(
    PicoraPluginManifest manifest, {
    required Map<String, dynamic> deleteMap,
    required Map<String, dynamic> config,
  }) async {
    final encoded = deleteMap['pictureKey']?.toString() ?? '';
    Map<String, dynamic> upload = {};
    try {
      upload = Map<String, dynamic>.from(jsonDecode(encoded));
    } catch (_) {
      throw const HeroFailure('上传记录缺少插件删除信息');
    }
    final context = _TemplateContext(
      config: config,
      filePath: deleteMap['path']?.toString() ?? '',
      fileName: deleteMap['name']?.toString() ?? '',
      fileBytes: const [],
      upload: upload,
      resources: manifest.resources,
    );
    final response = await _execute(
      manifest,
      manifest.delete!,
      context,
      includeFile: false,
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw HeroFailure(
        '${manifest.name} 删除失败（HTTP ${response.statusCode ?? '-'}）',
      );
    }
    return ['success'];
  }

  Future<Response<Object?>> _execute(
    PicoraPluginManifest manifest,
    PluginRequestSpec request,
    _TemplateContext context, {
    required bool includeFile,
  }) async {
    final renderedUrl = await context.render(request.url);
    final uri = Uri.tryParse(renderedUrl.toString());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const HeroFailure('插件生成了无效的请求地址');
    }
    if (uri.scheme == 'http' && !manifest.permissions.allowInsecureHttp) {
      throw const HeroFailure('插件未获得明文 HTTP 权限');
    }
    if (!manifest.permissions.allowsHost(uri.host)) {
      throw HeroFailure('插件无权访问 ${uri.host}');
    }
    final headers = <String, dynamic>{};
    for (final entry in request.headers.entries) {
      final value = (await context.render(entry.value)).toString();
      if (value.isNotEmpty) headers[entry.key] = value;
    }
    final query = <String, dynamic>{};
    for (final entry in request.query.entries) {
      query[entry.key] = await context.render(entry.value);
    }
    final fields = <String, dynamic>{};
    for (final entry in request.body.fields.entries) {
      fields[entry.key] = await context.render(entry.value);
    }
    Object? body;
    switch (request.body.type) {
      case 'multipart':
        body = FormData.fromMap({
          ...fields,
          if (includeFile)
            request.body.fileField: MultipartFile.fromBytes(
              context.fileBytes,
              filename: context.fileName,
              contentType: DioMediaType.parse(
                lookupMimeType(context.filePath) ?? 'application/octet-stream',
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
        body = context.fileBytes;
        headers.putIfAbsent(
          'Content-Type',
          () => lookupMimeType(context.filePath) ?? 'application/octet-stream',
        );
      case 'none':
        body = null;
    }
    return dio.request<Object?>(
      uri.toString(),
      data: body,
      queryParameters: query,
      options: Options(
        method: request.method,
        headers: headers,
        followRedirects: request.followRedirects,
        sendTimeout: Duration(seconds: request.timeoutSeconds),
        receiveTimeout: Duration(seconds: request.timeoutSeconds),
      ),
    );
  }
}

class _TemplateContext {
  final Map<String, dynamic> config, upload;
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
  });

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
    if (exact != null) return _evaluate(exact.group(1)!.trim());
    return value.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (match) {
      final result = _evaluate(match.group(1)!.trim());
      return result is List<int> ? base64Encode(result) : result.toString();
    });
  }

  Object _evaluate(String expression) {
    final function = RegExp(
      r'^(base64|sha256|hmacSha256|basicAuth|normalizeBaseUrl|assetText)\((.*)\)$',
    ).firstMatch(expression);
    if (function != null) {
      final name = function.group(1)!;
      final args = function
          .group(2)!
          .split(',')
          .map((item) => _resolve(item.trim()))
          .toList();
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
        return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
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
    if (key.startsWith('config.')) {
      return _clean(config[key.substring(7)]);
    }
    if (key.startsWith('upload.')) {
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

Object? _readPath(Object? value, String path) {
  var current = value;
  final normalized = path.replaceFirst(RegExp(r'^\$\.?'), '');
  if (normalized.isEmpty) return current;
  final tokens = RegExp(r'([^.\[\]]+)|\[(\d+)\]')
      .allMatches(normalized)
      .map((match) => match.group(1) ?? match.group(2)!)
      .toList();
  for (final token in tokens) {
    if (current is Map) {
      current = current[token];
    } else if (current is List && int.tryParse(token) != null) {
      final index = int.parse(token);
      if (index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

String _absoluteUrl(String value, Uri requestUri) {
  final uri = Uri.tryParse(value);
  if (uri == null) throw const HeroFailure('插件返回了无效链接');
  final resolved = uri.hasScheme ? uri : requestUri.resolveUri(uri);
  if (!['http', 'https'].contains(resolved.scheme) || resolved.host.isEmpty) {
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
