import '../diagnostics.dart';

const pluginRuntimes = {'http-v1': 1, 'http-v2': 2};
const pluginV2Capabilities = {
  'prepare',
  'credential-cache',
  'response-conditions',
  'credential-refresh',
  'safe-redirects',
  'scoped-delete',
};
void pluginKeys(Map value, Set<String> allowed, String where) {
  for (final key in value.keys) {
    if (key is! String || !allowed.contains(key)) {
      throw HeroFailure('$where 包含未知字段；需要受支持的协议版本');
    }
  }
}

bool validPluginPath(String path) =>
    path.length <= 120 &&
    (path == r'$' ||
        RegExp(
          r'^(?:\$\.)?(?:[A-Za-z_][A-Za-z0-9_-]*|\[\d+\])(?:\.[A-Za-z_][A-Za-z0-9_-]*|\[\d+\])*$',
        ).hasMatch(path));
Object? readPluginPath(Object? value, String path) {
  if (!validPluginPath(path)) return null;
  var current = value;
  final normalized = path.replaceFirst(RegExp(r'^\$\.?'), '');
  if (normalized.isEmpty) return current;
  for (final token in RegExp(
    r'([A-Za-z_][A-Za-z0-9_-]*)|\[(\d+)\]',
  ).allMatches(normalized)) {
    if (token.group(1) != null && current is Map) {
      current = current[token.group(1)];
    } else if (token.group(2) != null && current is List) {
      final i = int.parse(token.group(2)!);
      current = i < current.length ? current[i] : null;
    } else {
      return null;
    }
  }
  return current;
}

class PluginCondition {
  final String path;
  final Object? equals;
  final bool hasEquals;
  final bool? exists;
  final List<String>? containsAny;
  const PluginCondition(
    this.path,
    this.equals,
    this.hasEquals,
    this.exists, [
    this.containsAny,
  ]);
  factory PluginCondition.fromJson(Object? value) {
    if (value is! Map) throw const HeroFailure('响应条件必须是对象');
    pluginKeys(value, {'path', 'equals', 'exists', 'containsAny'}, '响应条件');
    final path = value['path'];
    if (path is! String || !validPluginPath(path)) {
      throw const HeroFailure('响应条件 path 无效');
    }
    if (['equals', 'exists', 'containsAny'].where(value.containsKey).length !=
        1) {
      throw const HeroFailure('响应条件必须选择 equals、exists 或 containsAny');
    }
    final hasEquals = value.containsKey('equals');
    if (hasEquals &&
        value['equals'] is! String &&
        value['equals'] is! num &&
        value['equals'] is! bool &&
        value['equals'] != null) {
      throw const HeroFailure('equals 必须是标量');
    }
    if (value.containsKey('exists') && value['exists'] is! bool) {
      throw const HeroFailure('exists 必须是布尔值');
    }
    final words = value['containsAny'];
    if (value.containsKey('containsAny') &&
        (words is! List ||
            words.isEmpty ||
            words.length > 8 ||
            words.any((s) => s is! String || s.length < 2 || s.length > 80))) {
      throw const HeroFailure('containsAny 需要 1–8 个长度为 2–80 的关键词');
    }
    return PluginCondition(
      path,
      value['equals'],
      hasEquals,
      value['exists'] as bool?,
      (words as List?)?.cast<String>(),
    );
  }
  bool matches(Object? data) {
    final value = readPluginPath(data, path);
    if (containsAny != null) {
      return value is String &&
          containsAny!.any(
            (word) => value.toLowerCase().contains(word.toLowerCase()),
          );
    }
    return hasEquals ? value == equals : (value != null) == exists;
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    if (hasEquals) 'equals': equals,
    if (exists != null) 'exists': exists,
    if (containsAny != null) 'containsAny': containsAny,
  };
}

