import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:picora/utils/common_functions.dart';
import 'models.dart';
import 'controller.dart';
import 'hero_theme.dart';
import 'markdown_migration_page.dart';

class RepositoryBadge extends StatelessWidget {
  final HostSpec spec;
  final double size;
  const RepositoryBadge(this.spec, {super.key, this.size = 42});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: spec.id == 'github'
          ? spec.color
          : spec.color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    alignment: Alignment.center,
    child: spec.iconAsset == null && spec.iconBytes == null
        ? Text(
            spec.mark,
            style: TextStyle(
              color: spec.color,
              fontWeight: FontWeight.w800,
              fontSize: size * .32,
            ),
          )
        : Padding(
            padding: EdgeInsets.all(size * .17),
            child: spec.iconBytes != null
                ? (spec.iconFormat == 'svg'
                      ? SvgPicture.memory(
                          spec.iconBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stack) => _fallback(),
                        )
                      : Image.memory(
                          spec.iconBytes!,
                          fit: BoxFit.contain,
                          cacheWidth: (size * 3).round(),
                          errorBuilder: (context, error, stack) => _fallback(),
                        ))
                : spec.iconAsset!.endsWith('.svg')
                ? SvgPicture.asset(spec.iconAsset!, fit: BoxFit.contain)
                : Image.asset(
                    spec.iconAsset!,
                    fit: BoxFit.contain,
                    cacheWidth: (size * 3).round(),
                  ),
          ),
  );

  Widget _fallback() => Text(
    spec.mark,
    style: TextStyle(
      color: spec.color,
      fontWeight: FontWeight.w800,
      fontSize: size * .32,
    ),
  );
}

class EntryImage extends StatelessWidget {
  final AlbumEntry entry;
  final BoxFit fit;
  final bool natural;
  const EntryImage(
    this.entry, {
    super.key,
    this.fit = BoxFit.cover,
    this.natural = false,
  });
  @override
  Widget build(BuildContext context) {
    Widget fallback() => SizedBox(
      height: natural ? 140 : null,
      child: ColoredBox(
        color: heroMuted.withValues(alpha: .10),
        child: const Center(
          child: Icon(Icons.image_outlined, color: heroMuted, size: 30),
        ),
      ),
    );
    final local = File(entry.path);
    if (entry.path.isNotEmpty && local.existsSync()) {
      return Image.file(
        local,
        fit: fit,
        frameBuilder: (_, child, frame, __) =>
            frame == null ? fallback() : child,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }
    if (entry.thumbnail.startsWith('http')) {
      return Image.network(
        entry.thumbnail,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (_, child, event) => event == null ? child : fallback(),
      );
    }
    return fallback();
  }
}

Future<void> copyEntry(
  BuildContext context,
  AlbumEntry entry, [
  String format = 'rawurl',
]) async {
  await Clipboard.setData(
    ClipboardData(text: getFormatedUrl(entry.url, entry.name, format)),
  );
  if (context.mounted) {
    heroSnack(
      context,
      '已复制 ${format == 'rawurl'
          ? '链接'
          : format == 'markdown'
          ? 'Markdown'
          : 'Discuz'}',
    );
  }
}

Future<void> chooseTarget(
  BuildContext context,
  PicoraController controller,
  VoidCallback openRepositories, {
  bool defaultOnly = false,
}) async {
  final config = await heroSheet<RepositoryConfig>(
    context,
    ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .7,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                defaultOnly ? '默认图床' : '上传到哪里？',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('选择一个已配置的存储位置', style: TextStyle(color: heroMuted)),
              const SizedBox(height: 20),
              if (controller.repositories.isEmpty)
                HeroEmpty(
                  icon: Icons.cloud_outlined,
                  title: '还没有配置图床',
                  message: '添加你的第一个存储位置，开始上传。',
                  action: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      openRepositories();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('前往图床列表'),
                  ),
                ),
              for (final item in controller.repositories)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: RepositoryBadge(item.spec),
                  title: Text(item.name),
                  subtitle: Text(
                    item.spec.name,
                    style: const TextStyle(color: heroMuted, fontSize: 12),
                  ),
                  trailing: Icon(
                    (defaultOnly
                                ? controller.defaultId
                                : controller.target?.id) ==
                            item.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color:
                        (defaultOnly
                                ? controller.defaultId
                                : controller.target?.id) ==
                            item.id
                        ? heroBlue
                        : heroMuted,
                    size: 21,
                  ),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (config == null) return;
  try {
    if (defaultOnly) {
      await controller.setDefault(config);
    } else {
      controller.selectTarget(config);
    }
    if (context.mounted) {
      heroSnack(context, '${defaultOnly ? '默认图床已设为' : '将上传到'} ${config.name}');
    }
  } catch (e) {
    if (context.mounted) heroSnack(context, e.toString());
  }
}

