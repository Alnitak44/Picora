import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ZLibDecoder;

import '../diagnostics.dart';
import '../models.dart';
import 'plugin_manifest.dart';
import 'plugin_protocol.dart';

/// ZIP files stay in app storage; assets are read in memory, never extracted.
class PicoraPluginPackage {
  static const maxZipBytes = 10 * 1024 * 1024;
  static const maxExpandedBytes = 20 * 1024 * 1024;
  static const maxFileBytes = 2 * 1024 * 1024;
  final PicoraPluginManifest manifest;
  final Map<String, dynamic> metadata;
  final Map<String, Uint8List> files;
  final Uint8List bytes;

  PicoraPluginPackage._(this.manifest, this.metadata, this.files, this.bytes);

  String get readme => utf8.decode(files['readme.md']!);
  String? get repository => metadata['repository'] as String?;
  String? get icon => metadata['icon'] as String?;

  HostSpec toHostSpec() => manifest.toHostSpec(
    iconBytes: icon == null ? null : files[icon],
    iconFormat: icon?.split('.').last.toLowerCase(),
  );

  Uint8List? resource(String path) {
    if (!validPath(path) || !path.startsWith('assets/')) return null;
    return files[path];
  }

  static bool validPath(String path) =>
      path.isNotEmpty &&
      path.length <= 240 &&
      !RegExp(r'[\\:\x00-\x1f\x7f]').hasMatch(path) &&
      !path.startsWith('/') &&
      path
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');

