import 'package:flutter/material.dart';

import 'github_mirrors.dart';
import 'hero_theme.dart';

class GitHubMirrorPage extends StatefulWidget {
  const GitHubMirrorPage({super.key});
  @override
  State<GitHubMirrorPage> createState() => _GitHubMirrorPageState();
}

class _GitHubMirrorPageState extends State<GitHubMirrorPage> {
  final _mirrors = GitHubMirrors.instance;
  bool _saving = false;

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
    if (saved == true && mounted) setState(() {});
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
    subtitle: mirror.baseUrl == null
        ? null
        : Text(
            mirror.baseUrl!,
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: mirror.custom
        ? PopupMenuButton<String>(
            enabled: !_saving,
            tooltip: '管理镜像',
            onSelected: (value) {
              if (value == 'edit') {
                _edit(mirror);
              } else {
                _change(() => _mirrors.remove(mirror.id), '镜像已删除');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 镜像', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: '添加镜像',
            onPressed: _saving ? null : () => _edit(),
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
            onPressed: _saving ? null : () => _edit(),
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
