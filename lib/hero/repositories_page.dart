import 'package:flutter/material.dart';
import 'package:picora/router/application.dart';
import 'package:picora/router/routers.dart';
import 'dart:convert';
import 'package:picora/picture_host_manage/manage_api/upyun_manage_api.dart';
import 'controller.dart';
import 'models.dart';

import 'hero_theme.dart';
import 'upload_page.dart';
import 'plugin_page.dart';

Future<void> addRepository(
  BuildContext context,
  PicoraController controller,
) async {
  final spec = await heroSheet<HostSpec>(
    context,
    RepositoryTypePicker(controller: controller),
  );
  if (spec != null && context.mounted) {
    await editRepository(context, controller, spec);
  }
}

class RepositoryTypePicker extends StatefulWidget {
  final PicoraController controller;
  const RepositoryTypePicker({super.key, required this.controller});

  @override
  State<RepositoryTypePicker> createState() => _RepositoryTypePickerState();
}

class _RepositoryTypePickerState extends State<RepositoryTypePicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final specs = widget.controller.availableHostSpecs.where((spec) {
      if (query.isEmpty) return true;
      final aliases = switch (spec.id) {
        'aws' => 'AWS S3 Amazon Backblaze Backlaze B2 Cloudflare R2 MinIO',
        'aliyun' => 'Alibaba OSS',
        'tencent' => 'Tencent COS',
        'qiniu' => 'Kodo',
        'upyun' => 'USS',
        'alist' => 'OpenList',
        _ => '',
      };
      return '${spec.name} ${spec.description} ${spec.id} $aliases'
          .toLowerCase()
          .contains(query);
    }).toList();
    final media = MediaQuery.of(context);
    return SizedBox(
      height: (media.size.height - media.viewInsets.bottom) * .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择图床类型',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '同一图床类型可添加多组独立配置。',
              style: TextStyle(color: heroMuted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _search,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索图床或存储服务',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: specs.isEmpty
                  ? const HeroEmpty(
                      icon: Icons.search_off_rounded,
                      title: '没有找到图床类型',
                      message: '换一个名称或关键词试试。',
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: specs.length,
                      itemBuilder: (context, index) {
                        final spec = specs[index];
                        const shape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        );
                        return Material(
                          type: MaterialType.transparency,
                          shape: shape,
                          clipBehavior: Clip.antiAlias,
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              highlightColor: heroBlue.withValues(alpha: .06),
                              splashColor: heroBlue.withValues(alpha: .10),
                            ),
                            child: ListTile(
                              shape: shape,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              leading: RepositoryBadge(spec),
                              title: Text(
                                spec.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                spec.description,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: heroMuted,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: heroMuted,
                              ),
                              onTap: () => Navigator.pop(context, spec),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> editRepository(
  BuildContext context,
  PicoraController controller,
  HostSpec spec, {
  RepositoryConfig? existing,
}) async {
  if (spec.isRuntimePlugin &&
      !controller.installedPlugins.any((plugin) => plugin.hostId == spec.id)) {
    heroSnack(context, '请先从模块仓库下载对应插件，已有配置已保留');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PluginCenterPage(controller: controller),
      ),
    );
    return;
  }
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RepositoryEditor(
        controller: controller,
        spec: spec,
        existing: existing,
      ),
    ),
  );
  if (result == true && context.mounted) {
    heroSnack(context, existing == null ? '图床已添加' : '配置已保存');
  }
}

