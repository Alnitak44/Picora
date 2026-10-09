import 'package:picora/picture_host_manage/manage_api/alist_manage_api.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:picora/album/album_sql.dart';
import 'package:picora/picture_host_configure/configure_store/configure_store_file.dart';
import 'package:picora/utils/common_functions.dart';
import 'package:picora/utils/global.dart';
import 'package:picora/utils/image_compressor.dart';
import 'models.dart';
import 'diagnostics.dart';
import 'plugins/plugin_manager.dart';
import 'plugins/plugin_manifest.dart';
import 'plugins/uploader_registry.dart';
import 'markdown_migration.dart';

typedef UploadCall =
    Future<dynamic> Function(
      String host,
      String path,
      String name,
      Map<String, dynamic> values,
    );

class PicoraController extends ChangeNotifier {
  final UploadCall? uploadOverride;
  final UploaderRegistry uploaderRegistry;
  late final PicoraPluginManager pluginManager;
  PicoraController({
    this.uploadOverride,
    UploaderRegistry? uploaderRegistry,
    PicoraPluginManager? pluginManager,
  }) : uploaderRegistry = uploaderRegistry ?? UploaderRegistry() {
    this.pluginManager =
        pluginManager ?? PicoraPluginManager(registry: this.uploaderRegistry);
  }
  List<RepositoryConfig> repositories = [];
  List<AlbumEntry> images = [];
  List<String> pendingSharedPaths = [];
  bool continuousCamera = false;
  RepositoryConfig? target;
  String? defaultId;
  AlbumEntry? latest;
  bool initializing = true, busy = false;
  double progress = 0;
  String activity = '', themeChoice = 'system';
  String? failure, failedPath, initializationFailure;
  File? _metadataFile;
  Map<String, dynamic> _metadata = {};
  bool _disposed = false, _initializationInFlight = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> initialize() async {
    if (busy || _initializationInFlight) return;
    _initializationInFlight = true;
    initializing = true;
    initializationFailure = null;
    notifyListeners();
    try {
      await HeroDiagnostics.instance.initialize();
      await mainInit();
      await pluginManager.initialize();
      final dir = await getApplicationSupportDirectory();
      _metadataFile = File('${dir.path}/picora-album-meta.json');
      if (await _metadataFile!.exists()) {
        _metadata = Map<String, dynamic>.from(
          jsonDecode(await _metadataFile!.readAsString()),
        );
      }
      defaultId = SpUtil.getString('hero_default_repository');
      themeChoice = SpUtil.getString('hero_theme', defValue: 'system')!;
      if (!['light', 'system', 'dark'].contains(themeChoice)) {
        themeChoice = 'system';
      }
      continuousCamera = SpUtil.getBool(
        'hero_continuous_camera',
        defValue: false,
      )!;
      await loadRepositories();
      await loadImages();
    } catch (e, stack) {
      initializationFailure = describeError('初始化', e, stack);
    } finally {
      initializing = false;
      _initializationInFlight = false;
      notifyListeners();
    }
  }

  String describeError(String action, Object error, StackTrace stack) {
    final id = HeroDiagnostics.instance.record(
      action,
      error,
      stack: stack,
      context: {
        'provider': target?.host,
        'configuration': target?.id,
        'activity': activity,
      },
    );
    return '${error is HeroFailure ? error.message : '$action失败，请查看诊断日志'} · #$id';
  }

  Future<File> _activeFile(String host) async => File(
    '${(await getApplicationDocumentsDirectory()).path}/${Global.getUser()}_${getpdconfig(host)}.txt',
  );
  Iterable<HostSpec> get availableHostSpecs => hostSpecs.where(
    (spec) => !spec.isRuntimePlugin || pluginManager.isEnabled(spec.pluginId!),
  );
  List<PicoraPluginManifest> get installedPlugins => pluginManager.installed;