class UploadPage extends StatelessWidget {
  final PicoraController controller;
  final VoidCallback openRepositories, openAlbum;
  const UploadPage({
    super.key,
    required this.controller,
    required this.openRepositories,
    required this.openAlbum,
  });
  Future<void> _upload(
    BuildContext context,
    Future<List<AlbumEntry>> Function() action,
  ) async {
    try {
      final result = await action();
      if (context.mounted && result.isNotEmpty) {
        heroSnack(
          context,
          '${result.length} 张图片上传成功',
          action: SnackBarAction(label: '查看相册', onPressed: openAlbum),
        );
      }
    } catch (e, stack) {
      final message =
          controller.failure ?? controller.describeError('上传', e, stack);
      if (context.mounted) heroSnack(context, message);
    }
  }

  Future<void> _pick(BuildContext context, bool camera) async {
    if (controller.target == null) {
      await chooseTarget(context, controller, openRepositories);
      return;
    }
    try {
      if (camera) {
        do {
          final image = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 100,
          );
          if (image != null && context.mounted) {
            await _upload(context, () => controller.uploadFiles([image.path]));
          }
          if (image == null || controller.failure != null) break;
        } while (controller.continuousCamera && context.mounted);
      } else {
        final files = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );
        final paths =
            files?.files.map((f) => f.path).whereType<String>().toList() ?? [];
        if (paths.isNotEmpty && context.mounted) {
          await _upload(context, () => controller.uploadFiles(paths));
        }
      }
    } catch (e, stack) {
      final message = controller.describeError(
        camera ? '相机' : '选择图片',
        e,
        stack,
      );
      if (context.mounted) heroSnack(context, message);
    }
  }

  Future<void> _links(BuildContext context) async {
    final input = await heroSheet<String>(context, const LinkUploadSheet());
    if (input != null && context.mounted) {
      await _upload(context, () => controller.uploadLinks(input));
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('upload'),
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.pendingSharedPaths.isNotEmpty) ...[
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '收到 ${controller.pendingSharedPaths.length} 张系统传入图片',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () async {
                                final paths = List<String>.from(
                                  controller.pendingSharedPaths,
                                );
                                await _upload(
                                  context,
                                  () => controller.uploadFiles(paths),
                                );
                                if (controller.failure == null) {
                                  controller.clearSharedPaths();
                                }
                              },
                        icon: const Icon(Icons.arrow_upward_rounded),
                        label: const Text('上传这些图片'),
                      ),
                    ),
                    IconButton(
                      tooltip: '移除传入图片',
                      onPressed: controller.clearSharedPaths,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        Center(
          child: SizedBox(
            width: double.infinity,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: controller.busy
                    ? null
                    : () => chooseTarget(context, controller, openRepositories),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (controller.target != null)
                        RepositoryBadge(controller.target!.spec, size: 32)
                      else
                        const Icon(Icons.cloud_outlined, color: heroBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '当前上传目标',
                              style: TextStyle(color: heroMuted, fontSize: 10),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              controller.target?.name ?? '选择一个图床',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: heroMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        HeroPanel(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: _UploadAction(
                  icon: Icons.photo_library_outlined,
                  label: '相册上传',
                  primary: true,
                  onTap: controller.busy ? null : () => _pick(context, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UploadAction(
                  icon: Icons.camera_alt_outlined,
                  label: '拍照上传',
                  onTap: controller.busy ? null : () => _pick(context, true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UploadAction(
                  icon: Icons.link_rounded,
                  label: '链接上传',
                  onTap: controller.busy ? null : () => _links(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        HeroPanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.find_replace_rounded, color: heroBlue),
            title: const Text(
              '一键替换图床',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '迁移 Markdown 中的图片链接',
              style: TextStyle(fontSize: 11, color: heroMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: heroMuted),
            onTap: controller.busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MarkdownMigrationPage(controller: controller),
                    ),
                  ),
          ),
        ),
        if (controller.busy) ...[
          const SizedBox(height: 18),
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.activity, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: controller.progress == 0 ? null : controller.progress,
                  borderRadius: BorderRadius.circular(10),
                ),
              ],
            ),
          ),
        ],
        if (controller.failure != null) ...[
          const SizedBox(height: 14),
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.failure!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
                if (controller.failedPath != null)
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => _upload(
                            context,
                            () => controller.uploadFiles([
                              controller.failedPath!,
                            ]),
                          ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试这张图片'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SectionLabel(
          '最近上传',
          trailing: TextButton(
            onPressed: openAlbum,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('全部记录', style: TextStyle(fontSize: 12)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 15),
              ],
            ),
          ),
        ),
        if (controller.latest == null)
          HeroPanel(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: heroMuted.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.history_rounded, color: heroMuted),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '暂无上传记录',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '成功上传后，链接会出现在这里',
                        style: TextStyle(fontSize: 11, color: heroMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          LatestUploadCard(controller.latest!),
      ],
    ),
  );
}

