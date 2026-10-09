import 'dart:convert';

import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:uuid/uuid.dart';

import 'diagnostics.dart';

class GitHubMirror {
  final String id, name;
  final String? baseUrl;
  final bool custom;
  const GitHubMirror(this.id, this.name, this.baseUrl, {this.custom = false});
}

/// Applied only at public download call sites, never to uploader traffic.
class GitHubMirrors {
  static const preferenceKey = 'picora_github_mirrors';
  static final instance = GitHubMirrors();
  static const presets = [
    GitHubMirror('direct', 'GitHub 直连', null),
    GitHubMirror('gh2i', 'gh.2i.gs', 'https://gh.2i.gs/'),
    GitHubMirror('akams', 'github.akams.cn', 'https://github.akams.cn/'),
    GitHubMirror('ghproxy', 'gh-proxy.com', 'https://gh-proxy.com/'),
  ];

  Map<String, dynamic> get _state {
    try {
      final value = jsonDecode(SpUtil.getString(preferenceKey) ?? '');
      if (value is Map<String, dynamic>) return value;
    } catch (_) {
      // Missing or damaged preferences fall back to direct downloads.
    }
    return {};
  }

  List<GitHubMirror> get options {
    final custom = <GitHubMirror>[];
    final entries = _state['custom'];
    if (entries is List) {
      for (final item in entries.take(20)) {
        try {
          if (item is! Map ||
              item['id'] is! String ||
              item['name'] is! String) {
            continue;
          }
          final id = item['id'] as String;
          final name = item['name'] as String;
          final url = normalizeBase(item['url'] as String);
          if (!id.startsWith('custom-') ||
              name.isEmpty ||
              name.length > 40 ||
              [
                ...presets,
                ...custom,
              ].any((entry) => entry.id == id || entry.baseUrl == url)) {
            continue;
          }
          custom.add(GitHubMirror(id, name, url, custom: true));
        } catch (_) {
          // Ignore invalid entries rather than constructing arbitrary URLs.
        }
      }
    }
    return List.unmodifiable([...presets, ...custom]);
  }

  GitHubMirror get selected {
    final id = _state['selected'];
    return options.where((entry) => entry.id == id).firstOrNull ??
        presets.first;
  }

  String get routeKey => selected.baseUrl ?? 'direct';

  static String normalizeBase(String value) {
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (text.length > 2048 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.contains('://') ||
        uri.pathSegments.any((s) => s == '.' || s == '..') ||
        const {
          'github.com',
          'raw.githubusercontent.com',
          'api.github.com',
        }.contains(uri.host)) {
      throw const HeroFailure('请输入 HTTPS 镜像地址，例如 https://gh-proxy.com/');
    }
    final normalized = uri.toString();
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }

  Future<void> _save(String selected, List<GitHubMirror> entries) async {
    await SpUtil.getInstance();
    final saved = await SpUtil.putString(
      preferenceKey,
      jsonEncode({
        'selected': selected,
        'custom': [
          for (final entry in entries.where((entry) => entry.custom))
            {'id': entry.id, 'name': entry.name, 'url': entry.baseUrl},
        ],
      }),
    );
    if (saved != true) throw const HeroFailure('无法保存镜像设置');
  }

  Future<void> select(String id) async {
    final entries = options;
    if (!entries.any((entry) => entry.id == id)) {
      throw const HeroFailure('镜像不存在');
    }
    await _save(id, entries);
  }

  Future<void> saveCustom({
    String? id,
    required String name,
    required String url,
  }) async {
    final base = normalizeBase(url);
    final label = name.trim().isEmpty ? Uri.parse(base).host : name.trim();
    if (label.length > 40) throw const HeroFailure('镜像名称不能超过 40 字符');
    final entries = options.toList();
    if (entries.any((entry) => entry.id != id && entry.baseUrl == base)) {
      throw const HeroFailure('该镜像地址已存在');
    }
    if (id == null) {
      if (entries.where((entry) => entry.custom).length >= 20) {
        throw const HeroFailure('最多添加 20 个自定义镜像');
      }
      entries.add(
        GitHubMirror('custom-${const Uuid().v4()}', label, base, custom: true),
      );
    } else {
      final index = entries.indexWhere(
        (entry) => entry.id == id && entry.custom,
      );
      if (index < 0) throw const HeroFailure('自定义镜像不存在');
      entries[index] = GitHubMirror(id, label, base, custom: true);
    }
    await _save(selected.id, entries);
  }

  Future<void> remove(String id) async {
    final entries = options;
    if (!entries.any((entry) => entry.id == id && entry.custom)) {
      throw const HeroFailure('只能删除自定义镜像');
    }
    await _save(
      selected.id == id ? 'direct' : selected.id,
      entries.where((entry) => entry.id != id).toList(),
    );
  }

  Uri resolve(Uri source, {Map<String, dynamic> headers = const {}}) {
    final base = selected.baseUrl;
    if (base == null ||
        source.scheme != 'https' ||
        !const {
          'github.com',
          'raw.githubusercontent.com',
          'api.github.com',
        }.contains(source.host) ||
        source.userInfo.isNotEmpty ||
        source.hasQuery ||
        source.hasFragment ||
        (source.hasPort && source.port != 443) ||
        headers.keys.any(
          (key) => const {
            'authorization',
            'cookie',
            'proxy-authorization',
          }.contains(key.toLowerCase()),
        )) {
      return source;
    }
    // Preserve the original URL verbatim after the mirror prefix.
    return Uri.parse('$base$source');
  }
}
