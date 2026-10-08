import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../app_updates.dart';
import '../diagnostics.dart';
import 'plugin_manager.dart';
import 'plugin_package.dart';

class PluginCatalogEntry {
  final String id, name, description, author, version, digest, mark;
  final Uri downloadUrl, repository;
  final int size;
  final bool example;
  final AppVersion minAppVersion;

  PluginCatalogEntry._(
    this.id,
    this.name,
    this.description,
    this.author,
    this.version,
    this.digest,
    this.mark,
    this.downloadUrl,
    this.repository,
    this.size,
    this.example,
    this.minAppVersion,
  );

  factory PluginCatalogEntry.fromJson(Map<String, dynamic> json) {
    String text(String key, int max) {
      final value = json[key];
      if (value is! String || value.isEmpty || value.length > max) {
        throw HeroFailure('模块目录字段无效：$key');
      }
      return value;
    }

    Uri url(String key) {
      final uri = Uri.tryParse(text(key, 2048));
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.fragment.isNotEmpty) {
        throw HeroFailure('模块目录 $key 需要 HTTPS 地址');
      }
      return uri;
    }

    final id = text('id', 80);
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$').hasMatch(id)) {
      throw const HeroFailure('模块目录的插件 ID 无效');
    }
    if (json['runtime'] != 'http-v1' || json['packageVersion'] != 1) {
      throw const HeroFailure('模块目录包含不支持的插件协议');
    }
    final version = text('version', 30);
    AppVersion.parse(version);
    final digest = text('sha256', 64).toLowerCase();
    final size = json['size'];
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        size is! int ||
        size <= 0 ||
        size > PicoraPluginPackage.maxZipBytes) {
      throw const HeroFailure('模块目录的 ZIP 摘要或大小无效');
    }
    return PluginCatalogEntry._(
      id,
      text('name', 60),
      text('description', 160),
      text('author', 80),
      version,
      digest,
      json['mark'] is String
          ? (json['mark'] as String).substring(
              0,
              (json['mark'] as String).length.clamp(0, 3),
            )
          : 'P',
      url('downloadUrl'),
      url('repository'),
      size,
      json['example'] == true,
      AppVersion.parse(text('minAppVersion', 30)),
    );
  }

  bool supports(String appVersion) =>
      minAppVersion.compareTo(
        AppVersion.parse(appVersion, ignoreDebugSuffix: true),
      ) <=
      0;

  bool isUpdateFor(String installedVersion) =>
      AppVersion.parse(version).compareTo(AppVersion.parse(installedVersion)) >
      0;

  PicoraPluginPackage verify(List<int> bytes) {
    if (bytes.length != size || sha256.convert(bytes).toString() != digest) {
      throw const HeroFailure('插件 ZIP 校验失败，请刷新模块仓库后重试');
    }
    final package = PicoraPluginPackage.decode(bytes);
    final manifest = package.manifest;
    if (manifest.id != id ||
        manifest.version != version ||
        manifest.name != name ||
        manifest.author != author) {
      throw const HeroFailure('插件包身份或版本与模块目录不一致');
    }
    return package;
  }
}

class PluginCatalog {
  final List<PluginCatalogEntry> entries;
  final DateTime fetchedAt;
  final Object? refreshError;
  const PluginCatalog(this.entries, this.fetchedAt, {this.refreshError});
  bool get offline => refreshError != null;

  static List<PluginCatalogEntry> parse(String source) {
    if (utf8.encode(source).length > PluginCatalogService.maxIndexBytes) {
      throw const HeroFailure('模块目录超过 1 MB');
    }
    final value = jsonDecode(source);
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['plugins'] is! List ||
        (value['plugins'] as List).length > 500) {
      throw const HeroFailure('模块目录格式无效');
    }
    final entries = <PluginCatalogEntry>[];
    final ids = <String>{};
    for (final item in value['plugins'] as List) {
      if (item is! Map) throw const HeroFailure('模块目录条目无效');
      final entry = PluginCatalogEntry.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (!ids.add(entry.id)) throw const HeroFailure('模块目录有重复插件 ID');
      entries.add(entry);
    }
    return List.unmodifiable(entries);
  }
}

class PluginCatalogService {
  static const indexUrl =
      'https://raw.githubusercontent.com/Alnitak44/picora-plugins/main/index.json';
  static const maxIndexBytes = 1024 * 1024;
  final Dio dio;
  final Directory? storageRoot;
  final DateTime Function() now;
  PluginCatalog? _cached;
  bool _loadedDisk = false;

  PluginCatalogService({Dio? dio, this.storageRoot, DateTime Function()? now})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              maxRedirects: 5,
            ),
          ),
      now = now ?? DateTime.now;

  Future<File> _cacheFile() async => File(
    '${(storageRoot ?? await getApplicationSupportDirectory()).path}/picora-module-index.json',
  );

  Future<PluginCatalog> load({bool forceRefresh = false}) async {
    if (!_loadedDisk) {
      _loadedDisk = true;
      try {
        final file = await _cacheFile();
        if (await file.exists() && await file.length() <= maxIndexBytes * 2) {
          final value = jsonDecode(await file.readAsString()) as Map;
          final date = DateTime.parse(value['fetchedAt'] as String);
          _cached = PluginCatalog(
            PluginCatalog.parse(value['source'] as String),
            date,
          );
        }
      } catch (error, stack) {
        HeroDiagnostics.instance.record('读取模块目录缓存', error, stack: stack);
      }
    }
    final cached = _cached;
    final age = cached == null ? null : now().difference(cached.fetchedAt);
    if (!forceRefresh &&
        age != null &&
        !age.isNegative &&
        age < const Duration(hours: 12)) {
      return cached!;
    }
    try {
      final cancel = CancelToken();
      final response = await dio.get<List<int>>(
        indexUrl,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancel,
        onReceiveProgress: (received, total) {
          if (received > maxIndexBytes || total > maxIndexBytes) {
            cancel.cancel('模块目录超过 1 MB');
          }
        },
      );
      final bytes = response.data ?? <int>[];
      if (bytes.length > maxIndexBytes) throw const HeroFailure('模块目录超过 1 MB');
      final source = utf8.decode(bytes);
      final catalog = PluginCatalog(PluginCatalog.parse(source), now());
      _cached = catalog;
      try {
        final file = await _cacheFile();
        await file.parent.create(recursive: true);
        final pending = File('${file.path}.pending');
        await pending.writeAsString(
          jsonEncode({
            'fetchedAt': catalog.fetchedAt.toIso8601String(),
            'source': source,
          }),
          flush: true,
        );
        await pending.rename(file.path);
      } catch (error, stack) {
        HeroDiagnostics.instance.record('保存模块目录缓存', error, stack: stack);
      }
      return catalog;
    } catch (error, stack) {
      HeroDiagnostics.instance.record('刷新模块仓库', error, stack: stack);
      if (cached == null) rethrow;
      return PluginCatalog(
        cached.entries,
        cached.fetchedAt,
        refreshError: error,
      );
    }
  }

  Future<PicoraPluginPackage> download(
    PluginCatalogEntry entry,
    PicoraPluginManager manager,
  ) async {
    final Uint8List bytes = await manager.fetch(entry.downloadUrl);
    return entry.verify(bytes);
  }
}
