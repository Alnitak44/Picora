import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'hero_theme.dart';
import 'plugin_page.dart';
import 'plugin_tags.dart';
import 'plugin_update_badge.dart';
import 'plugins/plugin_catalog.dart';
import 'plugins/plugin_package.dart';

enum _InstallFilter {
  all('全部'),
  installed('已安装'),
  available('未安装');

  final String label;
  const _InstallFilter(this.label);
}

enum _AuthFilter { all, required, optional }

class _PluginRepositorySkeleton extends StatefulWidget {
  const _PluginRepositorySkeleton();

  @override
  State<_PluginRepositorySkeleton> createState() =>
      _PluginRepositorySkeletonState();
}

class _PluginRepositorySkeletonState extends State<_PluginRepositorySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = heroMuted.withValues(alpha: dark ? .24 : .13);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget block(double height, {double? width, double radius = 7}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    Widget line(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: block(height),
    );

    final rows = <Widget>[];
    for (var index = 0; index < 5; index++) {
      if (index > 0) {
        rows.add(
          const Divider(height: 1, thickness: 1, indent: 62, endIndent: 14),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              block(36, width: 36, radius: 11),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(.62, 14),
                    const SizedBox(height: 6),
                    line(.38, 9),
                    const SizedBox(height: 8),
                    line(.94, 10),
                    const SizedBox(height: 5),
                    line(.70, 10),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        block(14, width: 48, radius: 5),
                        const SizedBox(width: 6),
                        block(14, width: 38, radius: 5),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              block(32, width: 52, radius: 10),
            ],
          ),
        ),
      );
    }

    return Semantics(
      key: const ValueKey('plugin-repository-skeleton'),
      container: true,
      label: '正在加载插件',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Opacity(
            opacity: reduceMotion ? 1 : .55 + .35 * _pulse.value,
            child: child,
          ),
          child: HeroPanel(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(children: rows),
          ),
        ),
      ),
    );
  }
}

class PluginRepositoryPage extends StatefulWidget {
  final PicoraController controller;
  final Future<bool?> Function(PicoraPluginPackage) review;
  final PluginCatalogService? service;
  final Future<String> Function()? appVersionLoader;
  const PluginRepositoryPage({
    super.key,
    required this.controller,
    required this.review,
    this.service,
    this.appVersionLoader,
  });

  @override
  State<PluginRepositoryPage> createState() => _PluginRepositoryPageState();
}

class _PluginRepositoryPageState extends State<PluginRepositoryPage> {
  late final PluginCatalogService _service =
      widget.service ?? PluginCatalogService();
  PluginCatalog? _catalog;
  String? _version, _error, _activeId;
  String _query = '';
  _InstallFilter _installFilter = _InstallFilter.all;
  _AuthFilter _authFilter = _AuthFilter.all;
  final Set<PluginTag> _tagFilters = {};
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
      final message = widget.controller.describeError('加载插件仓库', error, stack);
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
        '下载插件 ${entry.id}',
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

