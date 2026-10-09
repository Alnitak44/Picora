import 'dart:convert';

import 'package:dio/dio.dart';

import 'diagnostics.dart';
import 'github_mirrors.dart';

class AppVersion implements Comparable<AppVersion> {
  final List<int> core;
  final List<String> prerelease;
  AppVersion._(this.core, this.prerelease);

  factory AppVersion.parse(String value, {bool ignoreDebugSuffix = false}) {
    var text = value.trim();
    if (ignoreDebugSuffix) {
      text = text.replaceFirst(RegExp(r'-debug(?=(?:\+.*)?$)'), '');
    }
    final match = RegExp(
      r'^[vV]?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(text);
    if (match == null) throw FormatException('无效版本号', value);
    final pre = match[4]?.split('.') ?? <String>[];
    if (pre.any(
      (p) => RegExp(r'^\d+$').hasMatch(p) && p.length > 1 && p.startsWith('0'),
    )) {
      throw FormatException('预发布版本数字不能有前导零', value);
    }
    return AppVersion._([
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    ], pre);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final result = core[i].compareTo(other.core[i]);
      if (result != 0) return result;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
      return prerelease.isEmpty ? 1 : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i], b = other.prerelease[i];
      final an = RegExp(r'^\d+$').hasMatch(a),
          bn = RegExp(r'^\d+$').hasMatch(b);
      final result = an && bn
          ? (a.length == b.length
                ? a.compareTo(b)
                : a.length.compareTo(b.length))
          : an != bn
          ? (an ? -1 : 1)
          : a.compareTo(b);
      if (result != 0) return result;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}

class ReleaseApk {
  final String name;
  final Uri url;
  final int size;
  final String? sha256;
  const ReleaseApk({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
}

class AppRelease {
  final String tag, notes;
  final Uri page;
  final AppVersion version;
  final List<ReleaseApk> apks;
  AppRelease._(this.tag, this.notes, this.page, this.version, this.apks);

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    if (json['draft'] == true || json['prerelease'] == true) {
      throw const HeroFailure('更新接口返回了非正式版本');
    }
    final tag = json['tag_name'];
    if (tag is! String) throw const HeroFailure('Release 缺少版本标签');
    final AppVersion version;
    try {
      version = AppVersion.parse(tag);
    } on FormatException {
      throw const HeroFailure('Release 标签需要使用 v1.0.0 格式');
    }
    if (version.prerelease.isNotEmpty) {
      throw const HeroFailure('正式 Release 使用了预发布版本号');
    }
    final page = _projectUri(json['html_url'], 'releases/tag/');
    if (page == null) throw const HeroFailure('Release 页面地址无效');
    final assets = json['assets'];
    if (assets is! List) throw const HeroFailure('Release 附件信息无效');
    final apks = <ReleaseApk>[];
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String ||
          !name.toLowerCase().endsWith('.apk') ||
          asset['state'] != 'uploaded') {
        continue;
      }
      final uri = _projectUri(
        asset['browser_download_url'],
        'releases/download/',
      );
      final size = asset['size'];
      if (uri == null || size is! int || size <= 0) {
        throw const HeroFailure('Release APK 的下载地址或大小无效');
      }
      String? checksum;
      final digest = asset['digest'];
      if (digest != null) {
        if (digest is! String ||
            !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
          throw const HeroFailure('Release APK 的 SHA-256 摘要无效');
        }
        checksum = digest.substring(7).toLowerCase();
      }
      apks.add(ReleaseApk(name: name, url: uri, size: size, sha256: checksum));
    }
    final notes = json['body'];
    return AppRelease._(tag, notes is String ? notes : '', page, version, apks);
  }

  bool isNewerThan(String installed) =>
      version.compareTo(AppVersion.parse(installed, ignoreDebugSuffix: true)) >
      0;

  ReleaseApk? apkFor(String abi) {
    final matches = apks.where((apk) {
      final name = apk.name.toLowerCase();
      return switch (abi) {
        'arm64-v8a' => name.contains('arm64'),
        'armeabi-v7a' => name.contains('armeabi-v7a') || name.contains('armv7'),
        'x86_64' => name.contains('x86_64') || name.contains('x64'),
        _ => false,
      };
    }).toList();
    if (matches.length == 1) return matches.single;
    if (matches.length > 1) return null;
    final universal = apks
        .where((apk) => apk.name.toLowerCase().contains('universal'))
        .toList();
    if (universal.length == 1) return universal.single;
    if (apks.length == 1 &&
        !RegExp(
          r'arm64|armeabi|armv7|x86|x64',
          caseSensitive: false,
        ).hasMatch(apks.single.name)) {
      return apks.single;
    }
    return null;
  }

  static Uri? _projectUri(Object? value, String suffix) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith('/Alnitak44/Picora/$suffix')) {
      return null;
    }
    return uri;
  }
}

class AppUpdateService {
  static const latestUrl =
      'https://api.github.com/repos/Alnitak44/Picora/releases/latest';
  final Dio dio;
  final DateTime Function() now;
  AppRelease? _cached;
  DateTime? _checkedAt;
  String? _etag;
  String? _route;
  AppUpdateService({Dio? dio, DateTime Function()? now})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ),
      now = now ?? DateTime.now;

  Future<AppRelease?> latest({bool forceRefresh = false}) async {
    final url = GitHubMirrors.instance
        .resolve(Uri.parse(latestUrl), headers: dio.options.headers)
        .toString();
    if (_route != url) {
      _route = url;
      _checkedAt = null;
      _etag = null;
      _cached = null;
    }
    if (!forceRefresh &&
        _checkedAt != null &&
        now().difference(_checkedAt!) < const Duration(hours: 6)) {
      return _cached;
    }
    final response = await dio.get<Object?>(
      url,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Picora',
          if (_etag != null) 'If-None-Match': _etag,
        },
        validateStatus: (status) =>
            status == 200 || status == 304 || status == 404,
      ),
    );
    if (response.statusCode == 304) {
      if (_checkedAt == null) throw const HeroFailure('更新接口返回了无缓存的响应');
      _checkedAt = now();
      return _cached;
    }
    if (response.statusCode == 404) {
      if (url != latestUrl) {
        throw const HeroFailure('镜像无法获取更新，请前往设置切换镜像后重试');
      }
      _cached = null;
      _etag = null;
    } else {
      Object? data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } on FormatException {
          throw const HeroFailure('更新接口返回了无效数据');
        }
      }
      if (data is! Map<String, dynamic>) throw const HeroFailure('更新接口返回了无效数据');
      final release = AppRelease.fromJson(data);
      _cached = release;
      _etag = response.headers.value('etag');
    }
    _checkedAt = now();
    return _cached;
  }
}
