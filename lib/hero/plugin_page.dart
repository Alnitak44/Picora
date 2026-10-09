import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'hero_theme.dart';
import 'markdown_style.dart';

import 'module_repository_page.dart';
import 'plugins/plugin_manifest.dart';
import 'plugins/plugin_package.dart';
import 'upload_page.dart';

class PluginCenterPage extends StatefulWidget {
  final PicoraController controller;
  const PluginCenterPage({super.key, required this.controller});

  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage> {
  bool _working = false;

  Future<void> _openPluginGuide() async {
    await _guard('打开插件开放说明', () async {
      final opened = await launchUrl(
        Uri.parse(
          'https://github.com/Alnitak44/Picora/blob/main/%E6%8F%92%E4%BB%B6%E5%BC%80%E6%94%BE%E8%AF%B4%E6%98%8E.md',
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) heroSnack(context, '无法打开插件开放说明');
    });
  }

  Future<void> _guard(String operation, Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) setState(() {});
    } catch (error, stack) {
      final message = widget.controller.describeError(operation, error, stack);
      if (mounted) {
        heroSnack(context, message);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _install() async {
    final source = await heroSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '安装插件',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '导入包含介绍、程序和资源的 Picora ZIP 插件包。',
              style: TextStyle(color: heroMuted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('从 ZIP 文件导入'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language_rounded),
              title: const Text('从 URL 安装'),
              subtitle: const Text('HTTP / HTTPS ZIP 地址，上限 10 MB'),
              onTap: () => Navigator.pop(context, 'url'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    String? url;
    if (source == 'url') {
      url = await heroSheet<String>(context, const PluginUrlInputSheet());
      if (url == null || !mounted) return;
    }
    PicoraPluginPackage? package;
    Uint8List? bytes;
    await _guard('读取插件包', () async {
      if (source == 'file') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['zip'],
          withData: false,
        );
        final file = result?.files.single;
        if (file == null) return;
        if (file.size > PicoraPluginPackage.maxZipBytes) {
          throw const FormatException('插件 ZIP 不能超过 10 MB');
        }
        bytes = file.bytes;
        if (bytes == null && file.path != null) {
          final selected = File(file.path!);
          if (await selected.length() > PicoraPluginPackage.maxZipBytes) {
            throw const FormatException('插件 ZIP 不能超过 10 MB');
          }
          bytes = await selected.readAsBytes();
        }
        if (bytes == null) throw const FormatException('无法读取所选插件包');
      } else {
        bytes = await widget.controller.pluginManager.fetch(Uri.parse(url!));
      }
      package = widget.controller.pluginManager.inspectPackage(bytes!);
    });
    if (package == null || !mounted) return;
    final approved = await _review(package!);
    if (approved != true || !mounted) return;
    await _guard('安装插件', () async {
      final result = await widget.controller.installPluginPackage(bytes!);
      if (mounted) heroSnack(context, result.updated ? '插件已更新' : '插件已安装');
    });
  }

  void _readme(PicoraPluginManifest manifest) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PluginReadmePage(
          package: widget.controller.pluginManager.packageFor(manifest.id),
          controller: widget.controller,
        ),
      ),
    );
  }