  factory PicoraPluginPackage.decode(List<int> source) {
    try {
      if (source.isEmpty || source.length > maxZipBytes) {
        throw const HeroFailure('插件 ZIP 不能为空，且不能超过 10 MB');
      }
      final directory = ZipDirectory()..read(InputMemoryStream(source));
      if (directory.fileHeaders.isEmpty || directory.fileHeaders.length > 128) {
        throw const HeroFailure('插件 ZIP 最多包含 128 个条目');
      }
      final names = <String>{};
      final files = <String, Uint8List>{};
      var total = 0;
      // Validate every header before decompressing any entry.
      for (final header in directory.fileHeaders) {
        final directoryEntry = header.filename.endsWith('/');
        final path = directoryEntry
            ? header.filename.substring(0, header.filename.length - 1)
            : header.filename;
        final fileType = (header.externalFileAttributes >> 16) & 0xf000;
        if (!validPath(path) ||
            !names.add(path.toLowerCase()) ||
            (fileType != 0 && fileType != 0x8000 && fileType != 0x4000)) {
          throw const HeroFailure('插件 ZIP 包含非法路径、重复条目或链接文件');
        }
        final local = header.file;
        if (local == null ||
            local.filename != header.filename ||
            header.generalPurposeBitFlag & 1 != 0 ||
            local.flags & 1 != 0 ||
            ![0, 8].contains(header.compressionMethod)) {
          throw const HeroFailure('插件 ZIP 损坏、加密或使用了不支持的压缩方式');
        }
        if (header.uncompressedSize > maxFileBytes ||
            local.uncompressedSize > maxFileBytes) {
          throw const HeroFailure('插件包中的单个文件不能超过 2 MB');
        }
        total += header.uncompressedSize;
        if (total > maxExpandedBytes) {
          throw const HeroFailure('插件解压后的总大小不能超过 20 MB');
        }
      }
      for (final header in directory.fileHeaders) {
        if (header.filename.endsWith('/')) continue;
        final raw = header.file!.getRawContent();
        final sink = _LimitedBytesSink(maxFileBytes);
        if (header.compressionMethod == 8) {
          final decoder = ZLibDecoder(raw: true).startChunkedConversion(sink);
          // Small input chunks bound output before accumulating it in memory.
          for (var offset = 0; offset < raw.length; offset += 1024) {
            decoder.add(
              raw.sublist(offset, (offset + 1024).clamp(0, raw.length)),
            );
          }
          decoder.close();
        } else {
          sink.add(raw);
          sink.close();
        }
        final data = sink.bytes;
        if (data.length != header.uncompressedSize ||
            getCrc32(data) != header.crc32) {
          throw const HeroFailure('插件 ZIP 文件大小或校验和不正确');
        }
        files[header.filename] = data;
      }
      if (!directory.fileHeaders.any(
        (header) =>
            header.filename == 'assets/' ||
            header.filename.startsWith('assets/'),
      )) {
        throw const HeroFailure('插件需要 assets/ 资源目录，可以为空');
      }
      Map<String, dynamic> jsonFile(String name) {
        final data = files[name];
        if (data == null || data.length > 1024 * 1024) {
          throw HeroFailure('插件缺少 $name，或文件超过 1 MB');
        }
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is! Map<String, dynamic>) {
          throw HeroFailure('$name 必须是 JSON 对象');
        }
        return decoded;
      }

      final metadata = jsonFile('plugin.json');
      if (metadata['packageVersion'] != 1 ||
          !pluginRuntimes.containsKey(metadata['runtime'])) {
        throw const HeroFailure(
          '插件需要 packageVersion: 1 和受支持的 http-v1 / http-v2',
        );
      }
      final entry = metadata['entry'];
      if (entry is! String ||
          !validPath(entry) ||
          !entry.endsWith('.json') ||
          entry == 'plugin.json' ||
          entry.startsWith('assets/')) {
        throw const HeroFailure('插件 entry 必须指向包内的 JSON 程序文件');
      }
      final program = jsonFile(entry);
      if (program['schemaVersion'] != pluginRuntimes[metadata['runtime']]) {
        throw const HeroFailure('runtime 与 schemaVersion 不匹配，请升级客户端或修正插件');
      }
      final readme = files['readme.md'];
      if (readme == null ||
          readme.isEmpty ||
          readme.length > 512 * 1024 ||
          utf8.decode(readme).trim().isEmpty) {
        throw const HeroFailure('插件需要非空的 UTF-8 readme.md，最多 512 KB');
      }
      for (final key in ['homepage', 'repository']) {
        final value = metadata[key];
        if (value == null) continue;
        final uri = value is String ? Uri.tryParse(value) : null;
        if (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw HeroFailure('插件 $key 必须是 HTTP/HTTPS 地址');
        }
      }
      final icon = metadata['icon'];
      if (icon != null &&
          (icon is! String ||
              !validPath(icon) ||
              !icon.startsWith('assets/') ||
              !files.containsKey(icon) ||
              !RegExp(
                r'\.(png|jpg|jpeg|webp|gif|svg)$',
                caseSensitive: false,
              ).hasMatch(icon))) {
        throw const HeroFailure('插件 icon 必须指向 assets/ 中的图片');
      }
      final manifest = PicoraPluginManifest.fromJson(
        {
          ...program,
          for (final key in [
            'id',
            'name',
            'version',
            'description',
            'author',
            'homepage',
            'mark',
            'color',
          ])
            key: metadata[key],
        },
        resources: Map.unmodifiable({
          for (final entry in files.entries)
            if (entry.key.startsWith('assets/')) entry.key: entry.value,
        }),
      );
      return PicoraPluginPackage._(
        manifest,
        Map.unmodifiable(metadata),
        Map.unmodifiable(files),
        Uint8List.fromList(source),
      );
    } on HeroFailure {
      rethrow;
    } catch (error) {
      throw HeroFailure('无法读取插件 ZIP：$error');
    }
  }

  /// Wrap pre-ZIP installed manifests without changing provider/config IDs.
  factory PicoraPluginPackage.fromLegacy(PicoraPluginManifest manifest) {
    final original = manifest.toJson();
    final metadata = <String, dynamic>{
      'packageVersion': 1,
      'runtime': 'http-v${manifest.schemaVersion}',
      'entry': 'uploader.json',
      for (final key in [
        'id',
        'name',
        'version',
        'description',
        'author',
        'homepage',
        'mark',
        'color',
      ])
        if (original[key] != null) key: original[key],
    };
    final program = <String, dynamic>{
      'schemaVersion': manifest.schemaVersion,
      for (final key in [
        'permissions',
        'config',
        'upload',
        'delete',
        'prepare',
        'requires',
      ])
        if (original[key] != null) key: original[key],
    };
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'plugin.json',
          const JsonEncoder.withIndent('  ').convert(metadata),
        ),
      )
      ..add(
        ArchiveFile.string(
          'uploader.json',
          const JsonEncoder.withIndent('  ').convert(program),
        ),
      )
      ..add(
        ArchiveFile.string(
          'readme.md',
          '# ${manifest.name}\n\n${manifest.description}\n\n'
              '此插件由旧版清单自动迁移。原文件未提供使用教程。\n\n'
              '在图床列表选择此图床，按字段提示添加配置后即可上传。'
              '${manifest.homepage == null ? '' : '\n\n[项目主页](${manifest.homepage})'}\n',
        ),
      )
      ..add(ArchiveFile.directory('assets/'));
    return PicoraPluginPackage.decode(ZipEncoder().encode(archive));
  }
}

class _LimitedBytesSink implements Sink<List<int>> {
  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  _LimitedBytesSink(this.limit);
  Uint8List get bytes => _builder.takeBytes();
  @override
  void add(List<int> data) {
    if (_builder.length + data.length > limit) {
      throw const HeroFailure('插件文件实际解压大小超过 2 MB');
    }
    _builder.add(data);
  }

  @override
  void close() {}
}
