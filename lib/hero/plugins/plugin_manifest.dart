import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../diagnostics.dart';
import '../models.dart';
import 'plugin_protocol.dart';

class PluginPermissions {
  final List<String> networkHosts;
  final bool readSelectedFile, allowInsecureHttp, deleteUploadedFile;
  const PluginPermissions({
    required this.networkHosts,
    required this.readSelectedFile,
    required this.allowInsecureHttp,
    this.deleteUploadedFile = false,
  });
  factory PluginPermissions.fromJson(
    Object? value, {
    int schemaVersion = 1,
    bool hasDelete = false,
  }) {
    if (value is! Map) throw const HeroFailure('缺少 permissions');
    pluginKeys(value, {
      'network',
      'readSelectedFile',
      'allowInsecureHttp',
      if (schemaVersion == 2) 'deleteUploadedFile',
    }, 'permissions');
    final hosts = value['network'];
    if (hosts is! List ||
        hosts.isEmpty ||
        hosts.length > 16 ||
        hosts.any((h) => h is! String)) {
      throw const HeroFailure('network 需要 1–16 个主机');
    }
    for (final flag in [
      'readSelectedFile',
      'allowInsecureHttp',
      'deleteUploadedFile',
    ]) {
      if (value.containsKey(flag) && value[flag] is! bool) {
        throw HeroFailure('$flag 必须是布尔值');
      }
    }
    final result = hosts
        .cast<String>()
        .map(
          (s) => schemaVersion == 2 && s.startsWith('config.')
              ? s
              : s.toLowerCase(),
        )
        .toList();
    for (final host in result) {
      final configured =
          schemaVersion == 2 &&
          RegExp(r'^config\.[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(host);
      if (schemaVersion == 2 && (host == '*' || host.startsWith('*.')) ||
          !configured &&
              host != '*' &&
              !RegExp(r'^(\*\.)?[a-z0-9.-]+$').hasMatch(host)) {
        throw const HeroFailure('网络主机权限无效，v2 不支持通配主机');
      }
    }
    if (value['readSelectedFile'] != true) {
      throw const HeroFailure('上传插件需要 readSelectedFile');
    }
    return PluginPermissions(
      networkHosts: result,
      readSelectedFile: true,
      allowInsecureHttp: value['allowInsecureHttp'] == true,
      deleteUploadedFile: schemaVersion == 1
          ? hasDelete
          : value['deleteUploadedFile'] == true,
    );
  }
  Map<String, dynamic> toJson() => {
    'network': networkHosts,
    'readSelectedFile': readSelectedFile,
    'allowInsecureHttp': allowInsecureHttp,
    if (deleteUploadedFile) 'deleteUploadedFile': true,
  };
  bool allowsHost(String host) => networkHosts.any(
    (h) =>
        h == '*' ||
        h == host.toLowerCase() ||
        h.startsWith('*.') && host.toLowerCase().endsWith(h.substring(1)),
  );
}

class PluginBodySpec {
  final String type, fileField;
  final Map<String, dynamic> fields;

  const PluginBodySpec({
    required this.type,
    required this.fileField,
    required this.fields,
  });

