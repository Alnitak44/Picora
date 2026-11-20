import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'diagnostics.dart';
import 'github_mirrors.dart';
import 'github_mirror_probe.dart';
import 'hero_theme.dart';

class GitHubMirrorPage extends StatefulWidget {
  final GitHubMirrorProbe? probe;
  const GitHubMirrorPage({super.key, this.probe});
  @override
  State<GitHubMirrorPage> createState() => _GitHubMirrorPageState();
}

class _GitHubMirrorPageState extends State<GitHubMirrorPage> {
  final _mirrors = GitHubMirrors.instance;
  bool _saving = false;
  bool _testing = false;
  int _testGeneration = 0;
  final _results = <String, MirrorProbeResult>{};
  final _pending = <String>{};
  final _tokens = <CancelToken>[];
  final _stats = <String, MirrorStats>{};
  late final _probe = widget.probe ?? GitHubMirrorProbe();
  late MirrorSortMode _sortMode;

  MirrorStats _statsFor(String id) => _stats[id] ?? _mirrors.statsFor(id);

  @override
  void initState() {
    super.initState();
    _sortMode = _mirrors.sortMode;
  }

  int _latencyRank(GitHubMirror mirror) {
    final result = _results[mirror.id];
    if (result == null) return 1;
    return result.available ? 0 : 2;
  }

  List<GitHubMirror> get _sortedMirrors {
    final options = _mirrors.options;
    final direct = options.where((mirror) => mirror.id == 'direct').toList();
    final others = options.where((mirror) => mirror.id != 'direct').toList();
    final defaultIndex = {
      for (var index = 0; index < options.length; index++)
        options[index].id: index,
    };
    switch (_sortMode) {
      case MirrorSortMode.defaultOrder:
        break;
      case MirrorSortMode.latency:
        others.sort((a, b) {
          final rank = _latencyRank(a).compareTo(_latencyRank(b));
          if (rank != 0) return rank;
          final elapsedA = _results[a.id]?.elapsed;
          final elapsedB = _results[b.id]?.elapsed;
          if (elapsedA != null && elapsedB != null) {
            final latency = elapsedA.compareTo(elapsedB);
            if (latency != 0) return latency;
          }
          return defaultIndex[a.id]!.compareTo(defaultIndex[b.id]!);
        });
      case MirrorSortMode.successRate:
        others.sort((a, b) {
          final statsA = _statsFor(a.id), statsB = _statsFor(b.id);
          if (statsA.attempts == 0 && statsB.attempts > 0) return 1;
          if (statsB.attempts == 0 && statsA.attempts > 0) return -1;
          final rate = statsB.successPercent.compareTo(statsA.successPercent);
          if (rate != 0) return rate;
          final count = statsB.attempts.compareTo(statsA.attempts);
          if (count != 0) return count;
          return defaultIndex[a.id]!.compareTo(defaultIndex[b.id]!);
        });
    }
    return [...direct, ...others];
  }

  MirrorProbeResult? get _recommended {
    if (_testing || _results.length != _mirrors.options.length) return null;
    final usable = _results.values.where((r) => r.available).toList()
      ..sort((a, b) {
        final sa = _statsFor(a.mirror.id);
        final sb = _statsFor(b.mirror.id);
        final rate = sb.stability.compareTo(sa.stability);
        if (rate != 0) return rate;
        final count = sb.attempts.compareTo(sa.attempts);
        if (count != 0) return count;
        return a.elapsed!.compareTo(b.elapsed!);
      });
    return usable.firstOrNull;
  }

  void _stopTests() {
    _testGeneration++;
    for (final token in _tokens.toList()) {
      token.cancel('user cancelled');
    }
    _tokens.clear();
    _pending.clear();
    _testing = false;
  }

  @override
  void dispose() {
    _stopTests();
    super.dispose();
  }

