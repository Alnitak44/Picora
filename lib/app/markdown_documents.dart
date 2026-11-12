import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'diagnostics.dart';

class MarkdownSourceFile {
  final String uri, name;
  final Uint8List bytes;
  const MarkdownSourceFile(this.uri, this.name, this.bytes);
  bool get bom =>
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  String get text {
    try {
      return utf8.decode(bom ? bytes.sublist(3) : bytes);
    } on FormatException {
      throw const HeroFailure('Markdown 文件需要使用 UTF-8 编码，请转换编码后重试');
    }
  }

  Uint8List encode(String text) => Uint8List.fromList([
    if (bom) ...[0xef, 0xbb, 0xbf],
    ...utf8.encode(text),
  ]);
}

class MarkdownDocumentService {
  static const channel = MethodChannel('io.github.alnitak44.picora/documents');
  String? backupPath;
  Future<MarkdownSourceFile?> pick() async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'pickMarkdown',
      );
      if (result == null) return null;
      final document = MarkdownSourceFile(
        result['uri'] as String,
        result['name'] as String,
        result['bytes'] as Uint8List,
      );
      document
          .text; // Validate encoding before downloading or uploading anything.
      return document;
    } on PlatformException catch (error) {
      throw _failure(error);
    }
  }

  Future<String?> saveNew(String name, Uint8List bytes) async {
    try {
      return await channel.invokeMethod<String>('saveMarkdown', {
        'name': name,
        'bytes': bytes,
      });
    } on PlatformException catch (error) {
      throw _failure(error);
    }
  }

  Future<void> overwrite(MarkdownSourceFile original, Uint8List bytes) async {
    final root = await getApplicationSupportDirectory();
    final dir = await Directory(
      '${root.path}/markdown-backups',
    ).create(recursive: true);
    final file = File('${dir.path}/${const Uuid().v4()}.md');
    await file.writeAsBytes(original.bytes, flush: true);
    backupPath = file.path;
    try {
      await channel.invokeMethod<void>('overwriteMarkdown', {
        'uri': original.uri,
        'bytes': bytes,
        'expectedMd5': md5.convert(original.bytes).toString(),
      });
    } on PlatformException catch (error) {
      throw HeroFailure('${_failure(error).message}。原文备份已保留，可从此页面导出');
    }
  }

  HeroFailure _failure(PlatformException error) {
    HeroDiagnostics.instance.record(
      'Markdown 系统文件操作',
      error,
      stack: StackTrace.current,
      context: {'nativeCode': error.code, 'nativeDetails': error.details},
    );
    return HeroFailure(switch (error.code) {
      'DOCUMENT_CHANGED' => '原文件已被其他程序修改，未覆盖，请重新选择文件或另存新文件',
      'FILE_TOO_LARGE' => 'Markdown 文件超过 10 MB，或输出超过 20 MB',
      'INVALID_MARKDOWN' => '请选择 .md 或 .markdown 文件',
      'PERMISSION_DENIED' => '没有文件读写权限，请重新选择文件或另存新文件',
      'WRITE_FAILED' => '保存失败，请检查文件权限、存储空间或云盘连接',
      'RESTORE_FAILED' => '保存失败且无法确认原文件已恢复，请导出原文备份恢复文件',
      'NO_DOCUMENT_PROVIDER' => '没有可用的系统文档选择器',
      _ => '系统文件操作失败（${error.code}）',
    });
  }
}