  Widget _mark(PluginCatalogEntry entry, {double size = 46}) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: heroBlue.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(size * .30),
    ),
    child: Text(
      entry.mark,
      style: TextStyle(
        color: heroBlue,
        fontSize: size * .30,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Future<void> _more(PluginCatalogEntry entry) async {
    final action = await heroSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _mark(entry),
              title: Text(
                entry.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('v${entry.version} · ${entry.author}'),
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('使用教程'),
              onTap: () => Navigator.pop(context, 'tutorial'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code_rounded),
              title: const Text('源码'),
              onTap: () => Navigator.pop(context, 'source'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'tutorial') {
      await _download(entry, tutorial: true);
    } else {
      await _source(entry);
    }
  }

  Widget _installedLabel() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark
        ? Color.lerp(pluginUpdateColor, Colors.white, .38)!
        : pluginUpdateColor;
    return Container(
      key: const ValueKey('plugin-installed-status'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? .16 : .09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            '已安装',
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    PluginCatalogEntry entry, {
    required bool compatible,
    required bool busy,
    required bool installed,
    required bool update,
  }) {
    if (busy) {
      return const SizedBox(
        width: 56,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (installed && !update) return _installedLabel();
    final label = !compatible
        ? '需新版'
        : installed
        ? '更新'
        : '安装';
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        backgroundColor: update ? pluginUpdateColor : null,
        foregroundColor: update ? Colors.white : null,
      ),
      onPressed: _activeId != null || !compatible
          ? null
          : () => _download(entry),
      child: Text(label),
    );
  }

  Widget _row(PluginCatalogEntry entry) {
    final installed = widget.controller.installedPlugins
        .where((plugin) => plugin.id == entry.id)
        .firstOrNull;
    final compatible = _version != null && entry.supports(_version!);
    final update = installed != null && entry.isUpdateFor(installed.version);
    final busy = _activeId == entry.id;
    final tags = entry.tags;
    final chips = <Widget>[
      if (tags != null)
        ...pluginTagChips(tags, requiresAuth: entry.requiresAuth, dense: true),
      if (update) const PluginUpdateBadge(dense: true),
    ];
    return InkWell(
      onTap: _activeId == null ? () => _more(entry) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _mark(entry, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${entry.version} · ${entry.author}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: heroMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final chip in chips)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: chip,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _action(
              entry,
              compatible: compatible,
              busy: busy,
              installed: installed != null,
              update: update,
            ),
          ],
        ),
      ),
    );
  }

  Widget _installFilterBar() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: heroMuted.withValues(alpha: dark ? .12 : .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final filter in _InstallFilter.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: _installFilter == filter,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('plugin-filter-${filter.name}'),
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => setState(() => _installFilter = filter),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _installFilter == filter
                            ? heroBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        filter.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _installFilter == filter
                              ? Colors.white
                              : heroMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required Key key,
    required String label,
    required bool selected,
    required Color tone,
    required VoidCallback onTap,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Color.lerp(tone, Colors.white, .38)! : tone;
    return FilterChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      backgroundColor: Colors.transparent,
      selectedColor: foreground.withValues(alpha: dark ? .20 : .10),
      side: BorderSide(
        color: selected
            ? foreground.withValues(alpha: .42)
            : heroMuted.withValues(alpha: .18),
      ),
      labelStyle: TextStyle(
        color: selected ? foreground : heroMuted,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _tagFilterButton() {
    final count = (_authFilter == _AuthFilter.all ? 0 : 1) + _tagFilters.length;
    final active = count > 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton.icon(
      key: const ValueKey('plugin-filter-button'),
      onPressed: _openTagFilters,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Text(active ? '筛选 $count' : '筛选'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        foregroundColor: active ? heroBlue : heroMuted,
        backgroundColor: active
            ? heroBlue.withValues(alpha: dark ? .16 : .08)
            : Colors.transparent,
        side: BorderSide(
          color: active
              ? heroBlue.withValues(alpha: .42)
              : heroMuted.withValues(alpha: .18),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _openTagFilters() async {
    await heroSheet<void>(
      context,
      StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          final active =
              _authFilter != _AuthFilter.all || _tagFilters.isNotEmpty;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '按标签筛选',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (active)
                      TextButton(
                        key: const ValueKey('plugin-filter-reset-tags'),
                        onPressed: () => update(() {
                          _authFilter = _AuthFilter.all;
                          _tagFilters.clear();
                        }),
                        child: const Text('重置'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '认证方式',
                  style: TextStyle(
                    color: heroMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip(
                      key: const ValueKey('plugin-filter-auth-required'),
                      label: '需认证',
                      selected: _authFilter == _AuthFilter.required,
                      tone: pluginAuthColor,
                      onTap: () => update(
                        () => _authFilter = _authFilter == _AuthFilter.required
                            ? _AuthFilter.all
                            : _AuthFilter.required,
                      ),
                    ),
                    _filterChip(
                      key: const ValueKey('plugin-filter-auth-optional'),
                      label: '无需认证',
                      selected: _authFilter == _AuthFilter.optional,
                      tone: pluginAuthColor,
                      onTap: () => update(
                        () => _authFilter = _authFilter == _AuthFilter.optional
                            ? _AuthFilter.all
                            : _AuthFilter.optional,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '插件能力',
                  style: TextStyle(
                    color: heroMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in PluginTag.values)
                      _filterChip(
                        key: ValueKey('plugin-filter-tag-${tag.code}'),
                        label: tag.label,
                        selected: _tagFilters.contains(tag),
                        tone: heroBlue,
                        onTap: () => update(() {
                          if (!_tagFilters.remove(tag)) _tagFilters.add(tag);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('plugin-filter-done'),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _matchesFilters(PluginCatalogEntry entry, Set<String> installedIds) {
    final installed = installedIds.contains(entry.id);
    if (_installFilter == _InstallFilter.installed && !installed) return false;
    if (_installFilter == _InstallFilter.available && installed) return false;
    if (_authFilter == _AuthFilter.required && !entry.requiresAuth) {
      return false;
    }
    if (_authFilter == _AuthFilter.optional && entry.requiresAuth) return false;
    final tags = entry.tags;
    if (_tagFilters.isNotEmpty) {
      if (tags == null || !_tagFilters.every(tags.contains)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件仓库', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: '刷新插件仓库',
            onPressed: _loading || _activeId != null
                ? null
                : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final installedVersions = {
            for (final plugin in widget.controller.installedPlugins)
              plugin.id: plugin.version,
          };
          final installedIds = installedVersions.keys.toSet();
          final entries = _catalog
              ?.orderedForInstalled(installedVersions)
              .where(
                (entry) => _searchText(entry).contains(_query.toLowerCase()),
              )
              .where((entry) => _matchesFilters(entry, installedIds))
              .toList();
          return RefreshIndicator(
            onRefresh: () => _load(refresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          hintText: '搜索插件',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _tagFilterButton(),
                  ],
                ),
                const SizedBox(height: 14),
                _installFilterBar(),
                const SizedBox(height: 16),
                if ((_loading && _catalog != null) || _activeId != null)
                  const LinearProgressIndicator(),
                if (_catalog?.offline == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '插件获取失败，请检查网络、前往设置切换镜像或点击右上角重试。',
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
                        const Text('插件获取失败，请检查网络、前往设置切换镜像或点击右上角重试。'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _load(refresh: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                if (_catalog == null && _loading)
                  const _PluginRepositorySkeleton(),
                if (entries != null && entries.isEmpty)
                  const Center(
                    child: Text('没有找到插件', style: TextStyle(color: heroMuted)),
                  ),
                if (entries != null && entries.isNotEmpty)
                  HeroPanel(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < entries.length;
                          index++
                        ) ...[
                          if (index > 0)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              indent: 56,
                              endIndent: 14,
                            ),
                          _row(entries[index]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _searchText(PluginCatalogEntry entry) {
    final tags = entry.tags;
    final tagText = tags == null
        ? ''
        : [
            tags.any((tag) => tag.isAuth) ? '需认证' : '无需认证',
            ...tags.map((tag) => tag.label),
          ].join(' ');
    return '${entry.name} ${entry.description} ${entry.author} ${entry.id} $tagText'
        .toLowerCase();
  }
}