  Future<void> _modules() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModuleRepositoryPage(
          controller: widget.controller,
          review: _review,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<bool?> _review(PicoraPluginPackage package) {
    final manifest = package.manifest;
    return heroSheet<bool>(
      context,
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RepositoryBadge(package.toHostSpec(), size: 52),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifest.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'v${manifest.version} · ${manifest.author}',
                        style: const TextStyle(color: heroMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(manifest.description),
            const SizedBox(height: 22),
            const SectionLabel('权限'),
            _permission(Icons.image_outlined, '读取你主动选择上传的文件'),
            _permission(
              Icons.language_rounded,
              '访问 ${manifest.permissions.networkHosts.join('、')}',
            ),
            if (manifest.delete != null)
              _permission(Icons.delete_outline_rounded, '可删除选中的云端图片；安装后默认关闭'),
            if (manifest.permissions.allowInsecureHttp)
              _permission(Icons.no_encryption_outlined, '允许使用明文 HTTP'),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('允许并安装'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permission(IconData icon, String text) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: heroBlue, size: 20),
    title: Text(text, style: const TextStyle(fontSize: 13)),
  );

  Future<void> _details(PicoraPluginManifest manifest) async {
    final githubUrl = _pluginGithubUrl(
      widget.controller.pluginManager.packageFor(manifest.id),
    );
    final action = await heroSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: RepositoryBadge(
                widget.controller.pluginManager
                    .packageFor(manifest.id)
                    .toHostSpec(),
              ),
              title: Text(manifest.name),
              subtitle: Text('v${manifest.version} · ${manifest.author}'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('插件主页与使用教程'),
              onTap: () => Navigator.pop(context, 'readme'),
            ),
            if (manifest.delete != null)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许删除选中的云端图片'),
                subtitle: const Text('仅在相册主动删除时使用；更新插件后需重新开启'),
                value: widget.controller.pluginManager.isCloudDeleteAllowed(
                  manifest.id,
                ),
                onChanged: _working
                    ? null
                    : (value) {
                        Navigator.pop(context);
                        _guard(
                          '修改删除权限',
                          () => widget.controller.setPluginCloudDelete(
                            manifest.id,
                            value,
                          ),
                        );
                      },
              ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('导出 ZIP 插件包'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            if (githubUrl != null)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('GitHub'),
                onTap: () => Navigator.pop(context, 'github'),
              ),

            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '卸载插件',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'readme') {
      _readme(manifest);
    } else if (action == 'share') {
      await _guard('导出插件包', () async {
        final file = File(
          '${(await getTemporaryDirectory()).path}/${manifest.id}.picora-plugin.zip',
        );
        await file.writeAsBytes(
          widget.controller.pluginManager.packageFor(manifest.id).bytes,
          flush: true,
        );
        await Share.shareXFiles([
          XFile(file.path),
        ], text: '${manifest.name} 插件');
      });
    } else if (action == 'github') {
      await _guard('打开 GitHub', () async {
        final opened = await launchUrl(
          Uri.parse(githubUrl!),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) heroSnack(context, '无法打开 GitHub');
      });
    } else if (action == 'remove') {
      final confirmed = await heroSheet<bool>(
        context,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '卸载这个插件？',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text('${manifest.name}\n上传记录会保留。请先删除使用它的图床配置。'),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('卸载插件'),
                ),
              ),
            ],
          ),
        ),
      );
      if (confirmed == true) {
        await _guard('卸载插件', () => widget.controller.removePlugin(manifest.id));
      }
    }
  }

  Widget _pluginCard(PicoraPluginManifest manifest) {
    final enabled = widget.controller.pluginManager.isEnabled(manifest.id);
    final example = widget.controller.pluginManager.isExample(manifest.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HeroPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RepositoryBadge(
                  widget.controller.pluginManager
                      .packageFor(manifest.id)
                      .toHostSpec(),
                  size: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifest.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'v${manifest.version} · ${manifest.author}',
                        style: const TextStyle(color: heroMuted, fontSize: 10),
                      ),
                      if (example)
                        const Text(
                          '示例',
                          style: TextStyle(color: heroBlue, fontSize: 10),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '插件详情',
                  onPressed: _working ? null : () => _details(manifest),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _readme(manifest),
                      icon: const Icon(Icons.menu_book_outlined, size: 16),
                      label: const Text('使用教程'),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: _working
                      ? null
                      : (value) => _guard(
                          value ? '启用插件' : '停用插件',
                          () => widget.controller.setPluginEnabled(
                            manifest.id,
                            value,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plugins = widget.controller.installedPlugins;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '插件中心',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: '插件开放说明',
            onPressed: _openPluginGuide,
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _install,
        icon: const Icon(Icons.add_rounded),
        label: const Text('安装插件'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
        children: [
          HeroPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.extension_outlined, color: heroBlue),
              title: const Text('模块仓库'),
              subtitle: const Text('发现、下载和更新图床插件'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _working ? null : _modules,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: SectionLabel('已安装插件')),
              Text(
                '${plugins.length} 个',
                style: const TextStyle(color: heroMuted, fontSize: 11),
              ),
            ],
          ),
          if (plugins.isEmpty)
            HeroPanel(
              child: HeroEmpty(
                icon: Icons.extension_outlined,
                title: '还没有安装插件',
                message: '从模块仓库下载插件，或导入本地 ZIP。',
                action: FilledButton.icon(
                  onPressed: _install,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('安装插件'),
                ),
              ),
            )
          else
            ...plugins.map(_pluginCard),
        ],
      ),
    );
  }
}