  factory PluginBodySpec.fromJson(Object? value, {required bool upload}) {
    if (value == null && !upload) {
      return const PluginBodySpec(type: 'none', fileField: 'file', fields: {});
    }
    if (value is! Map) throw const HeroFailure('插件请求 body 必须是对象');
    pluginKeys(value, {'type', 'fileField', 'fields'}, 'body');
    final type = value['type']?.toString() ?? 'multipart';
    if (!['multipart', 'json', 'form', 'binary', 'none'].contains(type)) {
      throw HeroFailure('不支持的插件请求体类型：$type');
    }
    final fields = value['fields'];
    if (fields != null && fields is! Map) {
      throw const HeroFailure('插件请求 body.fields 必须是对象');
    }
    return PluginBodySpec(
      type: type,
      fileField: value['fileField']?.toString().trim().isNotEmpty == true
          ? value['fileField'].toString().trim()
          : 'file',
      fields: fields == null ? const {} : Map<String, dynamic>.from(fields),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (type == 'multipart') 'fileField': fileField,
    if (fields.isNotEmpty) 'fields': fields,
  };
}

class PluginResponseSpec extends PluginResponseRules {
  final String urlPath;
  final String? thumbnailPath, deleteKeyPath, deleteUrlPath;
  const PluginResponseSpec({
    required this.urlPath,
    required this.thumbnailPath,
    required this.deleteKeyPath,
    this.deleteUrlPath,
    required super.successStatuses,
    super.success,
    super.errorMessagePath,
    super.errorCodePath,
  });
  factory PluginResponseSpec.fromJson(Object? value, {int schemaVersion = 1}) {
    final rules = PluginResponseRules.fromJson(
      value,
      upload: true,
      schemaVersion: schemaVersion,
    );
    final json = value as Map;
    String? path(String key, {bool required = false}) {
      final v = json[key];
      if (v == null && !required) return null;
      if (v is! String || !validPluginPath(v)) {
        throw HeroFailure('response.$key 路径无效');
      }
      return v;
    }

    return PluginResponseSpec(
      urlPath: path('url', required: true)!,
      thumbnailPath: path('thumbnail'),
      deleteKeyPath: path('deleteKey'),
      deleteUrlPath: path('deleteUrl'),
      successStatuses: rules.successStatuses,
      success: rules.success,
      errorMessagePath: rules.errorMessagePath,
      errorCodePath: rules.errorCodePath,
    );
  }
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'url': urlPath,
    if (thumbnailPath != null) 'thumbnail': thumbnailPath,
    if (deleteKeyPath != null) 'deleteKey': deleteKeyPath,
    if (deleteUrlPath != null) 'deleteUrl': deleteUrlPath,
  };
}

class PluginPrepareSpec {
  final String id;
  final PluginRequestSpec request;
  final PluginCacheSpec? cache;
  const PluginPrepareSpec(this.id, this.request, this.cache);
  factory PluginPrepareSpec.fromJson(Object? value) {
    if (value is! Map) throw const HeroFailure('prepare 步骤必须是对象');
    final id = value['id'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(id)) {
      throw const HeroFailure('prepare.id 无效');
    }
    final request = PluginRequestSpec.fromJson(
      Map<String, dynamic>.from(value)
        ..remove('id')
        ..remove('cache'),
      upload: false,
      prepare: true,
      schemaVersion: 2,
    );
    if (request.responseRules.exports.isEmpty) {
      throw const HeroFailure('前置请求必须明确导出变量');
    }
    if (request.refreshCredentials != null) {
      throw const HeroFailure('前置请求不能触发上传重试');
    }
    return PluginPrepareSpec(
      id,
      request,
      value['cache'] == null ? null : PluginCacheSpec.fromJson(value['cache']),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    ...request.toJson(),
    if (cache != null) 'cache': cache!.toJson(),
  };
}

class PluginRequestSpec {
  final String method, url;
  final Map<String, dynamic> headers, query;
  final Map<int, String> errorMessages;
  final PluginBodySpec body;
  final PluginResponseSpec? response;
  final PluginResponseRules responseRules;
  final PluginCredentialRefresh? refreshCredentials;
  final bool followRedirects;
  final int timeoutSeconds, maxRedirects;
  const PluginRequestSpec({
    required this.method,
    required this.url,
    required this.headers,
    required this.query,
    required this.errorMessages,
    required this.body,
    required this.response,
    required this.responseRules,
    required this.followRedirects,
    required this.timeoutSeconds,
    this.maxRedirects = 5,
    this.refreshCredentials,
  });
  factory PluginRequestSpec.fromJson(
    Object? value, {
    required bool upload,
    bool prepare = false,
    int schemaVersion = 1,
  }) {
    if (value is! Map) throw const HeroFailure('请求必须是对象');
    pluginKeys(value, {
      'method',
      'url',
      'headers',
      'query',
      'errors',
      'body',
      'response',
      'followRedirects',
      'timeoutSeconds',
      if (schemaVersion == 2) ...['maxRedirects', 'refreshCredentials'],
    }, '请求');
    final method = (value['method']?.toString() ?? (prepare ? 'GET' : 'POST'))
        .toUpperCase();
    final methods = prepare
        ? ['GET', 'HEAD', 'POST']
        : upload
        ? ['POST', 'PUT', 'PATCH']
        : ['POST', 'DELETE', 'GET'];
    if (!methods.contains(method)) throw const HeroFailure('请求方法不受支持');
    final url = value['url'];
    if (url is! String || url.isEmpty || url.length > 16384) {
      throw const HeroFailure('请求 URL 无效');
    }
    Map<String, dynamic> object(String key) {
      if (value[key] == null) return {};
      if (value[key] is! Map || (value[key] as Map).length > 64) {
        throw HeroFailure('$key 必须是对象，最多 64 项');
      }
      return Map<String, dynamic>.from(value[key]);
    }

    final headers = object('headers'),
        query = object('query'),
        errors = object('errors');
    for (final key in headers.keys) {
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{0,63}$').hasMatch(key) ||
          {
            'host',
            'content-length',
            'proxy-authorization',
            'proxy-connection',
            'connection',
            'transfer-encoding',
            'upgrade',
          }.contains(key.toLowerCase())) {
        throw HeroFailure('插件不能设置 $key 请求头');
      }
    }
    final timeout = value['timeoutSeconds'] ?? 60,
        max = value['maxRedirects'] ?? 5;
    if (timeout is! int ||
        timeout < 5 ||
        timeout > 300 ||
        max is! int ||
        max < 0 ||
        max > 5) {
      throw const HeroFailure('请求超时或重定向次数无效');
    }
    if (value.containsKey('followRedirects') &&
        value['followRedirects'] is! bool) {
      throw const HeroFailure('followRedirects 必须是布尔值');
    }
    final body = PluginBodySpec.fromJson(value['body'], upload: upload);
    if (!upload && ['multipart', 'binary'].contains(body.type)) {
      throw const HeroFailure('前置和删除操作不能发送文件');
    }
    if (['GET', 'HEAD'].contains(method) && body.type != 'none') {
      throw const HeroFailure('GET/HEAD 不能带请求体');
    }
    if (body.type == 'multipart' && body.fields.containsKey(body.fileField)) {
      throw const HeroFailure('不能覆盖文件字段');
    }
    final response = upload
        ? PluginResponseSpec.fromJson(
            value['response'],
            schemaVersion: schemaVersion,
          )
        : null;
    final rules =
        response ??
        PluginResponseRules.fromJson(
          value['response'],
          upload: false,
          schemaVersion: schemaVersion,
        );
    if (!prepare && rules.exports.isNotEmpty) {
      throw const HeroFailure('导出字段仅用于前置请求');
    }
    final errorMessages = <int, String>{};
    for (final entry in errors.entries) {
      final status = int.tryParse(entry.key);
      if (status == null ||
          status < 100 ||
          status > 599 ||
          entry.value is! String ||
          (entry.value as String).isEmpty) {
        throw const HeroFailure('errors 状态码或提示无效');
      }
      errorMessages[status] = entry.value as String;
    }
    return PluginRequestSpec(
      method: method,
      url: url,
      headers: headers,
      query: query,
      errorMessages: errorMessages,
      body: body,
      response: response,
      responseRules: rules,
      followRedirects: value['followRedirects'] == true,
      timeoutSeconds: timeout,
      maxRedirects: max,
      refreshCredentials: value['refreshCredentials'] == null
          ? null
          : PluginCredentialRefresh.fromJson(value['refreshCredentials']),
    );
  }
  Map<String, dynamic> toJson() => {
    'method': method,
    'url': url,
    if (headers.isNotEmpty) 'headers': headers,
    if (query.isNotEmpty) 'query': query,
    'followRedirects': followRedirects,
    if (timeoutSeconds != 60) 'timeoutSeconds': timeoutSeconds,
    if (maxRedirects != 5) 'maxRedirects': maxRedirects,
    if (errorMessages.isNotEmpty)
      'errors': errorMessages.map((k, v) => MapEntry('$k', v)),
    if (body.type != 'none') 'body': body.toJson(),
    'response': responseRules.toJson(),
    if (refreshCredentials != null)
      'refreshCredentials': refreshCredentials!.toJson(),
  };
}

class PicoraPluginManifest {
  final int schemaVersion;
  final String id, name, version, description, author;
  final String? homepage;
  final String mark;
  final Color color;
  final PluginPermissions permissions;
  final List<HostField> fields;
  final PluginRequestSpec upload;
  final PluginRequestSpec? delete;
  final List<PluginPrepareSpec> prepare;
  final List<String> requires;
  final Map<String, Uint8List> resources;

