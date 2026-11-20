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

enum MirrorSortMode { defaultOrder, latency, successRate }

class MirrorStats {
  final int attempts, successes;
  const MirrorStats({this.attempts = 0, this.successes = 0});

  double get successRate => attempts == 0 ? 0 : successes / attempts;
  int get successPercent => (successRate * 100).round();

  /// A small prior keeps one lucky probe from outranking a long history.
  double get stability => (successes + 1) / (attempts + 2);
}

/// Applied only at public download call sites, never to uploader traffic.
class GitHubMirrors {
  static const preferenceKey = 'picora_github_mirrors';
  static const statsKey = 'picora_github_mirror_stats';
  static const autoFallbackKey = 'picora_github_mirror_auto_fallback';
  static const sortKey = 'picora_github_mirror_sort';
  static final instance = GitHubMirrors();
  static const maxFallbackRoutes = 4;
  static const presets = [
    GitHubMirror('direct', 'GitHub 直连', null),
    GitHubMirror('ghproxy', 'gh-proxy.com', 'https://gh-proxy.com/'),
    GitHubMirror('669966', 'git.669966.xyz', 'https://git.669966.xyz/'),
    GitHubMirror('dpik', 'gh.dpik.top', 'https://gh.dpik.top/'),
    GitHubMirror('ghproxy-net', 'ghproxy.net', 'https://ghproxy.net/'),
    GitHubMirror('chjina', 'gh.chjina.com', 'https://gh.chjina.com/'),
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

  Map<String, dynamic> get _statsState {
    try {
      final value = jsonDecode(SpUtil.getString(statsKey) ?? '');
      if (value is Map<String, dynamic>) return value;
    } catch (_) {
      // Corrupt statistics must never affect mirror selection.
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

  bool get autoFallbackEnabled =>
      SpUtil.getBool(autoFallbackKey, defValue: true) ?? true;

  MirrorSortMode get sortMode {
    final saved = SpUtil.getString(sortKey, defValue: '');
    return MirrorSortMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => MirrorSortMode.defaultOrder,
    );
  }

  MirrorStats statsFor(String id) {
    final value = _statsState[id];
    if (value is! Map) return const MirrorStats();
    final attempts = value['attempts'];
    final successes = value['successes'];
    if (attempts is! int ||
        successes is! int ||
        attempts < 0 ||
        attempts > 100000 ||
        successes < 0 ||
        successes > attempts) {
      return const MirrorStats();
    }
    return MirrorStats(attempts: attempts, successes: successes);
  }

  Future<void> setAutoFallback(bool value) async {
    await SpUtil.getInstance();
    final saved = await SpUtil.putBool(autoFallbackKey, value);
    if (saved != true) throw const HeroFailure('无法保存自动切换设置');
  }

  Future<void> setSortMode(MirrorSortMode mode) async {
    await SpUtil.getInstance();
    final saved = await SpUtil.putString(sortKey, mode.name);
    if (saved != true) throw const HeroFailure('无法保存镜像排序设置');
  }

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

  Future<void> _writeStats(Map<String, dynamic> stats) async {
    await SpUtil.getInstance();
    final saved = await SpUtil.putString(statsKey, jsonEncode(stats));
    if (saved != true) throw const HeroFailure('无法保存镜像测速记录');
  }

  Future<void> _serializedStatWrite(Future<void> Function() write) {
    final next = _statWrite.then((_) => write());
    _statWrite = next.catchError((Object _) {});
    return next;
  }

  Future<void> _statWrite = Future.value();

  /// Records one completed probe. Cancelled probes must not call this.
  Future<void> recordProbe(String id, {required bool available}) {
    if (!options.any((entry) => entry.id == id)) {
      return Future.error(const HeroFailure('镜像不存在'));
    }
    return _serializedStatWrite(() async {
      final stats = <String, dynamic>{
        for (final entry in _statsState.entries)
          if (entry.value is Map) entry.key: entry.value,
      };
      final previous = statsFor(id);
      final attempts = (previous.attempts + 1).clamp(0, 100000);
      final successes = (previous.successes + (available ? 1 : 0)).clamp(
        0,
        attempts,
      );
      stats[id] = {'attempts': attempts, 'successes': successes};
      await _writeStats(stats);
    });
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
    await _serializedStatWrite(() async {
      final stats = <String, dynamic>{
        for (final entry in _statsState.entries)
          if (entry.key != id && entry.value is Map) entry.key: entry.value,
      };
      await _writeStats(stats);
    });
  }

  bool canMirror(Uri source, {Map<String, dynamic> headers = const {}}) {
    if (source.scheme != 'https' ||
        !const {
          'github.com',
          'raw.githubusercontent.com',
          'api.github.com',
        }.contains(source.host) ||
        source.userInfo.isNotEmpty ||
        source.hasQuery ||
        source.hasFragment ||
        (source.hasPort && source.port != 443)) {
      return false;
    }
    return !headers.keys.any(
      (key) => const {
        'authorization',
        'cookie',
        'proxy-authorization',
      }.contains(key.toLowerCase()),
    );
  }

  /// Routes the current mirror first, then stable alternatives.
  ///
  /// Only public GitHub URLs are eligible. Credential-bearing requests always
  /// stay on the selected route so a proxy can never receive user secrets.
  List<GitHubMirror> requestRoutes(
    Uri source, {
    Map<String, dynamic> headers = const {},
  }) {
    final current = selected;
    if (!autoFallbackEnabled || !canMirror(source, headers: headers)) {
      return [current];
    }
    final alternatives =
        options.where((entry) => entry.id != current.id).toList()..sort((a, b) {
          final sa = statsFor(a.id), sb = statsFor(b.id);
          final rate = sb.stability.compareTo(sa.stability);
          if (rate != 0) return rate;
          final count = sb.attempts.compareTo(sa.attempts);
          if (count != 0) return count;
          return options.indexOf(a).compareTo(options.indexOf(b));
        });
    return [current, ...alternatives.take(maxFallbackRoutes - 1)];
  }

  Uri resolve(
    Uri source, {
    Map<String, dynamic> headers = const {},
    GitHubMirror? mirror,
  }) {
    final base = (mirror ?? selected).baseUrl;
    if (base == null || !canMirror(source, headers: headers)) {
      return source;
    }
    // Preserve the original URL verbatim after the mirror prefix.
    return Uri.parse('$base$source');
  }
}
