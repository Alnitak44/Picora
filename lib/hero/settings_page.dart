import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:picora/utils/global.dart';
import 'package:picora/utils/clear_cache.dart';
import 'controller.dart';
import 'hero_theme.dart';
import 'diagnostics_page.dart';
import 'upload_page.dart';
import 'config_exchange.dart';
import 'plugin_page.dart';
import 'filename_template_sheet.dart';
import 'app_updates.dart';
import 'app_update_sheet.dart';
import 'diagnostics.dart';

class SettingsPage extends StatefulWidget {
  final PicoraController controller;
  final VoidCallback openRepositories;
  final AppUpdateService? updateService;
  final Future<PackageInfo> Function()? appInfoLoader;
  const SettingsPage({
    super.key,
    required this.controller,
    required this.openRepositories,
    this.updateService,
    this.appInfoLoader,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PackageInfo? _appInfo;
  bool _checkingUpdate = false;
  late final AppUpdateService _updates =
      widget.updateService ?? AppUpdateService();

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<PackageInfo> _readAppInfo() =>
      (widget.appInfoLoader ?? PackageInfo.fromPlatform)();

  Future<void> _loadAppInfo() async {
    try {
      final info = await _readAppInfo();
      if (mounted) setState(() => _appInfo = info);
    } catch (error, stack) {
      HeroDiagnostics.instance.record('读取应用版本', error, stack: stack);
    }
  }

  String _updateFailure(Object error, StackTrace stack) {
    final logged = widget.controller.describeError('应用更新', error, stack);
    if (error is! DioException) return logged;
    final status = error.response?.statusCode;
    final message = status == 403 || status == 429
        ? 'GitHub 请求受限，请稍后重试'
        : error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout
        ? '连接 GitHub 超时，请检查网络后重试'
        : '获取更新失败，请查看诊断日志';
    return '$message · ${logged.split(' · ').last}';
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = _appInfo ?? await _readAppInfo();
      final release = await _updates.latest(forceRefresh: true);
      if (!mounted) return;
      setState(() => _appInfo = info);
      if (release == null) {
        heroSnack(context, '尚无正式发布版本');
      } else if (!release.isNewerThan(info.version)) {
        heroSnack(context, '已是最新版本（${info.version}）');
      } else {
        await heroSheet<void>(
          context,
          AppUpdateSheet(
            release: release,
            installedVersion: info.version,
            describeError: _updateFailure,
          ),
        );
      }
    } catch (error, stack) {
      final message = _updateFailure(error, stack);
      if (mounted) heroSnack(context, message);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        HeroPanel(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 60, endIndent: 18),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget _row(
    String title,
    IconData icon, {
    String? subtitle,
    String? value,
    VoidCallback? tap,
    bool? toggle,
    ValueChanged<bool>? change,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    leading: Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: heroBlue.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 18, color: heroBlue),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: const TextStyle(color: heroMuted, fontSize: 10, height: 1.7),
          ),
    onTap: tap,
    trailing: toggle != null
        ? Transform.scale(
            scale: .78,
            child: Switch.adaptive(value: toggle, onChanged: change),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: heroMuted, fontSize: 11),
                  ),
                ),
              const SizedBox(width: 5),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: heroMuted,
              ),
            ],
          ),
  );
  Future<void> _guard(String operation, Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e, stack) {
      if (mounted) {
        heroSnack(
          context,
          widget.controller.describeError(operation, e, stack),
        );
      }
    }
  }

  Future<String?> _choose(
    String title,
    Map<String, String> options,
    String current,
  ) => heroSheet<String>(
    context,
    Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          for (final entry in options.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value, style: const TextStyle(fontSize: 14)),
              trailing: Icon(
                current == entry.key
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: current == entry.key ? heroBlue : heroMuted,
                size: 21,
              ),
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    ),
  );
  Future<String?> _text(String title, String initial, String hint) async {
    final controller = TextEditingController(text: initial);
    final result = await heroSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(hintText: hint),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    Navigator.pop(context, controller.text.trim());
                  }
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
    // The sheet route still animates with this field attached after pop.
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    return result;
  }

  Future<void> _linkFormat() async {
    final choice = await _choose('复制链接格式', {
      'rawurl': '原始链接',
      'markdown': 'Markdown',
      'bbcode': 'Discuz / BBCode',
      'html': 'HTML',
      'markdown_with_link': 'Markdown 带链接',
      'custom': '自定义格式',
    }, Global.defaultLKformat);
    if (choice == null || !mounted) return;
    if (choice == 'custom') {
      final format = await _text(
        '自定义链接格式',
        Global.customLinkFormat,
        r'可使用 $url / $fileName / $ext',
      );
      if (format == null) return;
      Global.setCustomLinkFormat(format);
    }
    Global.setLKformat(choice);
    if (mounted) setState(() {});
  }

  Future<void> _rename() async {
    final current = Global.isCustomRename
        ? 'custom'
        : Global.isTimeStamp
        ? 'timestamp'
        : Global.isRandomName
        ? 'random'
        : 'original';
    final choice = await _choose('文件命名方式', {
      'original': '保留原文件名',
      'timestamp': '时间戳',
      'random': '随机字符串',
      'custom': '自定义命名',
    }, current);
    if (choice == null || !mounted) return;
    if (choice == 'custom') {
      final format = await heroSheet<String>(
        context,
        FilenameTemplateSheet(initial: Global.customRenameFormat),
      );
      if (format == null) return;
      Global.setCustomeRenameFormat(format);
    }
    Global.setIsTimeStamp(choice == 'timestamp');
    Global.setIsRandomName(choice == 'random');
    Global.setIsCustomeRename(choice == 'custom');
    if (mounted) setState(() {});
  }

  Future<void> _compress() async {
    double quality = Global.quality.toDouble();
    final width = TextEditingController(text: '${Global.minWidth}');
    final height = TextEditingController(text: '${Global.minHeight}');
    String format = Global.defaultCompressFormat;
    String? error;
    await heroSheet<void>(
      context,
      StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '图片压缩',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 22),
                const Text(
                  '输出格式',
                  style: TextStyle(color: heroMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: ['webp', 'jpg', 'png', 'avif']
                      .map(
                        (v) => ChoiceChip(
                          label: Text(v.toUpperCase()),
                          selected: v == format,
                          onSelected: (_) => update(() => format = v),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                Text(
                  '图片质量 · ${quality.round()}%',
                  style: const TextStyle(fontSize: 13),
                ),
                Slider(
                  value: quality,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  onChanged: (v) => update(() => quality = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: width,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '最小宽度（px）',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: height,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '最小高度（px）',
                        ),
                      ),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final w = int.tryParse(width.text),
                          h = int.tryParse(height.text);
                      if (w == null ||
                          h == null ||
                          w < 1 ||
                          h < 1 ||
                          w > 20000 ||
                          h > 20000) {
                        update(() => error = '请填写 1–20000 范围内的像素尺寸');
                        return;
                      }
                      Global.setQuality(quality.round());
                      Global.setminWidth(w);
                      Global.setminHeight(h);
                      Global.setDefaultCompressFormat(format);
                      Navigator.pop(context);
                    },
                    child: const Text('保存压缩设置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      width.dispose();
      height.dispose();
    });
    if (mounted) setState(() {});
  }

  Future<void> _import({bool scan = false}) async {
    String? text;
    if (scan) {
      text = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const ConfigScanner()));
    } else {
      text = await heroSheet<String>(context, const ConfigImportSheet());
    }
    if (text == null) return;
    await _guard('导入配置', () async {
      final count = await ConfigExchange.import(widget.controller, text!);
      if (mounted) heroSnack(context, '已导入 $count 组配置');
    });
  }

  Future<void> _export() async {
    if (widget.controller.repositories.isEmpty) {
      heroSnack(context, '还没有可以导出的配置');
      return;
    }
    final choice = await _choose('导出配置', {
      'native': '完整备份 · Picora JSON',
      'picgo': '默认图床 · PicGo / PicList',
    }, 'native');
    if (choice == null) return;
    await _guard('导出配置', () async {
      final configs = widget.controller.repositories;
      final content = choice == 'native'
          ? ConfigExchange.export(configs)
          : ConfigExchange.exportPicGo(
              configs.firstWhere(
                (c) => c.id == widget.controller.defaultId,
                orElse: () => configs.first,
              ),
            );
      final file = File(
        '${(await getTemporaryDirectory()).path}/Picora-config.json',
      );
      await file.writeAsString(content);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Picora 配置备份（包含图床密钥，请妥善保管）');
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('settings'),
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 130),
    children: [
      _group('上传设置', [
        _row(
          '默认图床',
          Icons.cloud_outlined,
          value:
              widget.controller.repositories
                  .where((r) => r.id == widget.controller.defaultId)
                  .firstOrNull
                  ?.name ??
              '未设置',
          tap: () => chooseTarget(
            context,
            widget.controller,
            widget.openRepositories,
            defaultOnly: true,
          ),
        ),
        _row(
          '连续拍照上传',
          Icons.camera_alt_outlined,
          subtitle: '上传完成后，再次打开相机',
          toggle: widget.controller.continuousCamera,
          change: widget.controller.setContinuousCamera,
        ),
        _row(
          '上传后自动复制',
          Icons.copy_outlined,
          toggle: Global.isCopyLink,
          change: (v) => setState(() => Global.setIsCopyLink(v)),
        ),
        _row(
          '链接格式',
          Icons.link_rounded,
          value:
              {
                'rawurl': 'URL',
                'markdown': 'Markdown',
                'bbcode': 'Discuz',
                'html': 'HTML',
                'custom': '自定义',
              }[Global.defaultLKformat] ??
              '带链接 MD',
          tap: _linkFormat,
        ),
        _row(
          'URL 编码',
          Icons.code_rounded,
          subtitle: '复制时编码链接中的特殊字符',
          toggle: Global.isURLEncode,
          change: (v) => setState(() => Global.setIsURLEncode(v)),
        ),
        _row(
          '文件命名',
          Icons.drive_file_rename_outline_rounded,
          value: Global.isCustomRename
              ? '自定义'
              : Global.isTimeStamp
              ? '时间戳'
              : Global.isRandomName
              ? '随机'
              : '保留原名',
          tap: _rename,
        ),
      ]),
      _group('图片处理', [
        _row(
          '上传前压缩',
          Icons.photo_size_select_large_rounded,
          subtitle: '节省存储空间，适合较大的图片',
          toggle: Global.isCompress,
          change: (v) => setState(() => Global.setIsCompress(v)),
        ),
        _row(
          '压缩参数',
          Icons.tune_rounded,
          value:
              '${Global.defaultCompressFormat.toUpperCase()} · ${Global.quality}%',
          tap: _compress,
        ),
      ]),
      _group('外观', [
        _row(
          '主题模式',
          Icons.palette_outlined,
          value: {
            'light': '浅色',
            'system': '自动',
            'dark': '深色',
          }[widget.controller.themeChoice],
          tap: () async {
            final choice = await _choose('主题模式', {
              'light': '浅色',
              'system': '自动',
              'dark': '深色',
            }, widget.controller.themeChoice);
            if (choice != null) {
              await _guard('切换主题', () => widget.controller.setTheme(choice));
            }
          },
        ),
      ]),
      _group('配置与数据', [
        _row(
          '插件中心',
          Icons.extension_outlined,
          subtitle: '安装、停用或导出 Picora 图床插件',
          tap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PluginCenterPage(controller: widget.controller),
            ),
          ),
        ),
        _row(
          '导入配置',
          Icons.download_outlined,
          subtitle: '兼容 PicGo / PicList / Picora JSON',
          tap: () => _import(),
        ),
        _row(
          '扫码导入',
          Icons.qr_code_scanner_rounded,
          tap: () => _import(scan: true),
        ),
        _row('导出与备份', Icons.ios_share_rounded, tap: _export),
        _row(
          '清理缓存',
          Icons.cleaning_services_outlined,
          subtitle: '仅清理临时文件，保留配置和上传记录',
          tap: () => _guard('清理缓存', () async {
            if (widget.controller.busy) {
              heroSnack(context, '上传进行中，请稍后清理缓存');
              return;
            }
            await CacheUtil.clear();
            if (context.mounted) heroSnack(context, '缓存已清理');
          }),
        ),
        _row(
          '清空上传记录',
          Icons.history_rounded,
          tap: () async {
            final choice = await _choose('清空所有上传记录？', {
              'cancel': '保留记录',
              'clear': '清空记录 · 保留本地和云端图片',
            }, 'cancel');
            if (choice == 'clear') {
              await _guard('清空记录', () async {
                await widget.controller.clearHistory();
                if (context.mounted) heroSnack(context, '上传记录已清空');
              });
            }
          },
        ),
      ]),
      _group('删除偏好', [
        _row(
          '同步删除云端文件',
          Icons.cloud_off_outlined,
          subtitle: '删除记录时，删除图床中的原文件',
          toggle: Global.isDeleteCloud,
          change: (v) => setState(() => Global.setIsDeleteCloud(v)),
        ),
        _row(
          '同步删除本地原图',
          Icons.delete_outline_rounded,
          subtitle: '会删除设备上的原始图片，请按需开启',
          toggle: Global.isDeleteLocal,
          change: (v) => setState(() => Global.setIsDeleteLocal(v)),
        ),
      ]),
      _group('支持与诊断', [
        _row(
          '诊断日志',
          Icons.receipt_long_outlined,
          subtitle: '错误详情、请求状态、堆栈与日志导出',
          tap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
        ),
        _row(
          '检查更新',
          Icons.system_update_rounded,
          value: _checkingUpdate ? '检查中…' : null,
          tap: _checkingUpdate ? null : _checkUpdate,
        ),

        _row(
          '项目与版本记录',
          Icons.open_in_new_rounded,
          subtitle: '基于 PicHoro v3.0.1',
          value: _appInfo?.version,
          tap: () => _guard('打开项目', () async {
            await launchUrl(
              Uri.parse('https://github.com/Alnitak44/Picora'),
              mode: LaunchMode.externalApplication,
            );
          }),
        ),
        _row(
          '关于 Picora',
          Icons.info_outline_rounded,
          tap: () => showAboutDialog(
            context: context,
            applicationName: 'Picora',
            applicationVersion: _appInfo?.version ?? '版本信息不可用',
            applicationIcon: Image.asset(
              'assets/images/picora.png',
              width: 48,
              height: 48,
              cacheWidth: 144,
            ),
            children: [
              const Text(
                'Android 图床与对象存储聚合客户端。\n基于 PicHoro v3.0.1，Picora 独立维护版本。\nMIT License\n© 2026 Alnitak44 与 Picora 贡献者。\n保留 Kuingsmile / PicHoro 的原有版权声明。',
              ),
            ],
          ),
        ),
      ]),
    ],
  );
}

