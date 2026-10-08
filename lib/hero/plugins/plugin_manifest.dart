import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../diagnostics.dart';
import '../models.dart';

class PluginPermissions {
  final List<String> networkHosts;
  final bool readSelectedFile, allowInsecureHttp;

  const PluginPermissions({
    required this.networkHosts,
    required this.readSelectedFile,
    required this.allowInsecureHttp,
  });

  factory PluginPermissions.fromJson(Object? value) {
    if (value is! Map) {
      throw const HeroFailure('插件缺少 permissions 对象');
    }
    final hosts =
        (value['network'] as List?)
            ?.map((item) => item.toString().trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];
    if (hosts.isEmpty) {
      throw const HeroFailure('插件必须声明允许访问的网络主机');
    }
    for (final host in hosts) {
      if (host != '*' && !RegExp(r'^(\*\.)?[a-z0-9.-]+$').hasMatch(host)) {
        throw HeroFailure('无效的网络主机权限：$host');
      }
    }
    if (value['readSelectedFile'] != true) {
      throw const HeroFailure('上传插件必须声明 readSelectedFile 权限');
    }
    return PluginPermissions(
      networkHosts: hosts,
      readSelectedFile: true,
      allowInsecureHttp: value['allowInsecureHttp'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'network': networkHosts,
    'readSelectedFile': readSelectedFile,
    'allowInsecureHttp': allowInsecureHttp,
  };

  bool allowsHost(String host) {
    final normalized = host.toLowerCase();
    return networkHosts.any(
      (allowed) =>
          allowed == '*' ||
          allowed == normalized ||
          (allowed.startsWith('*.') &&
              normalized.endsWith(allowed.substring(1)) &&
              normalized != allowed.substring(2)),
    );
  }
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

class PluginResponseSpec {
  final String urlPath;
  final String? thumbnailPath, deleteKeyPath;
  final List<int> successStatuses;

  const PluginResponseSpec({
    required this.urlPath,
    required this.thumbnailPath,
    required this.deleteKeyPath,
    required this.successStatuses,
  });

  factory PluginResponseSpec.fromJson(Object? value) {
    if (value is! Map || value['url']?.toString().trim().isNotEmpty != true) {
      throw const HeroFailure('插件必须声明 response.url 响应路径');
    }
    final statuses =
        (value['successStatuses'] as List?)
            ?.map((item) => int.tryParse(item.toString()))
            .whereType<int>()
            .toList() ??
        const [200, 201];
    if (statuses.isEmpty ||
        statuses.any((status) => status < 100 || status > 599)) {
      throw const HeroFailure('插件 successStatuses 无效');
    }
    return PluginResponseSpec(
      urlPath: value['url'].toString().trim(),
      thumbnailPath: _optionalString(value['thumbnail']),
      deleteKeyPath: _optionalString(value['deleteKey']),
      successStatuses: statuses,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': urlPath,
    if (thumbnailPath != null) 'thumbnail': thumbnailPath,
    if (deleteKeyPath != null) 'deleteKey': deleteKeyPath,
    'successStatuses': successStatuses,
  };
}

class PluginRequestSpec {
  final String method, url;
  final Map<String, dynamic> headers, query;
  final Map<int, String> errorMessages;
  final PluginBodySpec body;
  final PluginResponseSpec? response;
  final bool followRedirects;
  final int timeoutSeconds;

  const PluginRequestSpec({
    required this.method,
    required this.url,
    required this.headers,
    required this.query,
    required this.errorMessages,
    required this.body,
    required this.response,
    required this.followRedirects,
    required this.timeoutSeconds,
  });

  factory PluginRequestSpec.fromJson(Object? value, {required bool upload}) {
    if (value is! Map) throw const HeroFailure('插件请求定义必须是对象');
    final method = (value['method']?.toString() ?? 'POST').toUpperCase();
    if (!['POST', 'PUT', 'PATCH', 'DELETE'].contains(method)) {
      throw HeroFailure('不支持的插件请求方法：$method');
    }
    final url = value['url']?.toString().trim() ?? '';
    if (url.isEmpty) throw const HeroFailure('插件请求缺少 URL');
    final headers = value['headers'];
    final query = value['query'];
    final errors = value['errors'];
    if (headers != null && headers is! Map) {
      throw const HeroFailure('插件请求 headers 必须是对象');
    }
    if (query != null && query is! Map) {
      throw const HeroFailure('插件请求 query 必须是对象');
    }
    if (errors != null && errors is! Map) {
      throw const HeroFailure('插件请求 errors 必须是对象');
    }
    final normalizedHeaders = headers == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(headers);
    for (final key in normalizedHeaders.keys) {
      if (['host', 'content-length'].contains(key.toLowerCase())) {
        throw HeroFailure('插件不能设置 $key 请求头');
      }
    }
    final timeoutSeconds =
        int.tryParse(value['timeoutSeconds']?.toString() ?? '60') ?? 60;
    if (timeoutSeconds < 5 || timeoutSeconds > 300) {
      throw const HeroFailure('插件请求 timeoutSeconds 必须在 5–300 秒之间');
    }
    final errorMessages = <int, String>{};
    if (errors is Map) {
      for (final entry in errors.entries) {
        final status = int.tryParse(entry.key.toString());
        final message = entry.value?.toString().trim() ?? '';
        if (status == null || status < 100 || status > 599 || message.isEmpty) {
          throw const HeroFailure('插件请求 errors 包含无效状态码或提示');
        }
        errorMessages[status] = message;
      }
    }
    return PluginRequestSpec(
      method: method,
      url: url,
      headers: normalizedHeaders,
      query: query == null ? const {} : Map<String, dynamic>.from(query),
      errorMessages: errorMessages,
      body: PluginBodySpec.fromJson(value['body'], upload: upload),
      response: upload ? PluginResponseSpec.fromJson(value['response']) : null,
      followRedirects: value['followRedirects'] != false,
      timeoutSeconds: timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'method': method,
    'url': url,
    if (headers.isNotEmpty) 'headers': headers,
    if (query.isNotEmpty) 'query': query,
    if (!followRedirects) 'followRedirects': false,
    if (timeoutSeconds != 60) 'timeoutSeconds': timeoutSeconds,
    if (errorMessages.isNotEmpty)
      'errors': errorMessages.map((key, value) => MapEntry('$key', value)),
    if (body.type != 'none') 'body': body.toJson(),
    if (response != null) 'response': response!.toJson(),
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
    if (json['schemaVersion'] != 1) {
      throw const HeroFailure('仅支持 schemaVersion 1 的 Picora 插件');
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
    final permissions = PluginPermissions.fromJson(json['permissions']);
    return PicoraPluginManifest(
      schemaVersion: 1,
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
      upload: PluginRequestSpec.fromJson(json['upload'], upload: true),
      delete: json['delete'] == null
          ? null
          : PluginRequestSpec.fromJson(json['delete'], upload: false),
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
    'permissions': permissions.toJson(),
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