  Future<void> loadRepositories() async {
    await pluginManager.initialize();
    final loaded = <RepositoryConfig>[];
    for (final spec in hostSpecs.where((item) => !item.isPlugin)) {
      final Map slots = await ConfigureStoreFile().readConfigureFile(spec.id);
      // Existing PicHoro active configurations are migrated once into free slots.
      final active = await _activeFile(spec.id);
      if (await active.exists() && (await active.length()) > 0) {
        final values = Map<String, dynamic>.from(
          jsonDecode(await active.readAsString()),
        );
        if (values.isNotEmpty &&
            !slots.values.any(
              (v) => _sameConfig(Map<String, dynamic>.from(v), values),
            )) {
          final free = slots.keys
              .cast<String>()
              .where(
                (key) =>
                    ConfigureStoreFile().checkIfOneUndetermined(slots[key]),
              )
              .firstOrNull;
          if (free != null &&
              SpUtil.getBool('hero_migrated_${spec.id}', defValue: false) !=
                  true) {
            slots[free] = {...values, 'remarkName': '${spec.name} · 原配置'};
            await ConfigureStoreFile().updateConfigureFile(spec.id, slots);
          }
        }
        await SpUtil.putBool('hero_migrated_${spec.id}', true);
      }
      for (final entry in slots.entries) {
        if (ConfigureStoreFile().checkIfOneUndetermined(entry.value)) continue;
        final values = Map<String, dynamic>.from(entry.value);
        final remark = values['remarkName'];
        loaded.add(
          RepositoryConfig(
            host: spec.id,
            slot: entry.key.toString(),
            name:
                remark == null ||
                    remark == 'undetermined' ||
                    remark == 'None' ||
                    remark == ''
                ? '${spec.name} · ${entry.key}'
                : remark.toString(),
            values: normalizeValues(spec, values),
          ),
        );
      }
    }
    for (final config in await pluginManager.readRepositories()) {
      final spec = hostSpec(config.host);
      loaded.add(
        RepositoryConfig(
          host: config.host,
          slot: config.slot,
          name: config.name,
          values:
              pluginManager.installed.any((item) => item.hostId == config.host)
              ? normalizeValues(spec, config.values)
              : Map<String, dynamic>.from(config.values),
        ),
      );
    }
    repositories = loaded;
    if (defaultId == null || !loaded.any((r) => r.id == defaultId)) {
      defaultId =
          loaded.where((r) => r.host == Global.getPShost()).firstOrNull?.id ??
          loaded.firstOrNull?.id;
      if (defaultId != null) {
        await SpUtil.putString('hero_default_repository', defaultId!);
      }
    }
    target =
        loaded.where((r) => r.id == (target?.id ?? defaultId)).firstOrNull ??
        loaded.firstOrNull;
    notifyListeners();
  }

  bool _sameConfig(Map<String, dynamic> a, Map<String, dynamic> b) => b.entries
      .where((e) => e.key != 'remarkName')
      .every((e) => a[e.key] == e.value);

  static Map<String, dynamic> normalizeValues(
    HostSpec spec,
    Map<String, dynamic> source,
  ) {
    final values = <String, dynamic>{};
    for (final field in spec.fields) {
      var value = source[field.key];
      if (value == null || value == 'undetermined' || value == '') {
        value = field.defaultValue ?? 'None';
      }
      if (field.isToggle) {
        value = value == true || value.toString().toLowerCase() == 'true';
      }
      values[field.key] = value;
    }
    if (spec.id == 'github' &&
        values['token'] != 'None' &&
        !values['token'].toString().startsWith('Bearer ')) {
      values['token'] = 'Bearer ${values['token']}';
    }
    if (spec.id == 'lsky.pro' &&
        values['token'] != 'None' &&
        !values['token'].toString().startsWith('Bearer ')) {
      values['token'] = 'Bearer ${values['token']}';
    }
    for (final key in [
      'host',
      'customUrl',
      'customDomain',
      'url',
      'ftpCustomUrl',
    ]) {
      if (values[key] is String && values[key] != 'None') {
        values[key] = (values[key] as String).replaceAll(RegExp(r'/+$'), '');
      }
    }
    for (final key in ['path', 'storePath']) {
      if (values[key] is String &&
          values[key] != 'None' &&
          !(values[key] as String).endsWith('/')) {
        values[key] = '${values[key]}/';
      }
    }
    if (spec.id == 'ftp') {
      values['ftpType'] = values['ftpType'].toString().toUpperCase();
      // Inherited FTP implementation uses a string for this switch.
      values['isAnonymous'] = values['isAnonymous'].toString();
    }
    return values;
  }

  void selectTarget(RepositoryConfig config) {
    if (busy) throw const HeroFailure('上传进行中，请完成后切换图床');
    target = config;
    notifyListeners();
  }

