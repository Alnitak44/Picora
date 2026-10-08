import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:picora/utils/common_functions.dart';
import 'diagnostics.dart';
import 'markdown_images.dart';

class MigrationCancellation {
  bool cancelled = false;
  CancelToken? request;
  void cancel() {
    cancelled = true;
    request?.cancel('已停止任务');
  }
}

class MarkdownMigrationIssue {
  final String url, phase, message, diagnosticId;
  final Map<String, dynamic> diagnostics;
  const MarkdownMigrationIssue(
    this.url,
    this.phase,
    this.message,
    this.diagnosticId, {
    this.diagnostics = const {},
  });
}

class MarkdownMigrationResult {
  final MarkdownImageDocument document;
  final Map<String, String> replacements;
  final List<MarkdownMigrationIssue> issues;
  final bool cancelled;
  const MarkdownMigrationResult(
    this.document,
    this.replacements,
    this.issues,
    this.cancelled,
  );
  int get total => document.remoteUris.length;
  int get successful => replacements.length;
  int get remaining => total - successful - issues.length;
  int get skipped => document.images.where((e) => e.uri == null).length;
  int get replacedOccurrences => document.images
      .where((e) => replacements.containsKey(e.uri?.toString()))
      .length;
  String get text => document.replace(replacements);
  String report() => [
    'Picora Markdown 图床替换报告',
    '远程图片 $total，上传成功 $successful，失败 ${issues.length}，未处理 $remaining；非 HTTP/HTTPS 图片 $skipped。',
    '已替换 $replacedOccurrences 处图片引用。失败和未处理的链接保留原样。',
    for (final issue in issues)
      '\n${issue.phase}：${HeroDiagnostics.redact(issue.url)}\n${HeroDiagnostics.redact(issue.message)}\n诊断编号：${issue.diagnosticId}\n${const JsonEncoder.withIndent('  ').convert(issue.diagnostics)}',
  ].join('\n');
}

typedef MigrationUpload = Future<String> Function(File file);
typedef MigrationProgress =
    void Function(int completed, int total, String phase, String url);

class MarkdownImageDownloader {
  static const maxImageBytes = 50 * 1024 * 1024;
  final Dio dio;
  final int maxBytes;
  final Duration timeout;
  MarkdownImageDownloader({
    Dio? dio,
    this.maxBytes = maxImageBytes,
    this.timeout = const Duration(seconds: 45),
  }) : dio = dio ?? Dio(setBaseOptions());

  Future<File> download(
    Uri uri,
    Directory folder,
    MigrationCancellation cancellation,
  ) async {
    if (cancellation.cancelled) throw const HeroFailure('任务已停止');
    final token = CancelToken();
    cancellation.request = token;
    final timer = Timer(timeout, () => token.cancel('图片下载超时'));
    RandomAccessFile? output;
    final partial = File('${folder.path}/download.part');
    try {
      await folder.create(recursive: true);
      final response = await dio.get<ResponseBody>(
        uri.toString(),
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 15),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final body = response.data;
      if (body == null) throw const HeroFailure('图片链接返回了空内容');
      final advertised = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (advertised != null && advertised > maxBytes) {
        throw const HeroFailure('图片超过 50 MB');
      }
      final header = BytesBuilder();
      var received = 0;
      output = await partial.open(mode: FileMode.write);
      await for (final chunk in body.stream) {
        if (cancellation.cancelled) {
          token.cancel();
          throw const HeroFailure('任务已停止');
        }
        received += chunk.length;
        if (received > maxBytes) {
          token.cancel();
          throw const HeroFailure('图片超过 50 MB');
        }
        if (header.length < 1024) {
          header.add(chunk.take(1024 - header.length).toList());
        }
        await output.writeFrom(chunk);
      }
      await output.close();
      output = null;
      if (received == 0) throw const HeroFailure('图片链接返回了空内容');
      final prefix = header.takeBytes();
      final sniffedText = utf8.decode(prefix, allowMalformed: true).trimLeft();
      if (RegExp(
        r'^(?:<!doctype\s+html|<html\b|<head\b|<body\b|[\[{])',
        caseSensitive: false,
      ).hasMatch(sniffedText)) {
        throw const HeroFailure('链接返回了网页或错误信息，可能有登录、防盗链限制');
      }
      final contentType = response.headers
          .value('content-type')
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      var mime = lookupMimeType('download', headerBytes: prefix);
      if (RegExp(r'<svg\b', caseSensitive: false).hasMatch(sniffedText)) {
        mime = 'image/svg+xml';
      }
      mime ??= contentType?.startsWith('image/') == true ? contentType : null;
      if (mime == null || !mime.startsWith('image/')) {
        throw const HeroFailure('链接内容不是可识别的图片');
      }
      final extension = switch (mime) {
        'image/jpeg' => '.jpg',
        'image/png' => '.png',
        'image/gif' => '.gif',
        'image/webp' => '.webp',
        'image/svg+xml' => '.svg',
        'image/avif' => '.avif',
        'image/heic' => '.heic',
        'image/heif' => '.heif',
        'image/bmp' => '.bmp',
        'image/tiff' => '.tiff',
        _ => '.img',
      };
      var basename = p
          .basenameWithoutExtension(uri.path)
          .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
      if (basename.isEmpty ||
          basename == '.' ||
          basename == '..' ||
          utf8.encode(basename).length > 160) {
        basename = 'image';
      }
      return await partial.rename('${folder.path}/$basename$extension');
    } finally {
      timer.cancel();
      if (identical(cancellation.request, token)) cancellation.request = null;
      if (output != null) await output.close();
      if (await partial.exists()) await partial.delete();
    }
  }
}

