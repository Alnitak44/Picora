import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

class HostField {
  final String key, label, hint;
  final bool required, secret;
  final Object? defaultValue;
  final List<String>? choices;
  const HostField(
    this.key,
    this.label, {
    this.hint = '',
    this.required = false,
    this.secret = false,
    this.defaultValue,
    this.choices,
  });
  bool get isToggle => defaultValue is bool;
}

class HostSpec {
  final String id, name, description, mark;
  final Color color;
  final List<HostField> fields;
  final String? iconAsset;
  final Uint8List? iconBytes;
  final String? iconFormat;
  final String? pluginId, pluginVersion;
  final bool builtInConnector;
  final List<String> permissionSummary;
  const HostSpec(
    this.id,
    this.name,
    this.description,
    this.mark,
    this.color,
    this.fields, {
    this.iconAsset,
    this.iconBytes,
    this.iconFormat,
    this.pluginId,
    this.pluginVersion,
    this.builtInConnector = false,
    this.permissionSummary = const [],
  });
  bool get isPlugin => pluginId != null;
  bool get isRuntimePlugin => isPlugin && !builtInConnector;
  bool get canBrowse => !isPlugin;
  bool get canExportToPicGo => !isPlugin;
}

HostSpec unknownHostSpec(String id) => HostSpec(
  id,
  '已移除的插件',
  '历史上传记录',
  '?',
  const Color(0xFF8A93A5),
  const [],
  pluginId: id,
);

const _path = HostField('path', '存储路径', hint: '例如 images/，留空上传至根目录');
const _url = HostField('customUrl', '自定义域名', hint: 'https://cdn.example.com');
const _options = HostField('options', '图片处理后缀', hint: '可选，例如 ?x-oss-process=…');
const _uploadPath = HostField('uploadPath', '上传路径', hint: '例如 /images/');
const _webPath = HostField('webPath', '访问路径', hint: '文件公开访问时使用的路径');
final hostSpecs = <HostSpec>[
  HostSpec(
    'aliyun',
    '阿里云 OSS',
    '存储桶 · OSS',
    'A',
    Color(0xFFFF8A47),
    [
      HostField('keyId', 'AccessKey ID', required: true),
      HostField('keySecret', 'AccessKey Secret', required: true, secret: true),
      HostField('bucket', 'Bucket 名称', required: true),
      HostField('area', '存储区域', hint: 'oss-cn-hangzhou', required: true),
      _path,
      _url,
      _options,
    ],
    iconAsset: 'assets/images/providers/aliyun.svg',
  ),
  HostSpec(
    'tencent',
    '腾讯云 COS',
    '存储桶 · COS',
    'T',
    Color(0xFF4385EF),
    [
      HostField('secretId', 'Secret ID', required: true),
      HostField('secretKey', 'Secret Key', required: true, secret: true),
      HostField('bucket', 'Bucket 名称', hint: '包含 APPID 的完整名称', required: true),
      HostField('appId', 'APPID', required: true),
      HostField('area', '存储区域', hint: 'ap-guangzhou', required: true),
      _path,
      _url,
      _options,
    ],
    iconAsset: 'assets/images/providers/tencent.svg',
  ),
  HostSpec(
    'upyun',
    '又拍云',
    '云存储 · USS',
    'U',
    Color(0xFF52A8CA),
    [
      HostField('bucket', '服务名称', required: true),
      HostField('operator', '操作员', required: true),
      HostField('password', '操作员密码', required: true, secret: true),
      HostField('url', '加速域名', hint: 'https://…', required: true),
      _path,
      _options,
      HostField('antiLeechToken', '防盗链密钥', secret: true),
      HostField('antiLeechExpiration', '防盗链有效期（秒）', defaultValue: '1800'),
    ],
    iconAsset: 'assets/images/providers/upyun.png',
  ),
  HostSpec(
    'qiniu',
    '七牛云',
    '存储桶 · Kodo',
    'Q',
    Color(0xFF45A5ED),
    [
      HostField('accessKey', 'Access Key', required: true),
      HostField('secretKey', 'Secret Key', required: true, secret: true),
      HostField('bucket', 'Bucket 名称', required: true),
      HostField('url', '访问域名', required: true, hint: 'https://…'),
      HostField(
        'area',
        '存储区域',
        required: true,
        defaultValue: 'z0',
        choices: ['z0', 'z1', 'z2', 'na0', 'as0'],
      ),
      _path,
      _options,
    ],
    iconAsset: 'assets/images/providers/qiniu.svg',
  ),
  HostSpec(
    'aws',
    'S3 兼容存储',
    'Amazon S3 / R2 / MinIO',
    'S3',
    Color(0xFF7B6AE6),
    [
      HostField('accessKeyId', 'Access Key ID', required: true),
      HostField(
        'secretAccessKey',
        'Secret Access Key',
        required: true,
        secret: true,
      ),
      HostField('bucket', 'Bucket 名称', required: true),
      HostField(
        'endpoint',
        'Endpoint',
        required: true,
        hint: 's3.example.com，不含 https://',
      ),
      HostField('region', '区域', hint: '可选，例如 us-east-1'),
      _uploadPath,
      _url,
      HostField('isS3PathStyle', '使用路径风格', defaultValue: false),
      HostField('isEnableSSL', '使用 HTTPS', defaultValue: true),
    ],
  ),
  HostSpec('lsky.pro', '兰空图床', 'Lsky Pro V2 · 自建图床', 'L', Color(0xFF6580EF), [
    HostField(
      'host',
      '图床地址',
      required: true,
      hint: 'https://images.example.com',
    ),
    HostField('token', 'API Token', required: true, secret: true),
    HostField('strategy_id', '存储策略 ID'),
    HostField('album_id', '相册 ID'),
  ]),
  HostSpec(
    'github',
    'GitHub',
    '仓库文件 · Contents API',
    'G',
    Color(0xFF414D66),
    [
      HostField('githubusername', 'GitHub 用户名', required: true),
      HostField('repo', '仓库名称', required: true),
      HostField('token', 'Personal Access Token', required: true, secret: true),
      HostField('branch', '分支', required: true, defaultValue: 'main'),
      HostField('storePath', '存储路径'),
      HostField('customDomain', '自定义域名'),
    ],
    iconAsset: 'assets/images/providers/github.png',
  ),
  HostSpec('sm.ms', 'SM.MS', 'Web 图床 · API 上传', 'SM', Color(0xFF44B4A0), [
    HostField('token', 'API Token', required: true, secret: true),
  ]),
  HostSpec('imgur', 'Imgur', 'Web 图床 · API 上传', 'I', Color(0xFF4AB766), [
    HostField('clientId', 'Client ID', required: true),
    HostField('proxy', 'API 代理地址', hint: '可选，完整 API 地址'),
  ]),
  HostSpec('webdav', 'WebDAV', '网盘 · 标准协议', 'W', Color(0xFF628CAE), [
    HostField('host', '服务器地址', required: true, hint: 'https://dav.example.com'),
    HostField('webdavusername', '用户名', required: true),
    HostField('password', '密码', required: true, secret: true),
    _uploadPath,
    _url,
    _webPath,
  ]),
  HostSpec('alist', 'OpenList', '网盘聚合 · 统一管理', 'OL', Color(0xFFAF81DB), [
    HostField(
      'host',
      'OpenList 地址',
      required: true,
      hint: 'https://openlist.example.com',
    ),
    HostField('adminToken', '管理员 Token', secret: true),
    HostField('alistusername', '用户名'),
    HostField('password', '密码', secret: true),
    HostField('token', '访问 Token', hint: '留空时通过用户名和密码获取', secret: true),
    _uploadPath,
    _url,
    _webPath,
  ]),
  HostSpec('ftp', 'FTP / SFTP', '服务器 · 文件传输', 'F', Color(0xFFDA9E4F), [
    HostField('ftpHost', '服务器', required: true),
    HostField('ftpPort', '端口', defaultValue: '22', required: true),
    HostField('ftpUser', '用户名', required: true),
    HostField('ftpPassword', '密码', secret: true),
    HostField('ftpType', '协议', choices: ['SFTP', 'FTP'], defaultValue: 'SFTP'),
    HostField('isAnonymous', '匿名访问', defaultValue: false),
    _uploadPath,
    HostField('ftpHomeDir', '主目录', defaultValue: '/'),
    HostField('ftpCustomUrl', '自定义域名'),
    HostField('ftpWebPath', '访问路径'),
  ]),
  HostSpec(
    'picgo',
    'PicGo Bridge',
    '连接电脑或 NAS 上的 PicGo Server',
    'PG',
    Color(0xFF4F6FEF),
    [
      HostField(
        'serverUrl',
        'PicGo Server 地址',
        required: true,
        hint: '例如 http://192.168.1.10:36677',
      ),
      HostField('secret', 'Server Secret', secret: true),
      HostField('uploader', 'Uploader ID', hint: '可选，例如 github'),
      HostField('configName', '配置名称', hint: '可选，支持中文'),
      HostField('configId', '配置 ID', hint: '可选，优先级高于配置名称'),
      HostField('timeoutSeconds', '超时秒数', defaultValue: '90'),
    ],
    pluginId: 'builtin.picgo-bridge',
    pluginVersion: '1.0.0',
    builtInConnector: true,
    permissionSummary: ['读取待上传文件', '访问用户配置的 PicGo Server'],
  ),
];
HostSpec hostSpec(String id) =>
    hostSpecs.where((e) => e.id == id).firstOrNull ?? unknownHostSpec(id);

