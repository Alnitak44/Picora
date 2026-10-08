import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A single redaction boundary for new UI and inherited provider errors.
class HeroDiagnostics extends ChangeNotifier {
  static final instance = HeroDiagnostics();
  final List<Map<String, dynamic>> entries = [];
  File? _file;
  Future<void> _writes = Future.value();
  static final _secret = RegExp(
    r'password|secret|token|authorization|cookie|credential|picturekey|keyid|accesskey',
    caseSensitive: false,
  );
  static Object? redact(Object? value, [String key = '']) {
    if (_secret.hasMatch(key)) return '[REDACTED]';
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), redact(v, k.toString())),
      );
    }
    if (value is Iterable) {
      return value.take(100).map((v) => redact(v)).toList();
    }
    if (value is String) {
      if (value.trimLeft().startsWith('{') ||
          value.trimLeft().startsWith('[')) {
        try {
          return redact(jsonDecode(value), key);
        } catch (_) {
          /* Not a JSON string. */
        }
      }
      final safe = value
          .replaceAllMapped(
            RegExp(r'(https?://)[^/@\s]+@', caseSensitive: false),
            (m) => '${m[1]}[REDACTED]@',
          )
          .replaceAll(
            RegExp(r'Bearer\s+[^\s,\]"}]+', caseSensitive: false),
            'Bearer [REDACTED]',
          )
          .replaceAllMapped(
            RegExp(
              r'([?&](?:token|key|signature|password|credential|x-amz-[^=]+)=)[^&\s]+',
              caseSensitive: false,
            ),
            (m) => '${m[1]}[REDACTED]',
          );
      return safe.length > 4000 ? '${safe.substring(0, 4000)}…' : safe;
    }
    if (value == null || value is num || value is bool) return value;
    return value.runtimeType.toString();
  }

  Future<void> initialize() async {
    if (_file != null) return;
    _file = File(
      '${(await getApplicationSupportDirectory()).path}/picora-diagnostics.jsonl',
    );
    await _file!.parent.create(recursive: true);
    if (await _file!.exists()) {
      for (final line in await _file!.readAsLines()) {
        try {
          entries.add(Map<String, dynamic>.from(jsonDecode(line)));
        } catch (_) {
          /* Ignore incomplete final line. */
        }
      }
      if (entries.length > 300) entries.removeRange(300, entries.length);
    }
    notifyListeners();
  }

  String record(
    String operation,
    Object error, {
    StackTrace? stack,
    Map<String, dynamic> context = const {},
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final data = <String, dynamic>{
      'id': id,
      'time': DateTime.now().toUtc().toIso8601String(),
      'operation': operation,
      'type': error.runtimeType.toString(),
      'context': redact(context),
      'stack': redact(stack?.toString()),
    };
    if (error is DioException) {
      data['network'] = {
        'method': error.requestOptions.method,
        'url': redact(error.requestOptions.uri.toString()),
        'status': error.response?.statusCode,
        'kind': error.type.name,
        'response': redact(error.response?.data),
        'message': redact(error.message),
      };
    } else if (error is Response) {
      data['network'] = {
        'method': error.requestOptions.method,
        'url': redact(error.requestOptions.uri.toString()),
        'status': error.statusCode,
        'response': redact(error.data),
      };
    } else if (error is FileSystemException) {
      data['filesystem'] = {
        'path': redact(error.path),
        'code': error.osError?.errorCode,
        'message': redact(error.osError?.message ?? error.message),
      };
    } else {
      // Never stringify arbitrary provider exceptions: they may contain credentials.
      data['message'] = error is HeroFailure
          ? redact(error.message)
          : '异常详情请结合上下文和堆栈查看';
    }
    entries.insert(0, data);
    if (entries.length > 300) entries.removeLast();
    _writes = _writes
        .then((_) async {
          if (_file != null) {
            await _file!.writeAsString(entries.map(jsonEncode).join('\n'));
          }
        })
        .catchError((Object _) {});
    notifyListeners();
    return id;
  }

  Future<File> export() async {
    await _writes;
    final file = File(
      '${(await getTemporaryDirectory()).path}/Picora-debug.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries),
    );
    return file;
  }

  Future<void> clear() async {
    await _writes;
    if (_file != null) await _file!.writeAsString('');
    entries.clear();
    notifyListeners();
  }
}

class HeroFailure implements Exception {
  final String message;
  const HeroFailure(this.message);
  @override
  String toString() => message;
}