class _UploadAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  const _UploadAction({
    required this.icon,
    required this.label,
    this.primary = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: primary ? heroBlue : Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: primary ? Colors.white : heroBlue, size: 25),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: primary ? Colors.white : null,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LatestUploadCard extends StatelessWidget {
  final AlbumEntry entry;
  const LatestUploadCard(this.entry, {super.key});
  @override
  Widget build(BuildContext context) => HeroPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 56, height: 56, child: EntryImage(entry)),
            ),
            const SizedBox(width: 13),
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
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF45AD8B),
                        size: 12,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '已上传至 ${hostSpec(entry.host).name}',
                        style: const TextStyle(color: heroMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '复制链接',
              onPressed: () => copyEntry(context, entry),
              icon: const Icon(Icons.copy_rounded, size: 19, color: heroBlue),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final item in [
          ('URL', 'rawurl'),
          ('MD', 'markdown'),
          ('BB', 'bbcode'),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => copyEntry(context, entry, item.$2),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          item.$1,
                          style: const TextStyle(
                            color: heroBlue,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          getFormatedUrl(entry.url, entry.name, item.$2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: heroMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.copy_outlined,
                        color: heroMuted,
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class LinkUploadSheet extends StatefulWidget {
  const LinkUploadSheet({super.key});
  @override
  State<LinkUploadSheet> createState() => _LinkUploadSheetState();
}

class _LinkUploadSheetState extends State<LinkUploadSheet> {
  final _text = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '通过链接上传',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '下载图片后，上传到当前图床。每行一个链接。',
            style: TextStyle(color: heroMuted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: 'https://example.com/image.jpg',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (mounted) {
                setState(() {
                  _text.text = data?.text ?? '';
                });
              }
            },
            icon: const Icon(Icons.content_paste_rounded, size: 17),
            label: const Text('从剪贴板粘贴'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                try {
                  final links = _text.text.trim().split(RegExp(r'\s+'));
                  for (final text in links) {
                    PicoraController.imageUri(text);
                  }
                  Navigator.pop(context, _text.text.trim());
                } catch (e) {
                  setState(() => _error = e.toString());
                }
              },
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              label: const Text('下载并上传'),
            ),
          ),
        ],
      ),
    ),
  );
}