  const PicoraPluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.homepage,
    required this.mark,
    required this.color,
    required this.permissions,
    required this.fields,
    required this.upload,
    required this.delete,
    this.resources = const {},
    this.prepare = const [],
    this.requires = const [],
  });

  String get hostId => 'plugin.$id';

  factory PicoraPluginManifest.parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw HeroFailure('插件 JSON 无效：${error.message}');
    }
    if (decoded is! Map) throw const HeroFailure('插件清单必须是 JSON 对象');
    return PicoraPluginManifest.fromJson(Map<String, dynamic>.from(decoded));
  }

  factory PicoraPluginManifest.fromJson(
    Map<String, dynamic> json, {
    Map<String, Uint8List> resources = const {},
  }) {
    validatePluginProgram(json);
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int || !{1, 2}.contains(schemaVersion)) {
      throw const HeroFailure('仅支持 schemaVersion 1 / 2');
    }
    pluginKeys(json, {
      'schemaVersion',
      'id',
      'name',
      'version',
      'description',
      'author',
      'homepage',
      'mark',
      'color',
      'permissions',
      'config',
      'upload',
      'delete',
      if (schemaVersion == 2) ...['prepare', 'requires'],
    }, '程序');
    final requires = json['requires'] ?? <String>[];
    if (requires is! List ||
        requires.any(
          (r) => r is! String || !pluginV2Capabilities.contains(r),
        )) {
      throw const HeroFailure('插件要求的能力不受当前客户端支持');
    }
    final id = json['id']?.toString().trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$').hasMatch(id) ||
        id.length > 80) {
      throw const HeroFailure('插件 ID 应使用反向域名格式，例如 com.example.host');
    }
    final name = _requiredString(json, 'name', max: 60);
    final version = _requiredString(json, 'version', max: 30);
    final description = _requiredString(json, 'description', max: 160);
    final author = _requiredString(json, 'author', max: 80);
    final homepage = _optionalString(json['homepage']);
    if (homepage != null) {
      final uri = Uri.tryParse(homepage);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const HeroFailure('插件 homepage 必须是 HTTP 或 HTTPS 地址');
      }
    }
    final rawFields = json['config'];
    if (rawFields is! List) throw const HeroFailure('插件 config 必须是字段数组');
    final fields = <HostField>[];
    final keys = <String>{};
    for (final item in rawFields) {
      if (item is! Map) throw const HeroFailure('插件配置字段必须是对象');
      pluginKeys(item, {
        'key',
        'label',
        'type',
        'hint',
        'required',
        'default',
        'options',
      }, '配置字段');
      if (item.containsKey('required') && item['required'] is! bool) {
        throw const HeroFailure('配置字段 required 必须是布尔值');
      }
      final key = item['key']?.toString().trim() ?? '';
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(key) ||
          !keys.add(key)) {
        throw HeroFailure('插件配置字段键无效或重复：$key');
      }
      final type = item['type']?.toString() ?? 'text';
      if (!['text', 'secret', 'toggle', 'select'].contains(type)) {
        throw HeroFailure('插件字段 $key 使用了不支持的类型：$type');
      }
      final options = (item['options'] as List?)
          ?.map((option) => option.toString())
          .toList();
      if (type == 'select' && (options == null || options.isEmpty)) {
        throw HeroFailure('插件字段 $key 的 select 缺少 options');
      }
      Object? defaultValue = item['default'];
      if (type == 'toggle') defaultValue = defaultValue == true;
      fields.add(
        HostField(
          key,
          _requiredString(Map<String, dynamic>.from(item), 'label', max: 50),
          hint: item['hint']?.toString() ?? '',
          required: item['required'] == true,
          secret: type == 'secret',
          defaultValue: defaultValue,
          choices: type == 'select' ? options : null,
        ),
      );
    }
    if (fields.length > 30) throw const HeroFailure('插件配置字段不能超过 30 个');
    final mark = (json['mark']?.toString().trim().toUpperCase() ?? 'P');
    if (mark.isEmpty || mark.length > 3) {
      throw const HeroFailure('插件 mark 需要 1–3 个字符');
    }
    final permissions = PluginPermissions.fromJson(
      json['permissions'],
      schemaVersion: schemaVersion,
      hasDelete: json['delete'] != null,
    );
    for (final permission in permissions.networkHosts.where(
      (h) => h.startsWith('config.'),
    )) {
      final field = fields.where((f) => f.key == permission.substring(7));
      if (field.isEmpty || field.single.secret) {
        throw const HeroFailure('网络端点必须引用当前配置的非密码字段');
      }
    }
    final rawPrepare = json['prepare'] ?? [];
    if (rawPrepare is! List || rawPrepare.length > 4) {
      throw const HeroFailure('最多 4 个前置请求');
    }
    final prepare = rawPrepare.map(PluginPrepareSpec.fromJson).toList();
    final available = <String, Set<String>>{};
    for (final step in prepare) {
      if (available.containsKey(step.id)) throw const HeroFailure('前置请求 ID 重复');
      _validatePluginTemplates(
        step.request.toJson(),
        keys,
        available,
        resources,
        operation: 'prepare',
        schemaVersion: schemaVersion,
      );
      available[step.id] = step.request.responseRules.exports.keys.toSet();
    }
    final upload = PluginRequestSpec.fromJson(
      json['upload'],
      upload: true,
      schemaVersion: schemaVersion,
    );
    _validatePluginTemplates(
      upload.toJson(),
      keys,
      available,
      resources,
      operation: 'upload',
      schemaVersion: schemaVersion,
    );
    if (upload.refreshCredentials != null &&
        upload.refreshCredentials!.steps.any(
          (id) => !prepare.any((step) => step.id == id && step.cache != null),
        )) {
      throw const HeroFailure('刷新必须引用有缓存的前置请求');
    }
    final delete = json['delete'] == null
        ? null
        : PluginRequestSpec.fromJson(
            json['delete'],
            upload: false,
            schemaVersion: schemaVersion,
          );
    if (delete != null) {
      if (!permissions.deleteUploadedFile) {
        throw const HeroFailure('需要显式 deleteUploadedFile 权限');
      }
      if (delete.refreshCredentials != null) {
        throw const HeroFailure('删除操作不能自动重试');
      }
      _validatePluginTemplates(
        delete.toJson(),
        keys,
        const {},
        resources,
        operation: 'delete',
        schemaVersion: schemaVersion,
      );
      if (schemaVersion == 2 && !_hasDeleteReference(delete.toJson())) {
        throw const HeroFailure('删除必须使用单张图片的删除凭证或链接');
      }
    }
    return PicoraPluginManifest(
      schemaVersion: schemaVersion,
      resources: resources,
      id: id,
      name: name,
      version: version,
      description: description,
      author: author,
      homepage: homepage,
      mark: mark,
      color: _parseColor(json['color']?.toString()),
      permissions: permissions,
      fields: fields,
      upload: upload,
      delete: delete,
      prepare: prepare,
      requires: requires.cast<String>(),
    );
  }

  HostSpec toHostSpec({Uint8List? iconBytes, String? iconFormat}) => HostSpec(
    hostId,
    name,
    '$description · 插件',
    mark,
    color,
    fields,
    iconBytes: iconBytes,
    iconFormat: iconFormat,
    pluginId: id,
    pluginVersion: version,
    permissionSummary: [
      '读取待上传文件',
      '访问 ${permissions.networkHosts.join('、')}',
      if (permissions.allowInsecureHttp) '允许明文 HTTP',
      if (delete != null) '删除选中的单张云端图片（默认关闭）',
    ],
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'author': author,
    if (homepage != null) 'homepage': homepage,
    'mark': mark,
    'color':
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
    'permissions': permissions.toJson()
      ..removeWhere(
        (key, _) => schemaVersion == 1 && key == 'deleteUploadedFile',
      ),
    'config': fields
        .map(
          (field) => {
            'key': field.key,
            'label': field.label,
            'type': field.isToggle
                ? 'toggle'
                : field.choices != null
                ? 'select'
                : field.secret
                ? 'secret'
                : 'text',
            if (field.hint.isNotEmpty) 'hint': field.hint,
            if (field.required) 'required': true,
            if (field.defaultValue != null) 'default': field.defaultValue,
            if (field.choices != null) 'options': field.choices,
          },
        )
        .toList(),
    if (prepare.isNotEmpty)
      'prepare': prepare.map((step) => step.toJson()).toList(),
    if (requires.isNotEmpty) 'requires': requires,
    'upload': upload.toJson(),
    if (delete != null) 'delete': delete!.toJson(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  required int max,
}) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty || value.length > max) {
    throw HeroFailure('插件 $key 不能为空且不能超过 $max 个字符');
  }
  return value;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