class RepositoriesPage extends StatelessWidget {
  final PicoraController controller;
  const RepositoriesPage({super.key, required this.controller});
  Future<void> _actions(BuildContext context, RepositoryConfig config) async {
    final action = await heroSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: RepositoryBadge(config.spec),
              title: Text(
                config.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(config.spec.name),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑配置'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.star_outline_rounded),
              title: const Text('设为默认图床'),
              onTap: () => Navigator.pop(context, 'default'),
            ),
            if (config.spec.canBrowse)
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('浏览云端文件'),
                onTap: () => Navigator.pop(context, 'browse'),
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除配置',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    try {
      if (action == 'edit') {
        await editRepository(
          context,
          controller,
          config.spec,
          existing: config,
        );
      } else if (action == 'default') {
        await controller.setDefault(config);
        if (context.mounted) heroSnack(context, '已设为默认图床');
      } else if (action == 'delete') {
        final confirmed = await heroSheet<bool>(
          context,
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '删除这组配置？',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  '${config.name}\n上传记录和云端图片都会保留。',
                  style: const TextStyle(color: heroMuted, height: 1.8),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除配置'),
                  ),
                ),
              ],
            ),
          ),
        );
        if (confirmed == true) {
          await controller.deleteRepository(config);
          if (context.mounted) heroSnack(context, '配置已删除');
        }
      } else if (action == 'browse') {
        await controller.activateForBrowser(config);
        if (!context.mounted) return;
        final routes = {
          'aliyun': Routes.aliyunBucketList,
          'tencent': Routes.tencentBucketList,
          'qiniu': Routes.qiniuBucketList,
          'upyun': Routes.upyunBucketList,
          'aws': Routes.awsBucketList,
          'github': Routes.githubManageHomePage,
          'lsky.pro': Routes.lskyproManageHomePage,
          'sm.ms': Routes.smmsManageHomePage,
          'imgur': Routes.imgurTokenManagePage,
          'ftp': Routes.sftpFileExplorer,
          'alist': Routes.alistBucketList,
          'webdav': Routes.webdavFileExplorer,
        };
        var route = routes[config.host]!;
        if (config.host == 'webdav' || config.host == 'ftp') {
          final prefix = config.host == 'ftp'
              ? config.values['ftpHomeDir']
              : '/';
          route +=
              '?element=${Uri.encodeComponent(jsonEncode(config.values))}&bucketPrefix=${Uri.encodeComponent(prefix == 'None' ? '/' : prefix.toString())}';
        }
        if (config.host == 'upyun') {
          final auth = await UpyunManageAPI().readUpyunManageConfig();
          if (auth == 'Error' || auth.isEmpty) route = Routes.upyunLogIn;
        }
        if (!context.mounted) return;
        await Application.router.navigateTo(context, route);
        await controller.loadImages();
      }
    } catch (e, stack) {
      if (context.mounted) {
        heroSnack(context, controller.describeError('图床配置操作', e, stack));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ListView(
        key: const PageStorageKey('repositories'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 150),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '图床列表',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '插件中心',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PluginCenterPage(controller: controller),
                  ),
                ),
                icon: const Icon(Icons.extension_outlined),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: '添加图床',
                onPressed: controller.busy
                    ? null
                    : () => addRepository(context, controller),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${controller.repositories.length} 个图床配置',
            style: const TextStyle(color: heroMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          if (controller.repositories.isEmpty)
            HeroPanel(
              child: HeroEmpty(
                icon: Icons.cloud_queue_rounded,
                title: '暂无图床配置',
                message: '添加图床或存储桶，配置完成后即可上传。',
                action: FilledButton.icon(
                  onPressed: () => addRepository(context, controller),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加图床'),
                ),
              ),
            )
          else
            ...controller.repositories.map(
              (config) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    onTap: () => _actions(context, config),
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          RepositoryBadge(config.spec, size: 48),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        config.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (config.id == controller.defaultId) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: heroBlue.withValues(
                                            alpha: .08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          '默认',
                                          style: TextStyle(
                                            color: heroBlue,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${config.spec.name} · ${config.location}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: heroMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.more_horiz_rounded,
                            color: heroMuted,
                            size: 21,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      if (controller.repositories.isNotEmpty)
        Positioned(
          right: 24,
          bottom: 110,
          child: FloatingActionButton.extended(
            heroTag: 'add-repository',
            onPressed: controller.busy
                ? null
                : () => addRepository(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('添加图床'),
          ),
        ),
    ],
  );
}

class RepositoryEditor extends StatefulWidget {
  final PicoraController controller;
  final HostSpec spec;
  final RepositoryConfig? existing;
  const RepositoryEditor({
    super.key,
    required this.controller,
    required this.spec,
    this.existing,
  });
  @override
  State<RepositoryEditor> createState() => _RepositoryEditorState();
}

class _RepositoryEditorState extends State<RepositoryEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _fields = <String, TextEditingController>{};
  final _toggles = <String, bool>{};
  bool _saving = false, _visible = false;
  @override
  void initState() {
    super.initState();
    _name.text = widget.existing?.name ?? widget.spec.name;
    for (final field in widget.spec.fields) {
      final value = widget.existing?.values[field.key] ?? field.defaultValue;
      if (field.isToggle) {
        _toggles[field.key] = value == true || value == 'true';
      } else {
        _fields[field.key] = TextEditingController(
          text: value == null || value == 'None' || value == 'undetermined'
              ? ''
              : value.toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(HostField field, String? text) {
    final value = text?.trim() ?? '';
    if (field.required && value.isEmpty) return '请填写${field.label}';
    if (value.isEmpty) return null;
    if ([
          'host',
          'customUrl',
          'customDomain',
          'url',
          'ftpCustomUrl',
          'proxy',
        ].contains(field.key) &&
        !value.startsWith('http://') &&
        !value.startsWith('https://')) {
      return '请输入以 http:// 或 https:// 开头的地址';
    }
    if (field.key == 'ftpPort' &&
        (int.tryParse(value) == null ||
            int.parse(value) < 1 ||
            int.parse(value) > 65535)) {
      return '端口范围为 1–65535';
    }
    if ([
          'strategy_id',
          'album_id',
          'antiLeechExpiration',
        ].contains(field.key) &&
        int.tryParse(value) == null) {
      return '请输入整数';
    }
    if (field.key == 'endpoint' && value.contains('://')) {
      return 'Endpoint 不包含协议，请使用下方 HTTPS 开关';
    }
    return null;
  }

  Widget _field(HostField field) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: field.isToggle
        ? SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(field.label, style: const TextStyle(fontSize: 13)),
            value: _toggles[field.key]!,
            onChanged: (v) => setState(() => _toggles[field.key] = v),
          )
        : field.choices != null
        ? DropdownButtonFormField<String>(
            initialValue: field.choices!.contains(_fields[field.key]!.text)
                ? _fields[field.key]!.text
                : field.choices!.first,
            decoration: InputDecoration(labelText: field.label),
            items: field.choices!
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) {
              _fields[field.key]!.text = v!;
            },
          )
        : TextFormField(
            controller: _fields[field.key],
            obscureText: field.secret && !_visible,
            autocorrect: !field.secret,
            enableSuggestions: !field.secret,
            style: const TextStyle(fontSize: 13),
            validator: (v) => _validate(field, v),
            decoration: InputDecoration(
              labelText: '${field.label}${field.required ? ' *' : ''}',
              hintText: field.hint.isEmpty ? null : field.hint,
              suffixIcon: field.secret
                  ? IconButton(
                      tooltip: _visible ? '隐藏密钥' : '显示密钥',
                      onPressed: () => setState(() => _visible = !_visible),
                      icon: Icon(
                        _visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 19,
                      ),
                    )
                  : null,
            ),
          ),
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{
        for (final field in widget.spec.fields)
          field.key: field.isToggle
              ? _toggles[field.key]
              : _fields[field.key]!.text.trim(),
      };
      if (widget.spec.id == 'alist' && values['adminToken'] == '') {
        values['adminToken'] = values['token'];
      }
      await widget.controller.saveRepository(
        widget.spec,
        _name.text,
        values,
        existing: widget.existing,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      if (mounted) {
        heroSnack(context, widget.controller.describeError('保存配置', e, stack));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.spec.fields.where((f) => f.required).toList();
    final optional = widget.spec.fields.where((f) => !f.required).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? '添加图床' : '编辑图床',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
          children: [
            Row(
              children: [
                RepositoryBadge(widget.spec, size: 54),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.spec.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.spec.description,
                        style: const TextStyle(color: heroMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('配置名称'),
                  TextFormField(
                    controller: _name,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入图床配置名称' : null,
                    decoration: InputDecoration(
                      hintText: widget.spec.id == 'aws'
                          ? '例如 Backblaze / Amazon'
                          : '例如 ${widget.spec.name} / 备用配置',
                      helperText: '这个名称只标识当前配置，同一图床可继续添加其他配置。',
                      helperMaxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('连接与认证'),
                  ...required.map(_field),
                ],
              ),
            ),
            if (optional.isNotEmpty) ...[
              const SizedBox(height: 18),
              HeroPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('更多选项'),
                    ...optional.map(_field),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            const Text(
              '保存后可在上传页选择此图床配置。',
              textAlign: TextAlign.center,
              style: TextStyle(color: heroMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? '正在保存' : '保存配置'),
            ),
          ],
        ),
      ),
    );
  }
}
