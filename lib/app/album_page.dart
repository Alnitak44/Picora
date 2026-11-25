import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:picora/legacy/utils/common_functions.dart';
import 'controller.dart';
import 'models.dart';
import 'hero_theme.dart';
import 'upload_page.dart';

class AlbumPage extends StatefulWidget {
  final PicoraController controller;
  final VoidCallback openUpload;
  final bool isActive;
  const AlbumPage({
    super.key,
    required this.controller,
    required this.openUpload,
    this.isActive = true,
  });
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage>
    with SingleTickerProviderStateMixin {
  static const _gap = 12.0;
  static const _minColumns = 2.0, _maxColumns = 6.0;
  String _view = 'grid', _query = '';
  String? _host;

  /// 当前渲染的列数，恒为整数：pinch 过程中取 [ _pinchDesired ] 的上取整。
  double _columnWidth = 2;

  /// 手势基线（连续值，便于双指增减被系统重置时无缝续接）。
  double _startColumns = 2;

  /// 目标列数（连续值）。
  double _pinchDesired = 2;

  /// 预览放大系数，恒 >= 1：内容只会被放大裁切，绝不会缩小留白。
  double _scale = 1;
  double _settleFrom = 1;
  double _availWidth = 358;
  bool _pinching = false, _pinchAllowed = false;
  late final AnimationController _settle;
  final _selected = <String>{};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _view = SpUtil.getString('hero_album_view', defValue: 'grid')!;
    _columnWidth = SpUtil.getInt(
      'hero_album_columns',
      defValue: 2,
    )!.clamp(2, 6).toDouble();
    _settle =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 200),
          )
          ..addListener(() {
            final t = Curves.easeOutCubic.transform(_settle.value);
            setState(() => _scale = _settleFrom + (1 - _settleFrom) * t);
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _scale != 1) {
              setState(() => _scale = 1);
            }
          });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  int get _columnCount => _columnWidth.round().clamp(2, 6);

  double _cellWidth(double columns) =>
      (_availWidth - (columns - 1) * _gap) / columns;

  /// 由当前视觉格子宽度反推等效列数，用于手势续接（不产生跳变）。
  double _desiredFromVisual() {
    final visual = _cellWidth(_columnWidth) * (_scale < 1 ? 1.0 : _scale);
    return ((_availWidth + _gap) / (visual + _gap)).clamp(
      _minColumns,
      _maxColumns,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) return;
    // 手势中途加减手指时，识别器会重新派发 onStart，这里按当前视觉尺寸续接。
    if (_pinching) {
      _startColumns = _pinchDesired;
      return;
    }
    _pinchAllowed = _view == 'grid';
    if (!_pinchAllowed) return;
    _settle.stop();
    final desired = _desiredFromVisual();
    _startColumns = desired;
    _pinchDesired = desired;
    setState(() {
      _pinching = true;
      _columnWidth = desired.ceil().clamp(2, 6).toDouble();
      _scale = (_cellWidth(desired) / _cellWidth(_columnWidth)).clamp(1.0, 1.6);
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_pinching || !_pinchAllowed || details.pointerCount < 2) return;
    final factor = details.scale.clamp(.2, 5.0);
    final desired = (_startColumns / factor).clamp(_minColumns, _maxColumns);
    final columns = desired.ceil().clamp(2, 6).toDouble();
    final scale = (_cellWidth(desired) / _cellWidth(columns)).clamp(1.0, 1.6);
    _pinchDesired = desired;
    if (columns == _columnWidth && (scale - _scale).abs() < .002) return;
    setState(() {
      _columnWidth = columns;
      _scale = scale;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_pinching || !_pinchAllowed) {
      if (_pinching) setState(() => _pinching = false);
      return;
    }
    _pinchAllowed = false;
    // 吸附到与当前视觉尺寸最接近的整数列，回弹幅度不超过半档。
    final target = _pinchDesired.round().clamp(2, 6).toDouble();
    _settleFrom = (_cellWidth(_pinchDesired) / _cellWidth(target)).clamp(
      .5,
      1.6,
    );
    setState(() {
      _columnWidth = target;
      _scale = _settleFrom;
      _pinching = false;
    });
    SpUtil.putInt('hero_album_columns', target.round());
    if ((_settleFrom - 1).abs() < .002) {
      setState(() => _scale = 1);
      return;
    }
    _settle.forward(from: 0);
  }

  void _endSelection() => setState(() {
    _selectionMode = false;
    _selected.clear();
  });

  @override
  void didUpdateWidget(AlbumPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _selectionMode = false;
      _selected.clear();
    }
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
              '将删除 ${entries.length} 条上传记录，云端图片会保留。',
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

  Future<void> _deleteCloud(AlbumEntry entry) async {
    final confirmed = await heroSheet<bool>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '删除这张云端图片？',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              '云端图片删除后无法恢复。上传记录和本地文件会保留。',
              style: TextStyle(color: heroMuted, height: 1.7),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('确认删除云端图片'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      if (mounted) heroSnack(context, '正在删除云端图片…');
      await widget.controller.deleteCloudImage(
        entry,
        explicitAuthorization: true,
      );
      if (mounted) heroSnack(context, '云端图片已删除');
    } catch (error, stack) {
      if (mounted) {
        heroSnack(
          context,
          widget.controller.describeError('删除云端图片', error, stack),
        );
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _delete([entry]);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          '删除上传记录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          textStyle: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(fontSize: 12),
                        ),
                      ),
                    ),
                    if (widget.controller.supportsCloudDelete(entry)) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('delete-cloud-image'),
                          onPressed:
                              widget.controller.isCloudImageDeleted(entry)
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _deleteCloud(entry);
                                },
                          icon: const Icon(Icons.cloud_off_outlined, size: 18),
                          label: Text(
                            widget.controller.isCloudImageDeleted(entry)
                                ? '云端图片已删除'
                                : '删除云端图片',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: .52),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            textStyle: Theme.of(
                              context,
                            ).textTheme.labelLarge?.copyWith(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    AlbumEntry entry, {
    bool list = false,
    bool masonry = false,
    bool compact = false,
  }) {
    final selected = _selected.contains(entry.id);
    if (compact) {
      return AspectRatio(
        aspectRatio: 1.34,
        child: Material(
          key: ValueKey('album-card-${entry.id}'),
          color: Theme.of(context).colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _selectionMode ? _select(entry) : _details(entry),
            onLongPress: () => _select(entry),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: EntryImage(entry),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: selected
                          ? heroBlue.withValues(alpha: .22)
                          : Colors.transparent,
                      border: Border.all(
                        color: selected ? heroBlue : Colors.transparent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (_selectionMode)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        key: ValueKey(selected),
                        size: 18,
                        color: selected ? heroBlue : Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final image = SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(list ? 13 : 18),
        child: masonry
            ? EntryImage(entry, natural: true)
            : AspectRatio(
                aspectRatio: list ? 1 : 1.34,
                child: EntryImage(entry),
              ),
      ),
    );
    return Material(
      key: ValueKey('album-card-${entry.id}'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onLongPress: () => _select(entry),
        onTap: () => _selectionMode ? _select(entry) : _details(entry),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? heroBlue : heroMuted.withValues(alpha: .10),
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(6),
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
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutBack,
                                    ),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                              child: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                key: ValueKey(selected),
                                color: selected ? heroBlue : Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 10, 2, 4),
                      child: SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _pinchBadge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = (_pinching ? _pinchDesired.round() : _columnWidth.round())
        .clamp(2, 6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.grid_view_rounded,
            size: 14,
            color: scheme.onInverseSurface,
          ),
          const SizedBox(width: 6),
          Text(
            '$label 列',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onInverseSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _visible;
    final width = MediaQuery.of(context).size.width;
    final pagePadding = width >= 560 ? 24.0 : 16.0;
    return PopScope<void>(
      canPop: !widget.isActive || !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.isActive && _selectionMode) _endSelection();
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _TwoFingerScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _TwoFingerScaleGestureRecognizer
              >(
                () => _TwoFingerScaleGestureRecognizer(debugOwner: this),
                (recognizer) => recognizer
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd,
              ),
        },
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: widget.controller.loadImages,
              child: ListView(
                key: const PageStorageKey('album'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pagePadding, 20, pagePadding, 130),
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
                      _AlbumViewSwitch(
                        value: _view,
                        onChanged: (value) {
                          setState(() => _view = value);
                          SpUtil.putString('hero_album_view', _view);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration:
                        MediaQuery.maybeOf(context)?.disableAnimations ?? false
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: curved,
                          axisAlignment: -1,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -.12),
                              end: Offset.zero,
                            ).animate(curved),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: !_selectionMode
                        ? const SizedBox(
                            key: ValueKey('album-selection-bar-hidden'),
                          )
                        : Padding(
                            key: const ValueKey('album-selection-bar'),
                            padding: const EdgeInsets.only(bottom: 16),
                            child: HeroPanel(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value:
                                        images.isNotEmpty &&
                                        _selected.length == images.length,
                                    onChanged: (_) => setState(() {
                                      if (_selected.length == images.length) {
                                        _selected.clear();
                                      } else {
                                        _selected.addAll(
                                          images.map((e) => e.id),
                                        );
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
                                    onPressed: _selected.isEmpty
                                        ? null
                                        : _batchCopy,
                                    icon: const Icon(
                                      Icons.copy_outlined,
                                      size: 19,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '删除选中图片',
                                    onPressed: _selected.isEmpty
                                        ? null
                                        : () => _delete(
                                            widget.controller.images
                                                .where(
                                                  (e) =>
                                                      _selected.contains(e.id),
                                                )
                                                .toList(),
                                          ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 21,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  AnimatedSwitcher(
                    duration:
                        MediaQuery.maybeOf(context)?.disableAnimations ?? false
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) {
                      if (current == null || previous.isEmpty) {
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, if (current != null) current],
                        );
                      }
                      // 外层高度始终跟随新视图；旧视图单独裁切，不能撑高或压住新视图。
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          current,
                          for (final child in previous)
                            Positioned.fill(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: IgnorePointer(child: child),
                              ),
                            ),
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final key = child.key;
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final current =
                              key == ValueKey('album-$_view-${images.isEmpty}');
                          final v = animation.value;
                          // 先出后进：旧内容在前 30% 淡出，新内容从 30% 才淡入。
                          final opacity = current
                              ? Curves.easeOutCubic.transform(
                                  ((v - .3) / .7).clamp(0.0, 1.0),
                                )
                              : 1 -
                                    Curves.easeInCubic.transform(
                                      ((1 - v) / .3).clamp(0.0, 1.0),
                                    );
                          return Opacity(
                            opacity: opacity,
                            child: Transform.scale(
                              scale: current ? .985 + .015 * opacity : 1,
                              alignment: Alignment.topCenter,
                              child: child,
                            ),
                          );
                        },
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey('album-$_view-${images.isEmpty}'),
                      child: images.isEmpty
                          ? HeroPanel(
                              child: HeroEmpty(
                                icon: Icons.photo_library_outlined,
                                title: _query.isEmpty ? '暂无上传图片' : '未找到匹配图片',
                                message: _query.isEmpty
                                    ? '成功上传的图片会显示在这里。'
                                    : '试试其他名称，或切换到全部相册。',
                                action: _query.isEmpty
                                    ? FilledButton.icon(
                                        onPressed: widget.openUpload,
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('上传图片'),
                                      )
                                    : null,
                              ),
                            )
                          : _view == 'list'
                          ? Column(
                              children: images
                                  .map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _item(e, list: true),
                                    ),
                                  )
                                  .toList(),
                            )
                          : _view == 'masonry'
                          ? Column(
                              children: images
                                  .map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _item(e, masonry: true),
                                    ),
                                  )
                                  .toList(),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                _availWidth = constraints.maxWidth;
                                final cellWidth =
                                    (constraints.maxWidth -
                                        (_columnWidth - 1) * _gap) /
                                    _columnWidth;
                                final cellHeight = _AlbumGrid.cellHeightFor(
                                  cellWidth,
                                );

                                // 非吸附动画期间恒为 1，避免残留缩放导致两侧留白。
                                final preview = _settle.isAnimating
                                    ? _scale
                                    : (_scale < 1 ? 1.0 : _scale);
                                return ClipRect(
                                  clipper: _HorizontalEdgeClipper(),
                                  child: Transform.scale(
                                    scale: preview,
                                    alignment: Alignment.topLeft,
                                    child: _AlbumGrid(
                                      columns: _columnCount,
                                      cellWidth: cellWidth,
                                      cellHeight: cellHeight,
                                      gap: _gap,
                                      items: images,
                                      itemBuilder: (e, compact) =>
                                          _item(e, compact: compact),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (_pinching)
              Positioned(
                left: 0,
                right: 0,
                bottom: 128,
                child: IgnorePointer(
                  child: Center(child: _pinchBadge(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalEdgeClipper extends CustomClipper<Rect> {
  const _HorizontalEdgeClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, -10000, size.width, size.height + 20000);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// 网格视图：列数变化时让每张卡片补间到新位置/新尺寸，避免直接跳变。
class _AlbumGrid extends StatelessWidget {
  final int columns;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final List<AlbumEntry> items;
  final Widget Function(AlbumEntry entry, bool compact) itemBuilder;

  const _AlbumGrid({
    required this.columns,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.items,
    required this.itemBuilder,
  });

  /// 卡片高度只与宽度相关，保证每格等高，重排时只做位移动画。
  static double cellHeightFor(double width) =>
      width < 100 ? width / 1.34 : (width - 14) / 1.34 + 66;

  @override
  Widget build(BuildContext context) {
    final duration = (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final rows = (items.length + columns - 1) ~/ columns;
    final height = rows == 0 ? 0.0 : rows * cellHeight + (rows - 1) * gap;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            AnimatedPositioned(
              key: ValueKey('album-tile-${items[i].id}'),
              duration: duration,
              curve: Curves.easeOutCubic,
              left: (i % columns) * (cellWidth + gap),
              top: (i ~/ columns) * (cellHeight + gap),
              width: cellWidth,
              height: cellHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 按动画中的实际格子尺寸决定紧凑模式，避免重排过程中内容溢出。
                  final compact =
                      constraints.maxWidth < 100 ||
                      constraints.maxHeight <
                          (constraints.maxWidth - 14) / 1.34 + 64;
                  return itemBuilder(items[i], compact);
                },
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            child: SizedBox.shrink(key: ValueKey('album-grid-$columns')),
          ),
        ],
      ),
    );
  }
}

class _TwoFingerScaleGestureRecognizer extends ScaleGestureRecognizer {
  _TwoFingerScaleGestureRecognizer({super.debugOwner});

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (pointerCount >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && pointerCount < 2) {
      return;
    }
    super.resolve(disposition);
  }
}

class _AlbumViewSwitch extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _AlbumViewSwitch({required this.value, required this.onChanged});
  static const views = [
    ('list', Icons.view_list_outlined, '列表'),
    ('masonry', Icons.dashboard_outlined, '瀑布流'),
    ('grid', Icons.grid_view_rounded, '网格'),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = views.indexWhere((item) => item.$1 == value).clamp(0, 2);
    final lastIndex = views.length - 1;
    final duration = MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Container(
      width: 112,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.all(3),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment(selected / lastIndex * 2 - 1, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / views.length,
              heightFactor: 1,
              child: DecoratedBox(
                key: const ValueKey('album-view-indicator'),
                decoration: BoxDecoration(
                  color: heroBlue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: heroBlue.withValues(alpha: .12)),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final view in views)
                Expanded(
                  child: Tooltip(
                    message: view.$3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onChanged(view.$1),
                      child: Center(
                        child: AnimatedScale(
                          scale: value == view.$1 ? 1.08 : 1,
                          duration: duration,
                          child: Icon(
                            view.$2,
                            color: value == view.$1 ? heroBlue : heroMuted,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
