import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'controller.dart';
import 'hero_theme.dart';
import 'models.dart';
import 'upload_page.dart';
import 'markdown_documents.dart';
import 'markdown_migration.dart';
import 'diagnostics.dart';

class MarkdownMigrationPage extends StatefulWidget {
  final PicoraController controller;
  final MarkdownDocumentService? documents;
  const MarkdownMigrationPage({
    super.key,
    required this.controller,
    this.documents,
  });
  @override
  State<MarkdownMigrationPage> createState() => _MarkdownMigrationPageState();
}

class _MarkdownMigrationPageState extends State<MarkdownMigrationPage> {
  late final MarkdownDocumentService _documents =
      widget.documents ?? MarkdownDocumentService();
  MarkdownSourceFile? _source;
  RepositoryConfig? _destination;
  MarkdownMigrationResult? _result;
  MigrationCancellation? _cancellation;
  bool _overwrite = false, _working = false;
  bool _allowLeave = false, _confirmingLeave = false;
  String? _error, _savedUri;

  @override
  void initState() {
    super.initState();
    _destination = widget.controller.target;
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _guard(String action, Future<void> Function() callback) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await callback();
    } catch (error, stack) {
      final message = widget.controller.describeError(action, error, stack);
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pick() => _guard('选择 Markdown 文件', () async {
    final source = await _documents.pick();
    if (source == null || !mounted) return;
    setState(() {
      _source = source;
      _result = null;
      _savedUri = null;
      _allowLeave = false;
      _documents.backupPath = null;
    });
  });

  Future<void> _chooseTarget() async {
    final controller = widget.controller;
    final choice = await heroSheet<RepositoryConfig>(
      context,
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择目标图床',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (controller.repositories.isEmpty) const Text('请先到仓库添加图床配置'),
            for (final config in controller.repositories)
              Builder(
                builder: (context) {
                  final enabled =
                      !config.spec.isRuntimePlugin ||
                      controller.pluginManager.isEnabled(config.spec.pluginId!);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: RepositoryBadge(config.spec),
                    title: Text(config.name),
                    subtitle: Text(enabled ? config.spec.name : '插件已停用'),
                    trailing: config.id == _destination?.id
                        ? const Icon(Icons.check_rounded, color: heroBlue)
                        : null,
                    onTap: enabled
                        ? () => Navigator.pop(context, config)
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _destination = choice);
  }

  Future<void> _save() async {
    final source = _source!, result = _result!;
    final bytes = source.encode(result.text);
    if (_overwrite) {
      await _documents.overwrite(source, bytes);
      if (mounted) setState(() => _savedUri = source.uri);
    } else {
      final uri = await _documents.saveNew('$_baseName.picora.md', bytes);
      if (mounted && uri != null) setState(() => _savedUri = uri);
    }
    if (mounted) {
      heroSnack(
        context,
        _savedUri == null
            ? '未保存，处理结果仍保留在此页面'
            : (_overwrite ? '原文件已更新，原文备份已保留' : '新 Markdown 文件已保存'),
      );
    }
  }

  Future<void> _run() => _guard('一键替换图床', () async {
    if (_source == null || _destination == null) {
      throw const HeroFailure('请选择 Markdown 文件和目标图床');
    }
    final cancellation = MigrationCancellation();
    setState(() {
      _cancellation = cancellation;
      _result = null;
      _savedUri = null;
    });
    try {
      final result = await widget.controller.migrateMarkdown(
        _source!.text,
        _destination!,
        cancellation,
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.successful == 0) {
        heroSnack(
          context,
          result.cancelled ? '任务已停止，文件未修改' : '没有成功迁移的图片，文件未修改',
        );
        return;
      }
      if (result.cancelled) {
        heroSnack(context, '任务已停止；可保存已完成的部分');
        return;
      }
      await _save();
    } finally {
      if (mounted) setState(() => _cancellation = null);
    }
  });

  String get _baseName => String.fromCharCodes(
    p.basenameWithoutExtension(_source!.name).runes.take(60),
  );

  Future<void> _confirmExit() async {
    if (_working) {
      heroSnack(context, '请先停止任务，等待当前操作完成');
      return;
    }
    if (_confirmingLeave) return;
    _confirmingLeave = true;
    try {
      final leave = await heroSheet<bool>(
        context,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '处理结果尚未保存',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text('离开后将丢失本次 Markdown 替换结果。已上传的图片仍可在相册查看。'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续保存结果'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃结果并离开'),
              ),
            ],
          ),
        ),
      );
      if (leave == true && mounted) {
        setState(() => _allowLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } finally {
      _confirmingLeave = false;
    }
  }

  Future<void> _exportReport() => _guard('导出图床替换报告', () async {
    final uri = await _documents.saveNew(
      '$_baseName.picora-report.txt',
      utf8.encode(_result!.report()),
    );
    if (mounted && uri != null) heroSnack(context, '错误报告已导出，包含诊断编号和脱敏堆栈');
  });

  Future<void> _exportBackup() => _guard('导出原文备份', () async {
    final backup = File(_documents.backupPath!);
    final uri = await _documents.saveNew(
      '$_baseName.backup.md',
      await backup.readAsBytes(),
    );
    if (mounted && uri != null) heroSnack(context, '原文备份已导出');
  });

  Widget _mode(bool overwrite, String label, String description) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      description,
      style: const TextStyle(fontSize: 11, color: heroMuted),
    ),
    trailing: Icon(
      _overwrite == overwrite
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
      color: _overwrite == overwrite ? heroBlue : heroMuted,
    ),
    onTap: _working || _result != null
        ? null
        : () => setState(() => _overwrite = overwrite),
  );

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope<void>(
      canPop:
          !_working &&
          (_allowLeave || _savedUri != null || (_result?.successful ?? 0) == 0),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('一键替换图床', style: TextStyle(fontSize: 17)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          children: [
            HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Markdown 文件'),
                  Text(
                    _source?.name ?? '尚未选择文件',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'UTF-8 .md / .markdown，最大 10 MB；跳过本地图片与代码示例。',
                    style: TextStyle(
                      color: heroMuted,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _pick,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('选择文件'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('上传到'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _destination == null
                        ? const Icon(Icons.cloud_outlined, color: heroBlue)
                        : RepositoryBadge(_destination!.spec),
                    title: Text(_destination?.name ?? '选择目标图床'),
                    subtitle: Text(_destination?.spec.name ?? '本次任务固定使用所选配置'),
                    trailing: const Icon(Icons.expand_more_rounded),
                    onTap: _working || result != null ? null : _chooseTarget,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('输出方式'),
                  _mode(false, '另存新文件', '处理完成后选择保存位置，保留原文件'),
                  _mode(true, '覆盖原文件', '只替换成功的图片链接；写入前备份原文'),
                  if (result != null && _savedUri == null && !_working)
                    TextButton(
                      onPressed: () => setState(() => _overwrite = !_overwrite),
                      child: Text(_overwrite ? '改为另存新文件' : '改为覆盖原文件'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_working)
              HeroPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.controller.activity.isEmpty
                          ? '正在处理文件…'
                          : widget.controller.activity,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: widget.controller.busy
                          ? widget.controller.progress
                          : null,
                    ),
                    const SizedBox(height: 12),
                    if (_cancellation != null) ...[
                      const Text(
                        '停止后不再处理后续图片；当前上传完成后可保存已完成部分。',
                        style: TextStyle(color: heroMuted, fontSize: 11),
                      ),
                      TextButton(
                        onPressed: () {
                          _cancellation?.cancel();
                          setState(() {});
                        },
                        child: const Text('停止任务'),
                      ),
                    ],
                  ],
                ),
              )
            else if (result == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _source == null ||
                          _destination == null ||
                          widget.controller.busy
                      ? null
                      : _run,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('开始替换'),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    height: 1.6,
                  ),
                ),
              ),
            if (result != null) ...[
              const SizedBox(height: 18),
              HeroPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.cancelled ? '任务已停止' : '处理完成',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${result.successful} 张成功 · ${result.issues.length} 张失败 · ${result.remaining} 张未处理',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已替换 ${result.replacedOccurrences} 处图片引用；失败链接保留原样。'
                      '${result.skipped == 0 ? '' : ' 跳过 ${result.skipped} 处本地或非 HTTP/HTTPS 图片。'}',
                      style: const TextStyle(
                        color: heroMuted,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                    if (_savedUri != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Markdown 已保存',
                          style: TextStyle(color: heroBlue),
                        ),
                      ),
                    if (_savedUri == null && result.successful > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: FilledButton(
                          onPressed: _working
                              ? null
                              : () => _guard('保存 Markdown', _save),
                          child: const Text('保存已完成结果'),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: _working ? null : _exportReport,
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('导出处理报告'),
                    ),
                    if (_documents.backupPath != null)
                      TextButton.icon(
                        onPressed: _working ? null : _exportBackup,
                        icon: const Icon(Icons.restore_page_outlined, size: 18),
                        label: const Text('导出原文备份'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final issue in result.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HeroPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${issue.phase}失败',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${HeroDiagnostics.redact(issue.url)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: heroMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${HeroDiagnostics.redact(issue.message)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '诊断编号：${issue.diagnosticId}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: heroMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
