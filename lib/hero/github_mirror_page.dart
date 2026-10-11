import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

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
  late final _probe = widget.probe ?? GitHubMirrorProbe();

  MirrorProbeResult? get _fastest {
    if (_testing || _results.length != _mirrors.options.length) return null;
    final usable = _results.values.where((r) => r.available).toList()
      ..sort((a, b) => a.elapsed!.compareTo(b.elapsed!));
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
      if (_fastest == null) heroSnack(context, '所有线路均不可用，请检查网络后重试');
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

  Future<void> _edit([GitHubMirror? mirror]) async {
    final saved = await heroSheet<bool>(context, _MirrorEditor(mirror: mirror));
    if (saved == true && mounted) setState(() => _results.clear());
  }

  Widget _row(GitHubMirror mirror) => ListTile(
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (_pending.contains(mirror.id) || _results.containsKey(mirror.id))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _pending.contains(mirror.id)
                  ? '测速中…'
                  : _results[mirror.id]!.available
                  ? '可用 · ${_results[mirror.id]!.elapsed!.inMilliseconds.clamp(1, 999999)} ms'
                  : _results[mirror.id]!.error!,
              style: TextStyle(
                fontSize: 12,
                color: _results[mirror.id]?.available == false
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

  @override
  Widget build(BuildContext context) {
    final custom = _mirrors.options.where((entry) => entry.custom).toList();
    final fastest = _fastest;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 镜像', style: TextStyle(fontSize: 17)),
        actions: [
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
          IconButton(
            tooltip: '添加镜像',
            onPressed: _saving || _testing ? null : () => _edit(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '用于模块仓库、插件包和应用更新下载。',
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
          if (fastest != null) ...[
            HeroPanel(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '最快：${fastest.mirror.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '目录响应 ${fastest.elapsed!.inMilliseconds.clamp(1, 999999)} ms',
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
                        _saving || _mirrors.selected.id == fastest.mirror.id
                        ? null
                        : () => _change(
                            () => _mirrors.select(fastest.mirror.id),
                            '已切换至最快线路',
                          ),
                    child: Text(
                      _mirrors.selected.id == fastest.mirror.id
                          ? '已选用'
                          : '使用最快',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          HeroPanel(
            padding: EdgeInsets.zero,
            child: Column(children: GitHubMirrors.presets.map(_row).toList()),
          ),
          const SizedBox(height: 24),
          const SectionLabel('自定义镜像'),
          if (custom.isNotEmpty)
            HeroPanel(
              padding: EdgeInsets.zero,
              child: Column(children: custom.map(_row).toList()),
            ),
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