class ConfigImportSheet extends StatefulWidget {
  const ConfigImportSheet({super.key});
  @override
  State<ConfigImportSheet> createState() => _ConfigImportSheetState();
}

class _ConfigImportSheetState extends State<ConfigImportSheet> {
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
            '导入配置',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '粘贴 JSON 配置，导入为新的图床配置。',
            style: TextStyle(color: heroMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: '{ "picBed": { … } }',
              errorText: _error,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (mounted) _text.text = data?.text ?? '';
            },
            icon: const Icon(Icons.content_paste_outlined, size: 17),
            label: const Text('从剪贴板粘贴'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                try {
                  ConfigExchange.parse(_text.text);
                  Navigator.pop(context, _text.text);
                } catch (e) {
                  setState(() => _error = e.toString());
                }
              },
              child: const Text('导入图床配置'),
            ),
          ),
        ],
      ),
    ),
  );
}

class ConfigScanner extends StatefulWidget {
  const ConfigScanner({super.key});
  @override
  State<ConfigScanner> createState() => _ConfigScannerState();
}

class _ConfigScannerState extends State<ConfigScanner> {
  final _scanner = MobileScannerController();
  bool _done = false;
  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('扫描配置二维码', style: TextStyle(fontSize: 16)),
    ),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              final text = capture.barcodes.firstOrNull?.rawValue;
              if (!_done && text != null) {
                _done = true;
                Navigator.pop(context, text);
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '将 PicGo / PicList 的配置二维码放入画面',
            style: TextStyle(color: heroMuted, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