  Future<void> _testAll() async {
    if (_testing || _saving) return;
    final options = _mirrors.options;
    final generation = ++_testGeneration;
    setState(() {
      _testing = true;
      _results.clear();
      _pending.addAll(options.map((m) => m.id));
    });
    var next = 0;
    Future<void> worker() async {
      while (mounted &&
          generation == _testGeneration &&
          next < options.length) {
        final mirror = options[next++];
        final token = CancelToken();
        _tokens.add(token);
        final result = await _probe.probe(mirror, cancelToken: token);
        _tokens.remove(token);
        if (result.completed) {
          final previous = _statsFor(mirror.id);
          _stats[mirror.id] = MirrorStats(
            attempts: previous.attempts + 1,
            successes: previous.successes + (result.available ? 1 : 0),
          );
          unawaited(
            _mirrors
                .recordProbe(mirror.id, available: result.available)
                .catchError((Object error, StackTrace stack) {
                  HeroDiagnostics.instance.record(
                    '保存镜像测速记录',
                    error,
                    stack: stack,
                    context: {'mirror': mirror.id},
                  );
                }),
          );
        }
        if (!mounted || generation != _testGeneration) return;
        setState(() {
          _results[mirror.id] = result;
          _pending.remove(mirror.id);
        });
      }
    }

    await Future.wait(
      List.generate(options.length.clamp(1, 3), (_) => worker()),
    );
    if (mounted && generation == _testGeneration) {
      setState(() => _testing = false);
      if (_recommended == null) {
        heroSnack(context, '所有线路均不可用，请检查网络后重试');
      }
    }
  }

