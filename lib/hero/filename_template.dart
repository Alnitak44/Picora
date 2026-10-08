import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'diagnostics.dart';

class FilenameVariable {
  final String token, name, description, group;
  const FilenameVariable(this.token, this.name, this.description, this.group);
}

const filenameVariables = [
  FilenameVariable('{date}', '日期', '2026-10-06', '日期与时间'),
  FilenameVariable('{Y}', '四位年份', '2026；也支持 {year}', '日期与时间'),
  FilenameVariable('{y}', '两位年份', '26', '日期与时间'),
  FilenameVariable('{m}', '月份', '01–12；也支持 {month}', '日期与时间'),
  FilenameVariable('{d}', '日', '01–31；也支持 {day}', '日期与时间'),
  FilenameVariable('{h}', '小时', '00–23', '日期与时间'),
  FilenameVariable('{i}', '分钟', '00–59', '日期与时间'),
  FilenameVariable('{s}', '秒', '00–59', '日期与时间'),
  FilenameVariable('{ms}', '毫秒', '000–999', '日期与时间'),
  FilenameVariable('{timestamp}', '时间戳', '自 1970 年起的毫秒数', '日期与时间'),
  FilenameVariable('{filename}', '原文件名', '不含扩展名', '文件内容'),
  FilenameVariable('{md5}', '文件 MD5', '内容摘要，32 位十六进制', '文件内容'),
  FilenameVariable('{md5-16}', '短 MD5', '文件 MD5 的前 16 位', '文件内容'),
  FilenameVariable('{sha256}', '文件 SHA-256', '内容摘要，64 位十六进制', '文件内容'),
  FilenameVariable('{uuid}', 'UUID', '不含连字符的唯一字符串', '随机值'),
  FilenameVariable('{str-8}', '随机 8 位', '字母和数字；长度可改为 1–128', '随机值'),
  FilenameVariable('{str-16}', '随机 16 位', '每次上传重新生成', '随机值'),
];

String? validateFilenameTemplate(String template) {
  if (template.trim().isEmpty) return '请输入命名格式';
  if (template.length > 240) return '命名格式过长';
  if (RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(template)) {
    return '文件名不能包含路径分隔符或特殊字符';
  }
  final known = {
    ...filenameVariables.map((e) => e.token),
    '{year}',
    '{month}',
    '{day}',
  };
  for (final match in RegExp(r'\{[^{}]*\}').allMatches(template)) {
    final token = match.group(0)!;
    if (known.contains(token)) continue;
    final random = RegExp(r'^\{str-(\d+)\}$').firstMatch(token);
    final length = int.tryParse(random?.group(1) ?? '');
    if (length == null || length < 1 || length > 128) return '不支持的变量：$token';
  }
  if (RegExp(
    r'[{}]',
  ).hasMatch(template.replaceAll(RegExp(r'\{[^{}]*\}'), ''))) {
    return '变量的大括号没有配对';
  }
  return null;
}

Future<String> renderFilenameTemplate(
  File file,
  String template, {
  DateTime? now,
}) async {
  final error = validateFilenameTemplate(template);
  if (error != null) throw HeroFailure(error);
  final date = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final values = <String, String>{
    '{Y}': date.year.toString().padLeft(4, '0'),
    '{y}': two(date.year % 100),
    '{m}': two(date.month),
    '{d}': two(date.day),
    '{h}': two(date.hour),
    '{i}': two(date.minute),
    '{s}': two(date.second),
    '{ms}': date.millisecond.toString().padLeft(3, '0'),
    '{timestamp}': date.millisecondsSinceEpoch.toString(),
    '{filename}': p.basenameWithoutExtension(file.path),
  };
  values['{year}'] = values['{Y}']!;
  values['{month}'] = values['{m}']!;
  values['{day}'] = values['{d}']!;
  values['{date}'] = '${values['{Y}']}-${values['{m}']}-${values['{d}']}';
  if (template.contains('{md5}') || template.contains('{md5-16}')) {
    final hash = (await md5.bind(file.openRead()).first).toString();
    values['{md5}'] = hash;
    values['{md5-16}'] = hash.substring(0, 16);
  }
  if (template.contains('{sha256}')) {
    values['{sha256}'] = (await sha256.bind(file.openRead()).first).toString();
  }
  if (template.contains('{uuid}')) {
    values['{uuid}'] = const Uuid().v4().replaceAll('-', '');
  }
  final random = Random.secure();
  String randomString(int length) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  final name =
      template.trim().replaceAllMapped(RegExp(r'\{[^{}]*\}'), (match) {
        final token = match.group(0)!;
        if (values.containsKey(token)) return values[token]!;
        return randomString(int.parse(token.substring(5, token.length - 1)));
      }) +
      p.extension(file.path);
  if (utf8.encode(name).length > 240 || name == '.' || name == '..') {
    throw const HeroFailure('生成的文件名超过 240 字节，请缩短命名格式');
  }
  return name;
}
