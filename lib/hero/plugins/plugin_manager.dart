import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

import '../diagnostics.dart';
import '../models.dart';
import '../app_updates.dart';
import '../github_mirrors.dart';
import 'plugin_manifest.dart';
import 'plugin_package.dart';
import 'uploader_registry.dart';

class PluginInstallResult {
  final PicoraPluginManifest manifest;
  final bool updated;

  const PluginInstallResult(this.manifest, {required this.updated});
}

class PicoraPluginManager {
  final UploaderRegistry registry;
  final Directory? storageRoot;
  final Dio downloadDio;
  final Map<String, PicoraPluginManifest> _installed = {};
  final Map<String, PicoraPluginPackage> _packages = {};

  Directory? _pluginDirectory;
  File? _repositoryFile;
  bool _initialized = false;

  PicoraPluginManager({
    required this.registry,
    this.storageRoot,
    Dio? downloadDio,
  }) : downloadDio =
           downloadDio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 30),
               followRedirects: true,
               maxRedirects: 5,
             ),
           );

  List<PicoraPluginManifest> get installed {
    final result = _installed.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(result);
  }

  bool get initialized => _initialized;
  bool isExample(String id) => _packages[id]?.metadata['example'] == true;
  PicoraPluginPackage packageFor(String id) {
    final package = _packages[id];
    if (package == null) throw const HeroFailure('插件不存在');
    return package;
  }

  bool isEnabled(String id) =>
      SpUtil.getBool('hero_plugin_enabled_$id', defValue: true) ?? true;

  bool isCloudDeleteAllowed(String id) =>
      SpUtil.getBool('hero_plugin_cloud_delete_$id', defValue: false) ?? false;

  Future<void> setCloudDeleteAllowed(String id, bool allowed) async {
    await initialize();
    final plugin = _installed[id];
    if (plugin == null || plugin.delete == null) {
      throw const HeroFailure('该插件没有删除接口');
    }
    await SpUtil.putBool('hero_plugin_cloud_delete_$id', allowed);
    registry.runtime.clearCredentials();
  }

  Future<Directory> _root() async =>
      storageRoot ?? await getApplicationSupportDirectory();

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    final root = await _root();
    _pluginDirectory = Directory('${root.path}/picora-plugins');
    _repositoryFile = File('${root.path}/picora-plugin-repositories.json');
    await _pluginDirectory!.create(recursive: true);
    _installed.clear();
    _packages.clear();
    final entries = await _pluginDirectory!.list().toList();
    // ZIP versions win over legacy files retained as migration backups.
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      final zip = entity.path.toLowerCase().endsWith('.zip');
      if (entity is! File ||
          (!zip && !entity.path.toLowerCase().endsWith('.json'))) {
        continue;
      }
      try {
        if (await entity.length() >
            (zip ? PicoraPluginPackage.maxZipBytes : 1024 * 1024)) {
          throw const HeroFailure('已安装插件文件超过大小限制');
        }
        final package = zip
            ? PicoraPluginPackage.decode(await entity.readAsBytes())
            : PicoraPluginPackage.fromLegacy(
                inspect(await entity.readAsString()),
              );
        final manifest = package.manifest;

        if (!zip) {
          final target = File('${_pluginDirectory!.path}/${manifest.id}.zip');
          if (await target.exists()) continue;
          await _persistPackage(package);
          await entity.rename('${entity.path}.legacy');
        }
        _installed[manifest.id] = manifest;
        _packages[manifest.id] = package;
      } catch (error, stack) {
        HeroDiagnostics.instance.record(
          '加载插件包',
          error,
          stack: stack,
          context: {'file': entity.path},
        );
      }
    }
    _initialized = true;
    _syncRuntime();
  }

  PicoraPluginManifest inspect(String source) {
    if (utf8.encode(source).length > 1024 * 1024) {
      throw const HeroFailure('插件清单不能超过 1 MB');
    }
    return PicoraPluginManifest.parse(source);
  }

  Future<PluginInstallResult> install(String source) async {
    return installPackage(
      PicoraPluginPackage.fromLegacy(inspect(source)).bytes,
    );
  }

  PicoraPluginPackage inspectPackage(List<int> bytes) =>
      PicoraPluginPackage.decode(bytes);

  Future<void> _persistPackage(PicoraPluginPackage package) async {
    final target = File('${_pluginDirectory!.path}/${package.manifest.id}.zip');
    final pending = File('${target.path}.pending');
    try {
      await pending.writeAsBytes(package.bytes, flush: true);
      await pending.rename(target.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  Future<PluginInstallResult> installPackage(List<int> bytes) async {
    await initialize();
    final package = inspectPackage(bytes);
    final manifest = package.manifest;
    final incomingVersion = AppVersion.parse(manifest.version);
    final previous = _installed[manifest.id];
    if (previous != null &&
        incomingVersion.compareTo(AppVersion.parse(previous.version)) < 0) {
      throw const HeroFailure('不能覆盖安装更旧版本的插件');
    }
    final updated = previous != null;
    await _persistPackage(package);
    // A new package cannot inherit a previous version's destructive permission.
    await SpUtil.putBool('hero_plugin_cloud_delete_${manifest.id}', false);
    _installed[manifest.id] = manifest;
    _packages[manifest.id] = package;
    if (!updated &&
        SpUtil.getBool('hero_plugin_enabled_${manifest.id}') == null) {
      await SpUtil.putBool('hero_plugin_enabled_${manifest.id}', true);
    }
    _syncRuntime();
    return PluginInstallResult(manifest, updated: updated);
  }

  Future<Uint8List> fetch(Uri uri) async {
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
      throw const HeroFailure('插件地址必须是 HTTP 或 HTTPS URL');
    }
    final cancel = CancelToken();
    final response = await downloadDio.get<List<int>>(
      GitHubMirrors.instance
          .resolve(uri, headers: downloadDio.options.headers)
          .toString(),
      cancelToken: cancel,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: (received, total) {
        if (received > PicoraPluginPackage.maxZipBytes ||
            total > PicoraPluginPackage.maxZipBytes) {
          cancel.cancel('插件 ZIP 超过 10 MB');
        }
      },
    );
    final source = response.data ?? const <int>[];
    if (source.isEmpty) throw const HeroFailure('插件地址返回了空内容');
    if (source.length > PicoraPluginPackage.maxZipBytes) {
      throw const HeroFailure('插件 ZIP 不能超过 10 MB');
    }
    return Uint8List.fromList(source);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await initialize();
    if (!_installed.containsKey(id)) throw const HeroFailure('插件不存在');
    await SpUtil.putBool('hero_plugin_enabled_$id', enabled);
    _syncRuntime();
  }

  Future<void> remove(String id) async {
    await initialize();
    final manifest = _installed[id];
    if (manifest == null) throw const HeroFailure('插件不存在');
    final repositories = await readRepositories();
    if (repositories.any((item) => item.host == manifest.hostId)) {
      throw const HeroFailure('请先删除这个插件创建的图床配置');
    }
    for (final extension in ['zip', 'json', 'json.legacy']) {
      final file = File('${_pluginDirectory!.path}/$id.$extension');
      if (await file.exists()) await file.delete();
    }
    await SpUtil.remove('hero_plugin_cloud_delete_$id');
    _installed.remove(id);
    _packages.remove(id);
    await SpUtil.remove('hero_plugin_enabled_$id');
    _syncRuntime();
  }

  String sourceFor(String id) {
    final manifest = _installed[id];
    if (manifest == null) throw const HeroFailure('插件不存在');
    return manifest.encode();
  }

  Future<List<RepositoryConfig>> readRepositories() async {
    await initialize();
    if (!await _repositoryFile!.exists()) return [];
    Object? decoded;
    try {
      decoded = jsonDecode(await _repositoryFile!.readAsString());
    } catch (error) {
      throw HeroFailure('插件配置文件损坏：$error');
    }
    if (decoded is! List) throw const HeroFailure('插件配置文件格式错误');
    final result = <RepositoryConfig>[];
    for (final item in decoded) {
      if (item is! Map || item['values'] is! Map) continue;
      final host = item['host']?.toString() ?? '';
      // Retain configurations whose plugin is missing after an app upgrade.
      if (!host.startsWith('plugin.') ||
          !RegExp(
            r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$',
          ).hasMatch(host.substring(7))) {
        continue;
      }
      result.add(
        RepositoryConfig(
          host: host,
          slot: item['slot']?.toString() ?? 'A',
          name: item['name']?.toString() ?? hostSpec(host).name,
          values: Map<String, dynamic>.from(item['values']),
        ),
      );
    }
    return result;
  }

  Future<RepositoryConfig> saveRepository(
    HostSpec spec,
    String name,
    Map<String, dynamic> values, {
    RepositoryConfig? existing,
  }) async {
    await initialize();
    if (!spec.isPlugin) throw const HeroFailure('这不是插件图床');
    if (!_installed.containsKey(spec.pluginId)) {
      throw const HeroFailure('请先从模块仓库安装对应插件，再编辑配置');
    }
    final repositories = await readRepositories();
    final used = repositories
        .where((item) => item.host == spec.id)
        .map((item) => item.slot)
        .toSet();
    final slot =
        existing?.slot ??
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
            .split('')
            .where((candidate) => !used.contains(candidate))
            .firstOrNull;
    if (slot == null) throw const HeroFailure('该插件的 26 组配置已满');
    final config = RepositoryConfig(
      host: spec.id,
      slot: slot,
      name: name.trim(),
      values: values,
    );
    repositories.removeWhere((item) => item.id == config.id);
    repositories.add(config);
    await _writeRepositories(repositories);
    return config;
  }

  Future<void> deleteRepository(RepositoryConfig config) async {
    final repositories = await readRepositories();
    repositories.removeWhere((item) => item.id == config.id);
    await _writeRepositories(repositories);
  }

  Future<void> _writeRepositories(List<RepositoryConfig> repositories) async {
    registry.runtime.clearCredentials();
    await _repositoryFile!.parent.create(recursive: true);
    await _repositoryFile!.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        repositories
            .map(
              (item) => {
                'host': item.host,
                'slot': item.slot,
                'name': item.name,
                'values': item.values,
              },
            )
            .toList(),
      ),
      flush: true,
    );
  }

  void _syncRuntime() {
    replaceRuntimePluginSpecs(
      _packages.values.map((package) => package.toHostSpec()),
    );
    registry.syncPlugins(_installed.values, isEnabled);
  }
}