Color _parseColor(String? value) {
  final text = value?.trim() ?? '#6377E8';
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
    throw const HeroFailure('插件 color 必须使用 #RRGGBB 格式');
  }
  return Color(0xFF000000 | int.parse(text.substring(1), radix: 16));
}

void _validatePluginTemplates(
  Object? node,
  Set<String> keys,
  Map<String, Set<String>> available,
  Map<String, Uint8List> resources, {
  required String operation,
  required int schemaVersion,
}) {
  if (node is Map) {
    for (final value in node.values) {
      _validatePluginTemplates(
        value,
        keys,
        available,
        resources,
        operation: operation,
        schemaVersion: schemaVersion,
      );
    }
  } else if (node is List) {
    for (final value in node) {
      _validatePluginTemplates(
        value,
        keys,
        available,
        resources,
        operation: operation,
        schemaVersion: schemaVersion,
      );
    }
  } else if (node is String) {
    final expressions = RegExp(r'\$\{([^}]+)\}').allMatches(node);
    if (node.replaceAll(RegExp(r'\$\{([^}]+)\}'), '').contains(r'${')) {
      throw const HeroFailure('模板变量没有闭合');
    }
    for (final match in expressions) {
      final text = match.group(1)!.trim();
      final function = RegExp(
        r'^(base64|sha256|hmacSha256|basicAuth|normalizeBaseUrl|assetText|urlEncode)\((.*)\)$',
      ).firstMatch(text);
      for (final ref
          in function == null
              ? [text]
              : function.group(2)!.split(',').map((s) => s.trim())) {
        final parts = ref.split('.');
        final valid =
            ref == 'uuid' ||
            {'time.millis', 'time.unix'}.contains(ref) ||
            ref.startsWith('config.') &&
                keys.contains(ref.substring(7)) &&
                !(schemaVersion == 2 && operation == 'delete') ||
            parts.length == 3 &&
                parts[0] == 'steps' &&
                (available[parts[1]]?.contains(parts[2]) ?? false) &&
                operation != 'delete' ||
            ref.startsWith('file.') &&
                operation == 'upload' &&
                {
                  'file.name',
                  'file.mime',
                  'file.bytes',
                  'file.base64',
                  if (schemaVersion == 1) 'file.path',
                }.contains(ref) ||
            ref.startsWith('upload.') &&
                operation == 'delete' &&
                {
                  'upload.url',
                  'upload.deleteKey',
                  'upload.deleteUrl',
                }.contains(ref) ||
            ref.startsWith('assets/') &&
                resources.containsKey(ref) &&
                !(schemaVersion == 2 && operation == 'delete');
        if (!valid) throw const HeroFailure('模板引用了未声明或越权的变量');
      }
    }
  }
}

bool _hasDeleteReference(Object? value) {
  if (value is Map) return value.values.any(_hasDeleteReference);
  if (value is List) return value.any(_hasDeleteReference);
  if (value is! String) return false;
  return RegExp(r'\$\{([^}]+)\}')
      .allMatches(value)
      .any(
        (m) =>
            RegExp(r'\bupload\.(deleteKey|deleteUrl)\b').hasMatch(m.group(1)!),
      );
}