  Future<void> activateForBrowser(RepositoryConfig config) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后浏览云端');
    if (!config.spec.canBrowse) {
      throw const HeroFailure('插件图床暂不提供云端文件浏览');
    }
    await (await _activeFile(
      config.host,
    )).writeAsString(jsonEncode(config.values));
  }

  Future<void> setDefault(RepositoryConfig config) async {
    defaultId = config.id;
    await SpUtil.putString('hero_default_repository', config.id);
    if (!config.spec.isPlugin) {
      Global.setPShost(config.host);
      await (await _activeFile(
        config.host,
      )).writeAsString(jsonEncode(config.values));
    }
    notifyListeners();
  }

  Future<RepositoryConfig> saveRepository(
    HostSpec spec,
    String name,
    Map<String, dynamic> values, {
    RepositoryConfig? existing,
  }) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后修改配置');
    final normalized = normalizeValues(spec, values);
    if (spec.isPlugin) {
      final config = await pluginManager.saveRepository(
        spec,
        name,
        normalized,
        existing: existing,
      );
      if (defaultId == null || config.id == defaultId) {
        await setDefault(config);
      }
      await loadRepositories();
      return repositories.firstWhere((item) => item.id == config.id);
    }
    final Map slots = await ConfigureStoreFile().readConfigureFile(spec.id);
    final slot =
        existing?.slot ??
        slots.keys
            .cast<String>()
            .where(
              (key) => ConfigureStoreFile().checkIfOneUndetermined(slots[key]),
            )
            .firstOrNull;
    if (slot == null) throw const HeroFailure('该图床的 26 组配置已满');
    if (spec.id == 'alist') {
      if (normalized['token'] == 'None') {
        if (normalized['alistusername'] == 'None' ||
            normalized['password'] == 'None') {
          throw const HeroFailure('请填写 OpenList Token，或填写用户名与密码');
        }
        final result = await AlistManageAPI().getToken(
          normalized['host'],
          normalized['alistusername'],
          normalized['password'],
        );
        if (result[0] != 'success') {
          throw const HeroFailure('OpenList 登录失败，请检查用户名和密码');
        }
        normalized['token'] = result[1];
      }
      if (normalized['adminToken'] == 'None') {
        normalized['adminToken'] = normalized['token'];
      }
    }
    await ConfigureStoreFile().updateConfigureFileKey(spec.id, slot, {
      ...normalized,
      'remarkName': name.trim(),
    });
    final config = RepositoryConfig(
      host: spec.id,
      slot: slot,
      name: name.trim(),
      values: normalized,
    );
    if (defaultId == null || config.id == defaultId) await setDefault(config);
    await loadRepositories();
    return config;
  }

  Future<void> deleteRepository(RepositoryConfig config) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后删除配置');
    if (config.spec.isPlugin) {
      await pluginManager.deleteRepository(config);
      await loadRepositories();
      if (defaultId != null && repositories.isNotEmpty) {
        await setDefault(repositories.firstWhere((r) => r.id == defaultId));
      }
      return;
    }
    await ConfigureStoreFile().resetConfigureFileKey(config.host, config.slot);
    final active = await _activeFile(config.host);
    if (await active.exists() &&
        _sameConfig(
          config.values,
          Map<String, dynamic>.from(jsonDecode(await active.readAsString())),
        )) {
      await active.writeAsString('');
    }
    await loadRepositories();
    if (defaultId != null) {
      await setDefault(repositories.firstWhere((r) => r.id == defaultId));
    }
  }

  Future<void> loadImages() async {
    final entries = <AlbumEntry>[];
    for (final host in hostToTableNameMap.entries) {
      final db = host.value.startsWith('PBhostExtend')
          ? Global.imageDBExtend
          : Global.imageDB;
      if (db == null) continue;
      for (final row in await db.query(host.value, orderBy: 'id DESC')) {
        final meta = _metadata['${host.key}:${row['id']}'] as Map?;
        entries.add(
          AlbumEntry(
            row,
            host.key,
            uploadedAt: DateTime.tryParse(meta?['time'] ?? ''),
            repositoryId: meta?['repository'],
          ),
        );
      }
    }
    if (Global.imageDBExtend != null &&
        await AlbumSQL.isTableExist(Global.imageDBExtend!, pluginAlbumTable)) {
      for (final row in await Global.imageDBExtend!.query(
        pluginAlbumTable,
        orderBy: 'id DESC',
      )) {
        final host = row['PBhost']?.toString() ?? '';
        if (host.isEmpty) continue;
        final meta = _metadata['$host:${row['id']}'] as Map?;
        entries.add(
          AlbumEntry(
            row,
            host,
            uploadedAt: DateTime.tryParse(meta?['time'] ?? ''),
            repositoryId: meta?['repository'],
          ),
        );
      }
    }
    entries.sort(
      (a, b) => (b.uploadedAt ?? DateTime(1970)).compareTo(
        a.uploadedAt ?? DateTime(1970),
      ),
    );
    images = entries;
    // Old databases have no cross-provider timestamps; show latest only when known.
    latest = entries.where((e) => e.uploadedAt != null).firstOrNull;
    notifyListeners();
  }

  Future<List<AlbumEntry>> uploadFiles(
    List<String> paths, {
    RepositoryConfig? destination,
  }) => _uploadFiles(paths, destination: destination);

  Future<List<AlbumEntry>> _uploadFiles(
    List<String> paths, {
    RepositoryConfig? destination,
    bool insideMigration = false,
  }) async {
    if (busy && !insideMigration) throw const HeroFailure('已有上传任务正在进行');
    final config = destination ?? target;
    if (config == null) throw const HeroFailure('请先在仓库添加一个图床');
    busy = true;
    if (!insideMigration) progress = 0;
    failure = null;
    failedPath = null;
    notifyListeners();
    final completed = <AlbumEntry>[];
    final failed = <String>[];
    Object? lastError;
    StackTrace? lastStack;
    try {
      for (var i = 0; i < paths.length; i++) {
        var file = File(paths[i]);
        var name = p.basename(file.path);
        activity = '正在上传 ${i + 1}/${paths.length} · $name';
        notifyListeners();
        try {
          if (Global.isCustomRename) {
            name = await renamePictureWithCustomFormat(file);
          } else if (Global.isTimeStamp) {
            name = renamePictureWithTimestamp(file);
          } else if (Global.isRandomName) {
            name = renamePictureWithRandomString(file);
          }
          if (Global.isCompress) {
            file = await compressAndGetFile(
              file.path,
              name,
              Global.defaultCompressFormat,
              minHeight: Global.minHeight,
              minWidth: Global.minWidth,
              quality: Global.quality,
            );
            name = '${p.withoutExtension(name)}${p.extension(file.path)}';
          }
          final dynamic result = uploadOverride != null
              ? await uploadOverride!(
                  config.host,
                  file.path,
                  name,
                  Map.from(config.values),
                )
              : await uploaderRegistry.upload(
                  config.host,
                  path: file.path,
                  name: name,
                  config: Map<String, dynamic>.from(config.values),
                  configurationId: config.id,
                );
          if (result is! List || result.isEmpty || result[0] != 'success') {
            throw const HeroFailure('图床拒绝上传，请检查配置或查看请求日志');
          }
          final row = <String, dynamic>{
            'path': file.path,
            'name': name,
            'url': result[2],
            'PBhost': config.host,
            'pictureKey': result[3],
          };
          final table = _albumTable(config.host);
          final extended = table.startsWith('PBhostExtend');
          for (var j = 0; j < (extended ? 26 : 5); j++) {
            row['hostSpecificArg${String.fromCharCode(65 + j)}'] = 'test';
          }
          for (var j = 4; j < result.length && j < 30; j++) {
            row['hostSpecificArg${String.fromCharCode(65 + j - 4)}'] =
                result[j];
          }
          final db = extended ? Global.imageDBExtend : Global.imageDB;
          if (db == null) throw const HeroFailure('相册数据库未就绪');
          final id = await AlbumSQL.insertData(db, table, row);
          row['id'] = id;
          final now = DateTime.now();
          _metadata['${config.host}:$id'] = {
            'time': now.toUtc().toIso8601String(),
            'repository': config.id,
          };
          final entry = AlbumEntry(
            row,
            config.host,
            uploadedAt: now,
            repositoryId: config.id,
          );
          images.insert(0, entry);
          latest = entry;
          completed.add(entry);
        } catch (e, stack) {
          lastError = e;
          lastStack = stack;
          failed.add(name);
          failedPath = paths[i];
          failure = describeError('上传 $name', e, stack);
        }
        if (!insideMigration) progress = (i + 1) / paths.length;
        notifyListeners();
      }
      if (_metadataFile != null) {
        await _metadataFile!.writeAsString(jsonEncode(_metadata));
      }
      if (!insideMigration && Global.isCopyLink && completed.isNotEmpty) {
        await Clipboard.setData(
          ClipboardData(
            text: completed
                .map((e) => getFormatedUrl(e.url, e.name))
                .join('\n'),
          ),
        );
      }
      if (failed.isNotEmpty) {
        if (insideMigration && lastError != null) {
          Error.throwWithStackTrace(lastError, lastStack!);
        }
        throw HeroFailure(
          '${completed.length} 张成功，${failed.length} 张失败。${failure ?? ''}',
        );
      }
      return completed;
    } finally {
      if (!insideMigration) {
        busy = false;
        activity = '';
      }
      notifyListeners();
    }
  }

  Future<MarkdownMigrationResult> migrateMarkdown(
    String text,
    RepositoryConfig destination,
    MigrationCancellation cancellation, {
    MarkdownMigrator? migrator,
  }) async {
    if (busy) throw const HeroFailure('已有上传任务正在进行');
    final config = RepositoryConfig(
      host: destination.host,
      slot: destination.slot,
      name: destination.name,
      values: Map.unmodifiable(destination.values),
    );
    busy = true;
    progress = 0;
    failure = null;
    activity = '正在读取 Markdown 图片链接';
    notifyListeners();
    try {
      final root = await getApplicationDocumentsDirectory();
      final result = await (migrator ?? MarkdownMigrator()).migrate(
        text,
        imageDirectory: Directory(
          '${root.path}/markdown-images/${DateTime.now().microsecondsSinceEpoch}',
        ),
        cancellation: cancellation,
        targetId: config.id,
        upload: (file) async {
          final entries = await _uploadFiles(
            [file.path],
            destination: config,
            insideMigration: true,
          );
          return entries.single.url;
        },
        onProgress: (done, total, phase, url) {
          activity = '$phase ${done + (done < total ? 1 : 0)}/$total';
          progress = total == 0 ? 0 : done / total;
          notifyListeners();
        },
      );
      failure = result.issues.isEmpty
          ? null
          : '${result.issues.length} 张图片迁移失败，原链接已保留';
      return result;
    } finally {
      busy = false;
      activity = '';
      failedPath = null;
      notifyListeners();
    }
  }

  static Uri imageUri(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const HeroFailure('请输入有效的 HTTP 或 HTTPS 图片链接');
    }
    return uri;
  }

  Future<List<AlbumEntry>> uploadLinks(String input) async {
    if (busy) throw const HeroFailure('已有上传任务正在进行');
    if (target == null) throw const HeroFailure('请先在仓库添加一个图床');
    final urls = input
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .map(imageUri)
        .toList();
    if (urls.isEmpty) throw const HeroFailure('请至少填写一个图片链接');
    busy = true;
    progress = 0;
    activity = '正在下载链接中的图片';
    notifyListeners();
    final paths = <String>[];
    final cancel = CancelToken();
    try {
      final dir = await getTemporaryDirectory();
      for (var i = 0; i < urls.length; i++) {
        final response = await Dio(setBaseOptions()).get<List<int>>(
          urls[i].toString(),
          cancelToken: cancel,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (count, total) {
            if (count > 50 * 1024 * 1024) cancel.cancel('图片超过 50 MB');
          },
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
          throw const HeroFailure('图片为空或超过 50 MB');
        }
        final contentType = response.headers
            .value('content-type')
            ?.split(';')
            .first;
        if (!(contentType?.startsWith('image/') ?? false) &&
            !_imageMagic(bytes)) {
          throw const HeroFailure('链接返回的内容不是图片');
        }
        var name = p.basename(urls[i].path);
        if (name.isEmpty || p.extension(name).isEmpty) {
          name = 'image.${switchExtension(contentType)}';
        }
        name = name.replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]'), '_');
        final folder = Directory(
          '${dir.path}/picora-links/${DateTime.now().microsecondsSinceEpoch}',
        );
        await folder.create(recursive: true);
        final file = File('${folder.path}/$name');
        await file.writeAsBytes(bytes);
        paths.add(file.path);
        progress = (i + 1) / urls.length;
        notifyListeners();
      }
    } catch (e, stack) {
      failure = describeError('链接下载', e, stack);
      rethrow;
    } finally {
      busy = false;
      activity = '';
      notifyListeners();
    }
    return uploadFiles(paths);
  }

  static bool _imageMagic(List<int> b) =>
      b.length > 12 &&
      ((b[0] == 0xFF && b[1] == 0xD8) ||
          (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) ||
          (String.fromCharCodes(b.take(3)) == 'GIF') ||
          (String.fromCharCodes(b.take(4)) == 'RIFF' &&
              String.fromCharCodes(b.skip(8).take(4)) == 'WEBP'));
  static String switchExtension(String? type) =>
      {
        'image/jpeg': 'jpg',
        'image/png': 'png',
        'image/gif': 'gif',
        'image/webp': 'webp',
        'image/avif': 'avif',
      }[type] ??
      'png';

  Future<void> removeImages(List<AlbumEntry> entries) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后删除图片');
    for (final entry in entries) {
      if (Global.isDeleteCloud) {
        final isPlugin = entry.host.startsWith('plugin.');
        final config =
            repositories
                .where(
                  (r) => r.id == entry.repositoryId && r.host == entry.host,
                )
                .firstOrNull ??
            (isPlugin
                ? null
                : repositories.where((r) => r.host == entry.host).firstOrNull);
        if (isPlugin && config == null) {
          throw const HeroFailure('原插件配置组已不存在，无法删除云端图片；上传记录已保留');
        }
        final result = await uploaderRegistry.delete(
          entry.host,
          deleteMap: entry.row,
          config: config?.values ?? {},
          configurationId: config?.id,
          allowCloudDelete:
              !isPlugin ||
              pluginManager.isCloudDeleteAllowed(entry.host.substring(7)),
        );
        if (result is! List || result.firstOrNull != 'success') {
          throw const HeroFailure('云端删除失败，上传记录已保留');
        }
      }
      if (Global.isDeleteLocal &&
          entry.path.isNotEmpty &&
          await File(entry.path).exists()) {
        await File(entry.path).delete();
      }
      final table = _albumTable(entry.host);
      await AlbumSQL.deleteData(
        table.startsWith('PBhostExtend')
            ? Global.imageDBExtend!
            : Global.imageDB!,
        table,
        entry.row['id'],
      );
      _metadata.remove(entry.id);
      images.removeWhere((e) => e.id == entry.id);
      if (latest?.id == entry.id) {
        latest = images.where((e) => e.uploadedAt != null).firstOrNull;
      }
      notifyListeners();
    }
    if (_metadataFile != null) {
      await _metadataFile!.writeAsString(jsonEncode(_metadata));
    }
  }

  Future<void> clearHistory() async {
    if (busy) throw const HeroFailure('上传进行中，请稍后清空记录');
    for (final host in hostToTableNameMap.entries) {
      final db = host.value.startsWith('PBhostExtend')
          ? Global.imageDBExtend
          : Global.imageDB;
      if (db != null) await db.delete(host.value);
    }
    if (Global.imageDBExtend != null &&
        await AlbumSQL.isTableExist(Global.imageDBExtend!, pluginAlbumTable)) {
      await Global.imageDBExtend!.delete(pluginAlbumTable);
    }
    images.clear();
    _metadata.clear();
    latest = null;
    if (_metadataFile != null) await _metadataFile!.writeAsString('{}');
    notifyListeners();
  }

  void receiveSharedPaths(List<String> paths) {
    pendingSharedPaths = {...pendingSharedPaths, ...paths}.toList();
    notifyListeners();
  }

  void clearSharedPaths() {
    pendingSharedPaths.clear();
    notifyListeners();
  }

  void setContinuousCamera(bool value) {
    continuousCamera = value;
    SpUtil.putBool('hero_continuous_camera', value);
    notifyListeners();
  }

  Future<void> setTheme(String choice) async {
    if (!['light', 'system', 'dark'].contains(choice)) {
      throw const HeroFailure('不支持的主题选项');
    }
    if (await SpUtil.putString('hero_theme', choice) != true) {
      throw const HeroFailure('主题偏好保存失败，请重试');
    }
    themeChoice = choice;
    notifyListeners();
  }

  Future<PluginInstallResult> installPlugin(String source) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后安装插件');
    final result = await pluginManager.install(source);
    await loadRepositories();
    return result;
  }

  Future<PluginInstallResult> installPluginPackage(List<int> bytes) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后安装插件');
    final result = await pluginManager.installPackage(bytes);
    await loadRepositories();
    return result;
  }

  Future<void> setPluginEnabled(String id, bool enabled) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后修改插件');
    await pluginManager.setEnabled(id, enabled);
    notifyListeners();
  }

  Future<void> setPluginCloudDelete(String id, bool allowed) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后修改插件权限');
    await pluginManager.setCloudDeleteAllowed(id, allowed);
    notifyListeners();
  }

  Future<void> removePlugin(String id) async {
    if (busy) throw const HeroFailure('上传进行中，请稍后卸载插件');
    await pluginManager.remove(id);
    await loadRepositories();
    await loadImages();
  }

  String _albumTable(String host) =>
      host == 'picgo' || host.startsWith('plugin.')
      ? pluginAlbumTable
      : hostToTableNameMap[host] ?? pluginAlbumTable;
}
