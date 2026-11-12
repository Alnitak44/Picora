import 'dart:convert';
import 'models.dart';
import 'controller.dart';
import 'diagnostics.dart';

/// Accepts native Picora, PicHoro slots and PicGo/PicList picBed JSON.
class ConfigExchange {
  static List<(HostSpec, String, Map<String, dynamic>)> parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const HeroFailure('配置必须是 JSON 对象');
    final result = <(HostSpec, String, Map<String, dynamic>)>[];
    if (decoded['repositories'] is List) {
      for (final entry in decoded['repositories']) {
        final exportedHost = entry['host']?.toString();
        final internalHost = exportedHost == 'openlist'
            ? 'alist'
            : exportedHost;
        final spec = hostSpecs.where((s) => s.id == internalHost).firstOrNull;
        if (spec == null || entry['values'] is! Map) {
          throw const HeroFailure('配置包含不支持的平台');
        }
        result.add((
          spec,
          entry['name']?.toString() ?? '${spec.name} · 导入',
          Map<String, dynamic>.from(entry['values']),
        ));
      }
      return _validate(result);
    }
    final source = decoded['picBed'] is Map
        ? decoded['picBed'] as Map
        : decoded;
    const aliases = {
      'aliyun': 'aliyun',
      'tcyun': 'tencent',
      'tencent': 'tencent',
      'qiniu': 'qiniu',
      'upyun': 'upyun',
      'github': 'github',
      'smms': 'sm.ms',
      'sm.ms': 'sm.ms',
      'imgur': 'imgur',
      'lankong': 'lsky.pro',
      'lskyplist': 'lsky.pro',
      'lsky.pro': 'lsky.pro',
      'aws-s3': 'aws',
      'aws-s3-plist': 'aws',
      'aws': 'aws',
      'webdav': 'webdav',
      'webdavplist': 'webdav',
      'alist': 'alist',
      'alistplist': 'alist',
      'openlist': 'alist',
      'openlistplist': 'alist',
      'ftp': 'ftp',
    };
    for (final item in source.entries) {
      if (!aliases.containsKey(item.key) || item.value is! Map) continue;
      final spec = hostSpec(aliases[item.key]!);
      final raw = Map<String, dynamic>.from(item.value);
      final slots = raw.entries.where(
        (e) => RegExp(r'^[A-Z]$').hasMatch(e.key) && e.value is Map,
      );
      if (slots.isNotEmpty) {
        for (final slot in slots) {
          result.add((
            spec,
            '${spec.name} · ${slot.key}',
            Map<String, dynamic>.from(slot.value),
          ));
        }
        continue;
      }
      final v = Map<String, dynamic>.from(raw);
      if (spec.id == 'aliyun') {
        v['keyId'] = raw['keyId'] ?? raw['accessKeyId'];
        v['keySecret'] = raw['keySecret'] ?? raw['accessKeySecret'];
      }
      if (spec.id == 'github' &&
          raw['repo']?.toString().contains('/') == true) {
        final parts = raw['repo'].toString().split('/');
        v['githubusername'] = parts[0];
        v['repo'] = parts[1];
        v['storePath'] = raw['path'];
        v['customDomain'] = raw['customUrl'];
      }
      if (spec.id == 'lsky.pro') {
        v['host'] = raw['host'] ?? raw['server'];
        v['strategy_id'] = raw['strategy_id'] ?? raw['strategyId'];
        v['album_id'] = raw['album_id'] ?? raw['albumId'];
      }
      if (spec.id == 'aws') {
        v['accessKeyId'] = raw['accessKeyId'] ?? raw['accessKeyID'];
        v['bucket'] = raw['bucket'] ?? raw['bucketName'];
        v['customUrl'] = raw['customUrl'] ?? raw['urlPrefix'];
        v['isS3PathStyle'] = raw['isS3PathStyle'] ?? raw['pathStyleAccess'];
        final endpoint = v['endpoint']?.toString() ?? '';
        if (endpoint.contains('://')) {
          v['isEnableSSL'] = endpoint.startsWith('https');
          v['endpoint'] = endpoint.split('://').last;
        }
      }
      if (spec.id == 'webdav') {
        v['host'] = raw['host'] ?? raw['url'];
        v['webdavusername'] = raw['webdavusername'] ?? raw['username'];
      }
      if (spec.id == 'alist') {
        v['host'] = raw['host'] ?? raw['url'];
        v['alistusername'] = raw['alistusername'] ?? raw['username'];
        v['adminToken'] = raw['adminToken'] ?? raw['token'];
      }
      result.add((
        spec,
        raw['remarkName']?.toString() ?? '${spec.name} · 导入',
        v,
      ));
    }
    if (result.isEmpty) throw const HeroFailure('未识别到支持的 PicGo / PicList 配置');
    return _validate(result);
  }

  static List<(HostSpec, String, Map<String, dynamic>)> _validate(
    List<(HostSpec, String, Map<String, dynamic>)> configs,
  ) {
    for (final c in configs) {
      if (c.$1.id == 'alist' &&
          (c.$3['token']?.toString().isNotEmpty != true) &&
          (c.$3['alistusername']?.toString().isNotEmpty != true ||
              c.$3['password']?.toString().isNotEmpty != true)) {
        throw const HeroFailure('OpenList 需要 Token 或用户名和密码');
      }
      for (final field in c.$1.fields.where((f) => f.required)) {
        final value = c.$3[field.key] ?? field.defaultValue;
        if (value == null ||
            value.toString().trim().isEmpty ||
            value == 'None' ||
            value == 'undetermined') {
          throw HeroFailure('${c.$1.name} 缺少${field.label}');
        }
      }
    }
    return configs;
  }

  static String export(List<RepositoryConfig> configs) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'application': 'Picora',
        'repositories': configs
            .map(
              (r) => {
                'host': r.host == 'alist' ? 'openlist' : r.host,
                'name': r.name,
                'values': r.values,
              },
            )
            .toList(),
      });
  static String exportPicGo(RepositoryConfig config) {
    if (!config.spec.canExportToPicGo) {
      throw const HeroFailure('插件图床不能导出为 PicGo 配置，请导出 Picora 备份');
    }
    final v = Map<String, dynamic>.from(config.values)
      ..removeWhere((k, value) => value == 'None');
    var type = config.host;
    if (type == 'aliyun') {
      v['accessKeyId'] = v.remove('keyId');
      v['accessKeySecret'] = v.remove('keySecret');
    }
    if (type == 'tencent') type = 'tcyun';
    if (type == 'sm.ms') type = 'smms';
    if (type == 'github') {
      v['repo'] = '${v.remove('githubusername')}/${v['repo']}';
      v['path'] = v.remove('storePath');
      v['customUrl'] = v.remove('customDomain');
    }
    if (type == 'lsky.pro') {
      type = 'lskyplist';
      v['server'] = v.remove('host');
      v['strategyId'] = v.remove('strategy_id');
      v['albumId'] = v.remove('album_id');
      v['version'] = 'V2';
    }
    if (type == 'aws') {
      type = 'aws-s3';
      v['accessKeyID'] = v.remove('accessKeyId');
      v['bucketName'] = v.remove('bucket');
      v['urlPrefix'] = v.remove('customUrl');
      v['pathStyleAccess'] = v.remove('isS3PathStyle');
      v['endpoint'] =
          '${v.remove('isEnableSSL') == false ? 'http' : 'https'}://${v['endpoint']}';
    }
    return const JsonEncoder.withIndent('  ').convert({
      'picBed': {'current': type, type: v},
    });
  }

  static Future<int> import(PicoraController controller, String text) async {
    final configs = parse(text);
    // Capacity is checked before writing to avoid a partial import.
    for (final spec in hostSpecs) {
      if (controller.repositories.where((r) => r.host == spec.id).length +
              configs.where((c) => c.$1.id == spec.id).length >
          26) {
        throw HeroFailure('${spec.name} 的配置数量超过 26 组');
      }
    }
    for (final config in configs) {
      await controller.saveRepository(config.$1, config.$2, config.$3);
    }
    return configs.length;
  }
}