class PluginExportSpec {
  final String path, type, source;
  final bool required, secret;
  const PluginExportSpec(
    this.path,
    this.type,
    this.source,
    this.required,
    this.secret,
  );
  factory PluginExportSpec.fromJson(Object? value) {
    if (value is! Map) throw const HeroFailure('响应导出字段必须是对象');
    pluginKeys(value, {'path', 'type', 'source', 'required', 'secret'}, '导出');
    final path = value['path'],
        type = value['type'] ?? 'string',
        source = value['source'] ?? 'json';
    if (path is! String ||
        path.isEmpty ||
        path.length > 120 ||
        !{'string', 'number', 'boolean'}.contains(type) ||
        !{'json', 'header'}.contains(source) ||
        source == 'json' && !validPluginPath(path) ||
        source == 'header' && !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(path)) {
      throw const HeroFailure('响应导出 path/type/source 无效');
    }
    for (final flag in ['required', 'secret']) {
      if (value.containsKey(flag) && value[flag] is! bool) {
        throw HeroFailure('$flag 必须是布尔值');
      }
    }
    return PluginExportSpec(
      path,
      type as String,
      source as String,
      value['required'] != false,
      value['secret'] != false,
    );
  }
  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type,
    'source': source,
    'required': required,
    'secret': secret,
  };
}

