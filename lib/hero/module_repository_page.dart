import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'hero_theme.dart';
import 'plugin_page.dart';
import 'plugins/plugin_catalog.dart';
import 'plugins/plugin_package.dart';

class ModuleRepositoryPage extends StatefulWidget {
  final PicoraController controller;
  final Future<bool?> Function(PicoraPluginPackage) review;
  final PluginCatalogService? service;
  final Future<String> Function()? appVersionLoader;
  const ModuleRepositoryPage({
    super.key,
    required this.controller,
    required this.review,
    this.service,
    this.appVersionLoader,
  });

  @override
  State<ModuleRepositoryPage> createState() => _ModuleRepositoryPageState();
}

class _ModuleRepositoryPageState extends State<ModuleRepositoryPage> {
  late final PluginCatalogService _service =
      widget.service ?? PluginCatalogService();
  PluginCatalog? _catalog;
  String? _version, _error, _activeId;
  String _query = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _version ??=
          await (widget.appVersionLoader?.call() ??
              PackageInfo.fromPlatform().then((info) => info.version));
      final catalog = await _service.load(forceRefresh: refresh);
      if (mounted) setState(() => _catalog = catalog);
    } catch (error, stack) {
      final message = widget.controller.describeError('加载模块仓库', error, stack);
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(
    PluginCatalogEntry entry, {
    bool tutorial = false,
  }) async {
    if (_activeId != null) return;
    setState(() => _activeId = entry.id);
    try {
      final package = await _service.download(
        entry,
        widget.controller.pluginManager,
      );
      if (!mounted) return;
      if (tutorial) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PluginReadmePage(
              package: package,
              controller: widget.controller,
            ),
          ),
        );
      } else {
        if (!entry.supports(_version!)) {
          heroSnack(
            context,
            '此插件需要 Picora ${entry.minAppVersion.core.join('.')} 或更新版本',
          );
          return;
        }
        final approved = await widget.review(package);
        if (approved != true || !mounted) return;
        final result = await widget.controller.installPluginPackage(
          package.bytes,
        );
        if (mounted) {
          heroSnack(context, result.updated ? '插件已更新，配置已保留' : '插件已安装');
        }
      }
    } catch (error, stack) {
      final message = widget.controller.describeError(
        '下载模块 ${entry.id}',
        error,
        stack,
      );
      if (mounted) heroSnack(context, message);
    } finally {
      if (mounted) setState(() => _activeId = null);
    }
  }

  Future<void> _source(PluginCatalogEntry entry) async {
    try {
      final opened = await launchUrl(
        entry.repository,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) heroSnack(context, '无法打开插件源码');
    } catch (error, stack) {
      final message = widget.controller.describeError('打开插件源码', error, stack);
      if (mounted) heroSnack(context, message);
    }
  }

  Widget _card(PluginCatalogEntry entry) {
    final installed = widget.controller.installedPlugins
        .where((plugin) => plugin.id == entry.id)
        .firstOrNull;
    final compatible = _version != null && entry.supports(_version!);
    final update = installed != null && entry.isUpdateFor(installed.version);
    final busy = _activeId == entry.id;
    final label = !compatible
        ? '需要更新应用'
        : installed == null
        ? '安装'
        : update
        ? '更新至 ${entry.version}'
        : '已安装';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HeroPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: heroBlue.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    entry.mark,
                    style: const TextStyle(
                      color: heroBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'v${entry.version} · ${entry.author}',
                        style: const TextStyle(color: heroMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entry.example)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '首个插件 · 开发示例',
                  style: TextStyle(color: heroBlue, fontSize: 11),
                ),
              ),
            Text(
              entry.description,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _activeId != null
                      ? null
                      : () => _download(entry, tutorial: true),
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: const Text('使用教程'),
                ),
                TextButton.icon(
                  onPressed: () => _source(entry),
                  icon: const Icon(Icons.code_rounded, size: 16),
                  label: const Text('源码'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _activeId != null ||
                        !compatible ||
                        (installed != null && !update)
                    ? null
                    : () => _download(entry),
                child: Text(busy ? '正在下载…' : label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _catalog?.entries
        .where(
          (entry) =>
              '${entry.name} ${entry.description} ${entry.author} ${entry.id}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('模块仓库', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: '刷新模块仓库',
            onPressed: _loading || _activeId != null
                ? null
                : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => RefreshIndicator(
          onRefresh: () => _load(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: '搜索插件',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 20),
              if (_loading || _activeId != null)
                const LinearProgressIndicator(),
              if (_catalog?.offline == true)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '网络连接失败，显示 ${_catalog!.fetchedAt.toLocal().toString().substring(0, 16)} 的缓存目录。可点击右上角重试。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_error != null)
                HeroPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _load(refresh: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (entries != null && entries.isEmpty)
                const Center(
                  child: Text('没有找到插件', style: TextStyle(color: heroMuted)),
                ),
              if (entries != null) ...entries.map(_card),
            ],
          ),
        ),
      ),
    );
  }
}