class PluginUrlInputSheet extends StatefulWidget {
  const PluginUrlInputSheet({super.key});

  @override
  State<PluginUrlInputSheet> createState() => _PluginUrlInputSheetState();
}

class PluginReadmePage extends StatelessWidget {
  final PicoraPluginPackage package;
  final PicoraController controller;
  const PluginReadmePage({
    super.key,
    required this.package,
    required this.controller,
  });

  Future<void> _open(BuildContext context, String href) async {
    try {
      final uri = Uri.tryParse(href);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        if (context.mounted) heroSnack(context, '仅支持打开 HTTP / HTTPS 网页链接');
        return;
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        heroSnack(context, '无法打开链接');
      }
    } catch (error, stack) {
      final message = controller.describeError('打开插件链接', error, stack);
      if (context.mounted) heroSnack(context, message);
    }
  }

  Widget _image(Uri uri, String? title, String? alt) {
    final label = alt ?? title ?? '资源图片';
    final fallback = Text(
      '$label（资源不可用）',
      style: const TextStyle(color: heroMuted),
    );
    // Tutorials only load package resources, never implicit remote trackers.
    if (uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
      return fallback;
    }
    var path = uri.path;
    if (path.startsWith('./')) path = path.substring(2);
    final bytes = package.resource(path);
    if (bytes == null) return fallback;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: path.toLowerCase().endsWith('.svg')
          ? SvgPicture.memory(
              bytes,
              fit: BoxFit.contain,
              semanticsLabel: label,
              errorBuilder: (_, error, stack) => fallback,
            )
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              semanticLabel: label,
              cacheWidth: 1000,
              errorBuilder: (_, error, stack) => fallback,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manifest = package.manifest;
    return Scaffold(
      appBar: AppBar(title: const Text('插件主页', style: TextStyle(fontSize: 17))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        children: [
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RepositoryBadge(package.toHostSpec(), size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            manifest.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'v${manifest.version} · ${manifest.author}',
                            style: const TextStyle(
                              color: heroMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(manifest.description),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    if (_pluginGithubUrl(package) != null)
                      TextButton.icon(
                        onPressed: () =>
                            _open(context, _pluginGithubUrl(package)!),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('GitHub'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          MarkdownBody(
            data: package.readme,
            selectable: true,
            imageBuilder: _image,
            onTapLink: (text, href, title) {
              if (href != null) _open(context, href);
            },
            styleSheet: picoraMarkdownStyle(context),
          ),
        ],
      ),
    );
  }
}

class _PluginUrlInputSheetState extends State<PluginUrlInputSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '从 URL 安装',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '插件 ZIP 地址',
            hintText: 'https://example.com/plugin.zip',
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final uri = Uri.tryParse(_controller.text.trim());
              if (uri != null &&
                  ['http', 'https'].contains(uri.scheme) &&
                  uri.host.isNotEmpty) {
                Navigator.pop(context, uri.toString());
              }
            },
            child: const Text('下载并检查'),
          ),
        ),
      ],
    ),
  );
}

String? _pluginGithubUrl(PicoraPluginPackage package) {
  for (final url in [package.repository, package.manifest.homepage]) {
    final uri = Uri.tryParse(url ?? '');
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'github.com' &&
        uri.userInfo.isEmpty) {
      return url;
    }
  }
  return null;
}