class PluginResponseRules {
  final List<int> successStatuses;
  final PluginCondition? success;
  final String? errorMessagePath, errorCodePath;
  final Map<String, PluginExportSpec> exports;
  const PluginResponseRules({
    required this.successStatuses,
    this.success,
    this.errorMessagePath,
    this.errorCodePath,
    this.exports = const {},
  });
  factory PluginResponseRules.fromJson(
    Object? input, {
    required bool upload,
    int schemaVersion = 1,
  }) {
    final value = input ?? (upload ? null : <String, dynamic>{});
    if (value is! Map) throw const HeroFailure('response 必须是对象');
    pluginKeys(value, {
      'successStatuses',
      if (upload) ...['url', 'thumbnail', 'deleteKey'],
      if (upload && schemaVersion == 2) 'deleteUrl',
      if (schemaVersion == 2) ...[
        'success',
        'errorMessage',
        'errorCode',
        'exports',
      ],
    }, 'response');
    final statuses =
        value['successStatuses'] ??
        (upload ? [200, 201] : List.generate(100, (i) => 200 + i));
    if (statuses is! List ||
        statuses.isEmpty ||
        statuses.length > 100 ||
        statuses.any((s) => s is! int || s < 200 || s > 299)) {
      throw const HeroFailure('successStatuses 必须是 2xx 数组');
    }
    String? path(String key) {
      final result = value[key];
      if (result == null) return null;
      if (result is! String || !validPluginPath(result)) {
        throw HeroFailure('response.$key 路径无效');
      }
      return result;
    }

    final exports = <String, PluginExportSpec>{};
    final definitions = value['exports'];
    if (definitions != null) {
      if (definitions is! Map || definitions.length > 16) {
        throw const HeroFailure('最多导出 16 个字段');
      }
      for (final entry in definitions.entries) {
        if (entry.key is! String ||
            !RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(entry.key)) {
          throw const HeroFailure('导出变量名无效');
        }
        exports[entry.key] = PluginExportSpec.fromJson(entry.value);
      }
    }
    if (upload && exports.isNotEmpty) throw const HeroFailure('导出字段仅用于前置请求');
    return PluginResponseRules(
      successStatuses: statuses.cast<int>(),
      success: value['success'] == null
          ? null
          : PluginCondition.fromJson(value['success']),
      errorMessagePath: path('errorMessage'),
      errorCodePath: path('errorCode'),
      exports: Map.unmodifiable(exports),
    );
  }
  bool accepts(int? status, Object? data) =>
      successStatuses.contains(status) && (success?.matches(data) ?? true);
  Map<String, dynamic> toJson() => {
    'successStatuses': successStatuses,
    if (success != null) 'success': success!.toJson(),
    if (errorMessagePath != null) 'errorMessage': errorMessagePath,
    if (errorCodePath != null) 'errorCode': errorCodePath,
    if (exports.isNotEmpty)
      'exports': exports.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class PluginCacheSpec {
  final String? ttlFrom;
  final int? ttlSeconds;
  final int refreshBeforeSeconds, maxTtlSeconds;
  const PluginCacheSpec(
    this.ttlFrom,
    this.ttlSeconds,
    this.refreshBeforeSeconds,
    this.maxTtlSeconds,
  );
  factory PluginCacheSpec.fromJson(Object? value) {
    if (value is! Map) throw const HeroFailure('cache 必须是对象');
    pluginKeys(value, {
      'scope',
      'ttlFrom',
      'ttlSeconds',
      'refreshBeforeSeconds',
      'maxTtlSeconds',
    }, 'cache');
    if ((value['scope'] ?? 'configuration') != 'configuration') {
      throw const HeroFailure('缓存只能按配置组隔离');
    }
    final path = value['ttlFrom'], seconds = value['ttlSeconds'];
    if ((path == null) == (seconds == null) ||
        path != null && (path is! String || !validPluginPath(path)) ||
        seconds != null &&
            (seconds is! int || seconds < 1 || seconds > 86400)) {
      throw const HeroFailure('cache 需要 ttlFrom 或 ttlSeconds');
    }
    final early = value['refreshBeforeSeconds'] ?? 30,
        max = value['maxTtlSeconds'] ?? 3600;
    if (early is! int ||
        early < 0 ||
        early > 300 ||
        max is! int ||
        max < 1 ||
        max > 86400) {
      throw const HeroFailure('缓存 TTL 或提前量无效');
    }
    return PluginCacheSpec(path as String?, seconds as int?, early, max);
  }
  Map<String, dynamic> toJson() => {
    'scope': 'configuration',
    if (ttlFrom != null) 'ttlFrom': ttlFrom,
    if (ttlSeconds != null) 'ttlSeconds': ttlSeconds,
    'refreshBeforeSeconds': refreshBeforeSeconds,
    'maxTtlSeconds': maxTtlSeconds,
  };
}

class PluginCredentialRefresh {
  final List<String> steps;
  final List<int> statuses;
  final PluginCondition? condition;
  const PluginCredentialRefresh(this.steps, this.statuses, this.condition);
  factory PluginCredentialRefresh.fromJson(Object? value) {
    if (value is! Map) throw const HeroFailure('refreshCredentials 必须是对象');
    pluginKeys(value, {
      'steps',
      'statuses',
      'condition',
      'maxAttempts',
    }, 'refreshCredentials');
    final steps = value['steps'], statuses = value['statuses'] ?? [401];
    if (steps is! List ||
        steps.isEmpty ||
        steps.length > 4 ||
        steps.any((s) => s is! String) ||
        statuses is! List ||
        statuses.isEmpty ||
        statuses.length > 8 ||
        statuses.any(
          (s) =>
              s is! int ||
              !{200, 201, 400, 401, 403, 409, 410, 422}.contains(s),
        ) ||
        (value['maxAttempts'] ?? 1) != 1) {
      throw const HeroFailure('凭证失效最多重试一次；禁止超时或 5xx 重传');
    }
    final condition = value['condition'] == null
        ? null
        : PluginCondition.fromJson(value['condition']);
    if (condition == null && statuses.any((s) => s != 401)) {
      throw const HeroFailure('401 以外需要明确凭证失效条件');
    }
    if (condition != null &&
        condition.containsAny == null &&
        (!condition.hasEquals ||
            condition.equals == null ||
            condition.equals is bool ||
            condition.equals is String &&
                (condition.equals as String).isEmpty)) {
      throw const HeroFailure('凭证刷新必须匹配明确错误码或凭证错误关键词');
    }
    return PluginCredentialRefresh(
      steps.cast<String>(),
      statuses.cast<int>(),
      condition,
    );
  }
  bool matches(int? status, Object? data) =>
      statuses.contains(status) && (condition?.matches(data) ?? true);
  Map<String, dynamic> toJson() => {
    'steps': steps,
    'statuses': statuses,
    if (condition != null) 'condition': condition!.toJson(),
    'maxAttempts': 1,
  };
}

void validatePluginProgram(Object? source) {
  var nodes = 0;
  void visit(Object? value, int depth) {
    if (++nodes > 5000 || depth > 16) throw const HeroFailure('插件程序结构过大或嵌套过深');
    if (value is String && value.length > 16384) {
      throw const HeroFailure('插件程序字符串过长');
    }
    if (value is Map) {
      for (final item in value.entries) {
        if (item.key is! String || (item.key as String).length > 120) {
          throw const HeroFailure('程序字段名无效');
        }
        visit(item.value, depth + 1);
      }
    } else if (value is List) {
      for (final item in value) {
        visit(item, depth + 1);
      }
    } else if (value is num && !value.isFinite) {
      throw const HeroFailure('程序数值无效');
    }
  }

  visit(source, 0);
}