void replaceRuntimePluginSpecs(Iterable<HostSpec> specs) {
  hostSpecs.removeWhere((spec) => spec.isRuntimePlugin);
  hostSpecs.addAll(specs);
}

class RepositoryConfig {
  final String host, slot, name;
  final Map<String, dynamic> values;
  const RepositoryConfig({
    required this.host,
    required this.slot,
    required this.name,
    required this.values,
  });
  String get id => '$host:$slot';
  HostSpec get spec => hostSpec(host);
  String get location {
    for (final key in ['bucket', 'repo', 'host', 'ftpHost', 'endpoint']) {
      final value = values[key];
      if (value != null && value != 'None' && value != 'undetermined') {
        return value.toString();
      }
    }
    return spec.description;
  }
}

class AlbumEntry {
  final Map<String, dynamic> row;
  final String host;
  final DateTime? uploadedAt;
  final String? repositoryId;
  const AlbumEntry(this.row, this.host, {this.uploadedAt, this.repositoryId});
  String get id => '$host:${row['id']}';
  String get name => row['name']?.toString() ?? '未命名图片';
  String get url {
    final display = row['hostSpecificArgA']?.toString();
    if (host == 'github' && display != null && display.startsWith('http')) {
      return display;
    }
    return row['url']?.toString() ?? '';
  }

  String get path => row['path']?.toString() ?? '';
  String get thumbnail {
    if (host == 'ftp') return row['hostSpecificArgI']?.toString() ?? path;
    final value = row['hostSpecificArgA']?.toString();
    return value == null || value.isEmpty || value == 'test' ? url : value;
  }
}