  Future<void> _change(Future<void> Function() action, String message) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) heroSnack(context, message);
    } catch (error) {
      if (mounted) heroSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setSort(MirrorSortMode mode) async {
    if (mode == _sortMode) return;
    final previous = _sortMode;
    setState(() => _sortMode = mode);
    try {
      await _mirrors.setSortMode(mode);
    } catch (error, stack) {
      HeroDiagnostics.instance.record(
        '保存镜像排序设置',
        error,
        stack: stack,
        context: {'sort': mode.name},
      );
      if (mounted) {
        setState(() => _sortMode = previous);
        heroSnack(context, '排序设置保存失败');
      }
    }
  }

  Future<void> _edit([GitHubMirror? mirror]) async {
    final saved = await heroSheet<bool>(context, _MirrorEditor(mirror: mirror));
    if (saved == true && mounted) setState(() => _results.clear());
  }

  Widget _row(GitHubMirror mirror) {
    final stats = _statsFor(mirror.id);
    final result = _results[mirror.id];
    return ListTile(
      key: ValueKey('mirror-row-${mirror.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      minVerticalPadding: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onTap: _saving
          ? null
          : () => _change(() => _mirrors.select(mirror.id), '下载线路已切换'),
      leading: Icon(
        _mirrors.selected.id == mirror.id
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked,
        color: _mirrors.selected.id == mirror.id ? heroBlue : heroMuted,
      ),
      title: Text(mirror.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mirror.baseUrl != null)
            Text(
              mirror.baseUrl!,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (stats.attempts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '成功率 ${stats.successPercent}% · ${stats.successes}/${stats.attempts}',
                style: const TextStyle(fontSize: 12, color: heroMuted),
              ),
            ),
          if (_pending.contains(mirror.id) || result != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _pending.contains(mirror.id)
                    ? '测速中…'
                    : result!.available
                    ? '可用 · ${result.elapsed!.inMilliseconds.clamp(1, 999999)} ms'
                    : result.error!,
                style: TextStyle(
                  fontSize: 12,
                  color: result?.available == false
                      ? Theme.of(context).colorScheme.error
                      : heroBlue,
                ),
              ),
            ),
        ],
      ),
      trailing: mirror.custom
          ? PopupMenuButton<String>(
              enabled: !_saving && !_testing,
              tooltip: '管理镜像',
              onSelected: (value) {
                if (value == 'edit') {
                  _edit(mirror);
                } else {
                  _change(() async {
                    await _mirrors.remove(mirror.id);
                    _results.remove(mirror.id);
                  }, '镜像已删除');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'remove', child: Text('删除')),
              ],
            )
          : null,
    );
  }

  Widget _mirrorList(BuildContext context) {
    final mirrors = _sortedMirrors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    final detailRows = mirrors.fold<int>(
      1,
      (maxRows, mirror) =>
          _results[mirror.id] != null ||
              _statsFor(mirror.id).attempts > 0 ||
              _pending.contains(mirror.id)
          ? 3
          : maxRows,
    );
    final baseHeight = 58.0 + (detailRows - 1) * 18;
    final extent = MediaQuery.textScalerOf(
      context,
    ).scale(baseHeight).clamp(baseHeight, 138).toDouble();
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      height: extent * mirrors.length,
      child: Stack(
        children: [
          for (final (index, mirror) in mirrors.indexed)
            AnimatedPositioned(
              key: ValueKey(mirror.id),
              duration: duration,
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              top: extent * index,
              height: extent,
              child: RepaintBoundary(child: _row(mirror)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recommended = _recommended;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 镜像', style: TextStyle(fontSize: 17)),
        actions: [
          PopupMenuButton<MirrorSortMode>(
            key: const ValueKey('mirror-sort'),
            tooltip: '排序',
            initialValue: _sortMode,
            onSelected: _setSort,
            itemBuilder: (_) => [
              for (final mode in MirrorSortMode.values)
                CheckedPopupMenuItem(
                  value: mode,
                  checked: mode == _sortMode,
                  child: Text(switch (mode) {
                    MirrorSortMode.defaultOrder => '默认',
                    MirrorSortMode.latency => '按延迟',
                    MirrorSortMode.successRate => '按成功率',
                  }),
                ),
            ],
            icon: const Icon(Icons.sort_rounded, size: 20),
          ),
          TextButton.icon(
            onPressed: _saving
                ? null
                : () {
                    if (_testing) {
                      setState(_stopTests);
                    } else {
                      _testAll();
                    }
                  },
            icon: Icon(
              _testing ? Icons.stop_circle_outlined : Icons.speed_rounded,
              size: 20,
            ),
            label: Text(_testing ? '停止' : '测速'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '用于插件仓库、插件包和应用更新下载。',
            style: TextStyle(color: heroMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          if (_testing) ...[
            LinearProgressIndicator(
              value: _results.length / _mirrors.options.length,
            ),
            const SizedBox(height: 8),
            Text(
              '测速中 ${_results.length}/${_mirrors.options.length}',
              style: const TextStyle(fontSize: 12, color: heroMuted),
            ),
            const SizedBox(height: 16),
          ],
          if (recommended != null) ...[
            HeroPanel(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '推荐：${recommended.mirror.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [
                            '目录响应 ${recommended.elapsed!.inMilliseconds.clamp(1, 999999)} ms',
                            if (_statsFor(recommended.mirror.id).attempts > 0)
                              '成功率 ${_statsFor(recommended.mirror.id).successPercent}%'
                                  ' · ${_statsFor(recommended.mirror.id).successes}/${_statsFor(recommended.mirror.id).attempts}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: heroMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _saving || _mirrors.selected.id == recommended.mirror.id
                        ? null
                        : () => _change(
                            () => _mirrors.select(recommended.mirror.id),
                            '已切换至推荐线路',
                          ),
                    child: Text(
                      _mirrors.selected.id == recommended.mirror.id
                          ? '已选用'
                          : '使用推荐',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          HeroPanel(padding: EdgeInsets.zero, child: _mirrorList(context)),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: _saving || _testing ? null : () => _edit(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加自定义镜像'),
          ),
        ],
      ),
    );
  }
}

class _MirrorEditor extends StatefulWidget {
  final GitHubMirror? mirror;
  const _MirrorEditor({this.mirror});
  @override
  State<_MirrorEditor> createState() => _MirrorEditorState();
}

class _MirrorEditorState extends State<_MirrorEditor> {
  late final _name = TextEditingController(text: widget.mirror?.name);
  late final _url = TextEditingController(text: widget.mirror?.baseUrl);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await GitHubMirrors.instance.saveCustom(
        id: widget.mirror?.id,
        name: _name.text,
        url: _url.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.mirror == null ? '添加镜像' : '编辑镜像',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '名称（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '镜像地址',
              hintText: 'https://example.com/',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '下载地址为“镜像地址 + 原始 GitHub URL”。',
            style: TextStyle(color: heroMuted, fontSize: 12),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
    ),
  );
}
