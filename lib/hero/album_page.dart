import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:picora/utils/common_functions.dart';
import 'package:picora/utils/global.dart';
import 'controller.dart';
import 'models.dart';
import 'hero_theme.dart';
import 'upload_page.dart';

class AlbumPage extends StatefulWidget {
  final PicoraController controller;
  final VoidCallback openUpload;
  const AlbumPage({
    super.key,
    required this.controller,
    required this.openUpload,
  });
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  String _view = 'grid', _query = '';
  String? _host;
  final _selected = <String>{};
  bool _selectionMode = false;
  @override
  void initState() {
    super.initState();
    _view = SpUtil.getString('hero_album_view', defValue: 'grid')!;
  }

  Future<void> _filter() async {
    final result = await heroSheet<String>(
      context,
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .7,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择相册',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.collections_outlined,
                    color: heroBlue,
                  ),
                  title: const Text('全部相册'),
                  trailing: _host == null
                      ? const Icon(Icons.check_rounded, color: heroBlue)
                      : null,
                  onTap: () => Navigator.pop(context, 'all'),
                ),
                if (widget.controller.repositories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionLabel('按图床配置'),
                  for (final repository in widget.controller.repositories)
                    ListTile(
                      leading: RepositoryBadge(repository.spec, size: 34),
                      title: Text(repository.name),
                      subtitle: Text(
                        '${repository.spec.name} · ${widget.controller.images.where((e) => e.repositoryId == repository.id).length} 张图片',
                      ),
                      trailing: _host == 'repo:${repository.id}'
                          ? const Icon(Icons.check_rounded, color: heroBlue)
                          : null,
                      onTap: () =>
                          Navigator.pop(context, 'repo:${repository.id}'),
                    ),
                ],
                const SizedBox(height: 12),
                const SectionLabel('按图床平台（含旧记录）'),
                for (final spec in hostSpecs.where(
                  (h) => widget.controller.images.any((e) => e.host == h.id),
                ))
                  ListTile(
                    leading: RepositoryBadge(spec, size: 34),
                    title: Text(spec.name),
                    subtitle: Text(
                      '${widget.controller.images.where((e) => e.host == spec.id).length} 张图片',
                    ),
                    trailing: _host == spec.id
                        ? const Icon(Icons.check_rounded, color: heroBlue)
                        : null,
                    onTap: () => Navigator.pop(context, spec.id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _host = result == 'all' ? null : result;
        _selected.clear();
      });
    }
  }

  bool _matches(AlbumEntry entry) =>
      _host == null ||
      (_host!.startsWith('repo:')
          ? entry.repositoryId == _host!.substring(5)
          : entry.host == _host);

  String get _filterLabel {
    if (_host == null) return '全部相册';
    if (!_host!.startsWith('repo:')) return hostSpec(_host!).name;
    return widget.controller.repositories
            .where((r) => r.id == _host!.substring(5))
            .firstOrNull
            ?.name ??
        '图床相册';
  }

  List<AlbumEntry> get _visible => widget.controller.images
      .where(
        (e) =>
            _matches(e) &&
            (e.name.toLowerCase().contains(_query.toLowerCase()) ||
                e.url.toLowerCase().contains(_query.toLowerCase())),
      )
      .toList();
  void _select(AlbumEntry entry) => setState(() {
    _selectionMode = true;
    if (!_selected.add(entry.id)) _selected.remove(entry.id);
  });
  Future<void> _batchCopy() async {
    final entries = widget.controller.images.where(
      (e) => _selected.contains(e.id),
    );
    await Clipboard.setData(
      ClipboardData(
        text: entries.map((e) => getFormatedUrl(e.url, e.name)).join('\n'),
      ),
    );
    if (mounted) heroSnack(context, '已复制 ${entries.length} 个链接');
  }

  Future<void> _delete(List<AlbumEntry> entries) async {
    if (entries.isEmpty) return;
    final confirmed = await heroSheet<bool>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '删除这些图片？',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              '将删除 ${entries.length} 条上传记录。${Global.isDeleteCloud ? '同时删除云端图片。' : '云端图片会保留。'}${Global.isDeleteLocal ? '同时删除本地原文件。' : ''}',
              style: const TextStyle(color: heroMuted, height: 1.7),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('确认删除'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.removeImages(entries);
      if (mounted) {
        setState(() {
          _selected.clear();
          _selectionMode = false;
        });
        heroSnack(context, '已删除 ${entries.length} 条记录');
      }
    } catch (e, stack) {
      if (mounted) {
        heroSnack(context, widget.controller.describeError('删除图片', e, stack));
      }
    }
  }

  Future<void> _details(AlbumEntry entry) async {
    await heroSheet<void>(
      context,
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 260,
                    width: double.infinity,
                    child: EntryImage(entry, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${hostSpec(entry.host).name}${entry.uploadedAt == null ? '' : ' · ${entry.uploadedAt!.toLocal().toString().substring(0, 16)}'}',
                  style: const TextStyle(color: heroMuted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                LatestUploadCard(entry),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _delete([entry]);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除上传记录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(AlbumEntry entry, {bool list = false, bool masonry = false}) {
    final selected = _selected.contains(entry.id);
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(list ? 13 : 18),
      child: masonry
          ? EntryImage(entry, natural: true)
          : AspectRatio(aspectRatio: list ? 1 : 1.16, child: EntryImage(entry)),
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onLongPress: () => _select(entry),
        onTap: () => _selectionMode ? _select(entry) : _details(entry),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? heroBlue : heroMuted.withValues(alpha: .10),
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(7),
          child: list
              ? Row(
                  children: [
                    SizedBox(width: 60, height: 60, child: image),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hostSpec(entry.host).name,
                            style: const TextStyle(
                              fontSize: 10,
                              color: heroMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectionMode)
                      Checkbox(
                        value: selected,
                        onChanged: (_) => _select(entry),
                      )
                    else
                      IconButton(
                        tooltip: '复制链接',
                        onPressed: () => copyEntry(context, entry),
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: heroBlue,
                        ),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        image,
                        if (_selectionMode)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected ? heroBlue : Colors.white,
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 10, 2, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hostSpec(entry.host).name,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: heroMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_selectionMode)
                            SizedBox(
                              width: 28,
                              height: 32,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: '复制链接',
                                onPressed: () => copyEntry(context, entry),
                                icon: const Icon(
                                  Icons.copy_outlined,
                                  size: 14,
                                  color: heroMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _visible;
    final width = MediaQuery.of(context).size.width;
    final columns = width > 850
        ? 4
        : width > 600
        ? 3
        : 2;
    return RefreshIndicator(
      onRefresh: widget.controller.loadImages,
      child: ListView(
        key: const PageStorageKey('album'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 130),
        children: [
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Center(
                  child: TextButton.icon(
                    onPressed: _filter,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    label: Text(_filterLabel),
                    iconAlignment: IconAlignment.end,
                  ),
                ),
              ),
              IconButton(
                tooltip: _selectionMode ? '结束多选' : '多选图片',
                onPressed: () => setState(() {
                  _selectionMode = !_selectionMode;
                  _selected.clear();
                }),
                icon: Icon(
                  _selectionMode
                      ? Icons.close_rounded
                      : Icons.checklist_rounded,
                  color: heroBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() {
              _query = v;
              _selected.clear();
            }),
            decoration: const InputDecoration(
              hintText: '搜索图片名称或链接',
              prefixIcon: Icon(Icons.search_rounded, color: heroMuted),
              filled: true,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                '${images.length} 张图片',
                style: const TextStyle(color: heroMuted, fontSize: 12),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    for (final view in [
                      ('masonry', Icons.dashboard_outlined, '瀑布流'),
                      ('grid', Icons.grid_view_rounded, '网格'),
                      ('list', Icons.view_list_outlined, '列表'),
                    ])
                      Tooltip(
                        message: view.$3,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () {
                            setState(() => _view = view.$1);
                            SpUtil.putString('hero_album_view', _view);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _view == view.$1
                                  ? heroBlue.withValues(alpha: .10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              view.$2,
                              color: _view == view.$1 ? heroBlue : heroMuted,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_selectionMode) ...[
            HeroPanel(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Checkbox(
                    value:
                        images.isNotEmpty && _selected.length == images.length,
                    onChanged: (_) => setState(() {
                      if (_selected.length == images.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(images.map((e) => e.id));
                      }
                    }),
                  ),
                  Text(
                    '已选 ${_selected.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '复制选中链接',
                    onPressed: _selected.isEmpty ? null : _batchCopy,
                    icon: const Icon(Icons.copy_outlined, size: 19),
                  ),
                  IconButton(
                    tooltip: '删除选中图片',
                    onPressed: _selected.isEmpty
                        ? null
                        : () => _delete(
                            widget.controller.images
                                .where((e) => _selected.contains(e.id))
                                .toList(),
                          ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 21),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (images.isEmpty)
            HeroPanel(
              child: HeroEmpty(
                icon: Icons.photo_library_outlined,
                title: _query.isEmpty ? '暂无上传图片' : '未找到匹配图片',
                message: _query.isEmpty ? '成功上传的图片会显示在这里。' : '试试其他名称，或切换到全部相册。',
                action: _query.isEmpty
                    ? FilledButton.icon(
                        onPressed: widget.openUpload,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('上传图片'),
                      )
                    : null,
              ),
            )
          else if (_view == 'list')
            ...images.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _item(e, list: true),
              ),
            )
          else if (_view == 'masonry')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = col; i < images.length; i += columns)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _item(images[i], masonry: true),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: images
                    .map(
                      (e) => SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns,
                        child: _item(e),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