class MarkdownMigrator {
  final MarkdownImageDownloader downloader;
  MarkdownMigrator({MarkdownImageDownloader? downloader})
    : downloader = downloader ?? MarkdownImageDownloader();
  Future<MarkdownMigrationResult> migrate(
    String text, {
    required Directory imageDirectory,
    required MigrationUpload upload,
    required MigrationCancellation cancellation,
    String? targetId,
    MigrationProgress? onProgress,
  }) async {
    final document = await MarkdownImageDocument.parseAsync(text);
    final urls = document.remoteUris;
    if (urls.isEmpty) {
      throw const HeroFailure('未找到 HTTP / HTTPS 图片链接；本地图片和代码示例不会迁移');
    }
    if (urls.length > 1000) {
      throw const HeroFailure('一次最多迁移 1000 张不同的远程图片，请拆分 Markdown 文件');
    }
    final replacements = <String, String>{};
    final issues = <MarkdownMigrationIssue>[];
    for (var i = 0; i < urls.length; i++) {
      if (cancellation.cancelled) break;
      final uri = urls[i];
      var phase = '下载图片';
      File? downloaded;
      try {
        onProgress?.call(i, urls.length, phase, uri.toString());
        downloaded = await downloader.download(
          uri,
          Directory('${imageDirectory.path}/$i'),
          cancellation,
        );
        if (cancellation.cancelled) {
          await downloaded.delete();
          break;
        }
        phase = '上传图片';
        onProgress?.call(i, urls.length, phase, uri.toString());
        final url = await upload(downloaded);
        final next = Uri.tryParse(url);
        if (next == null ||
            !['http', 'https'].contains(next.scheme) ||
            next.host.isEmpty) {
          throw const HeroFailure('图床返回了无效的图片链接');
        }
        replacements[uri.toString()] = next.toString();
      } catch (error, stack) {
        if (cancellation.cancelled) break;
        final id = HeroDiagnostics.instance.record(
          'Markdown 图床替换 · $phase',
          error,
          stack: stack,
          context: {
            'sourceUrl': uri.toString(),
            'targetRepository': targetId,
            'imageIndex': i + 1,
          },
        );
        final details = HeroDiagnostics.instance.entries.firstWhere(
          (entry) => entry['id'] == id,
        );
        issues.add(
          MarkdownMigrationIssue(
            uri.toString(),
            phase,
            migrationErrorMessage(error),
            id,
            diagnostics: Map.unmodifiable(details),
          ),
        );
        if (downloaded != null && await downloaded.exists()) {
          await downloaded.delete();
        }
      } finally {
        onProgress?.call(i + 1, urls.length, '处理图片', uri.toString());
      }
    }
    return MarkdownMigrationResult(
      document,
      Map.unmodifiable(replacements),
      List.unmodifiable(issues),
      cancellation.cancelled,
    );
  }
}

String migrationErrorMessage(Object error) {
  if (error is HeroFailure) return error.message;
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 404 || status == 410) return '图片链接已失效或被删除（HTTP $status）';
    if (status == 401 || status == 403) {
      return '图片拒绝访问，可能需要登录或受防盗链限制（HTTP $status）';
    }
    if (status == 429) return '请求过于频繁，请稍后再试（HTTP 429）';
    if (status != null) return '服务器返回错误（HTTP $status）';
    if ([
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ].contains(error.type)) {
      return '网络超时，图片服务可能已停止响应';
    }
    if (error.type == DioExceptionType.cancel) {
      return error.message?.contains('超时') == true ||
              (error.error is String && (error.error as String).contains('超时'))
          ? '图片下载超时，已停止等待'
          : '下载中断';
    }
    if (error.type == DioExceptionType.badCertificate) {
      return '图片服务的 HTTPS 证书无效';
    }
    if (error.type == DioExceptionType.connectionError) return '域名无法解析或网络连接失败';
    return '网络请求失败，请查看诊断记录';
  }
  if (error is FileSystemException) return '无法读写本地文件，请检查存储空间与权限';
  return '处理失败，请查看诊断记录';
}
