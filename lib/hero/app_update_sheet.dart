import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';
import 'diagnostics.dart';
import 'hero_theme.dart';

class AppUpdateSheet extends StatefulWidget {
  final AppRelease release;
  final String installedVersion;
  final String Function(Object, StackTrace) describeError;
  const AppUpdateSheet({
    super.key,
    required this.release,
    required this.installedVersion,
    required this.describeError,
  });
  @override
  State<AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<AppUpdateSheet> {
  StreamSubscription<OtaEvent>? _events;
  bool _downloading = false;
  int? _progress;
  String? _status, _error;

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _fail(Object error, StackTrace stack) {
    final message = widget.describeError(error, stack);
    if (mounted) {
      setState(() {
        _downloading = false;
        _error = message;
      });
    }
  }

  Future<void> _openRelease() async {
    try {
      if (!await launchUrl(
        widget.release.page,
        mode: LaunchMode.externalApplication,
      )) {
        throw const HeroFailure('无法打开 Release 页面');
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  Future<void> _install() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
      _status = '准备下载';
    });
    try {
      if (!Platform.isAndroid) throw const HeroFailure('请从 Release 页面下载对应安装包');
      final ota = OtaUpdate();
      final abi = await ota.getAbi();
      if (!mounted) return;
      final apk = widget.release.apkFor(abi ?? '');
      if (apk == null) {
        throw const HeroFailure('此 Release 没有匹配当前设备的 APK，请查看发布页面');
      }
      await _events?.cancel();
      if (!mounted) return;
      _events = ota
          .execute(
            apk.url.toString(),
            destinationFilename: 'Picora-update.apk',
            sha256checksum: apk.sha256,
            androidProviderAuthority:
                'io.github.alnitak44.picora.ota_update_provider',
          )
          .listen(
            (event) {
              if (!mounted) return;
              if (event.status == OtaStatus.DOWNLOADING) {
                setState(() {
                  _progress = int.tryParse(event.value ?? '');
                  _status = '下载中';
                });
              } else if (event.status == OtaStatus.INSTALLING) {
                setState(() {
                  _downloading = false;
                  _progress = 100;
                  _status = '已打开系统安装界面';
                });
              } else {
                final message = switch (event.status) {
                  OtaStatus.PERMISSION_NOT_GRANTED_ERROR =>
                    '请允许 Picora 安装未知来源应用后重试',
                  OtaStatus.CHECKSUM_ERROR => '安装包校验失败，请重新下载',
                  OtaStatus.ALREADY_RUNNING_ERROR => '已有更新正在下载，请稍后再试',
                  _ => '更新下载失败，请查看诊断日志或打开发布页面',
                };
                final detail = HeroFailure(
                  '$message（${event.status.name}: ${event.value ?? '-'}）',
                );
                final logged = widget.describeError(detail, StackTrace.current);
                setState(() {
                  _downloading = false;
                  _error = '$message · ${logged.split(' · ').last}';
                });
              }
            },
            onError: (Object error, StackTrace stack) => _fail(error, stack),
            onDone: () {
              if (mounted && _downloading) {
                setState(() {
                  _downloading = false;
                  _error = '下载已结束但未确认安装，请重试或查看发布页面';
                });
              }
            },
          );
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发现新版本 ${widget.release.tag}',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '当前版本 ${widget.installedVersion}',
            style: const TextStyle(color: heroMuted, fontSize: 13),
          ),
          if (widget.installedVersion.contains('-debug')) ...[
            const SizedBox(height: 12),
            const Text(
              '当前为调试版。正式版签名可能不同，安装前可先导出配置。',
              style: TextStyle(color: heroMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          if (widget.release.notes.trim().isNotEmpty)
            MarkdownBody(
              data: widget.release.notes,
              imageBuilder: (_, _, _) => const SizedBox.shrink(),
              onTapLink: (_, href, _) async {
                final uri = Uri.tryParse(href ?? '');
                if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                  return;
                }
                try {
                  if (!await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw const HeroFailure('无法打开更新日志链接');
                  }
                } catch (error, stack) {
                  _fail(error, stack);
                }
              },
            )
          else
            const Text('此版本未提供更新日志。', style: TextStyle(color: heroMuted)),
          if (_status != null) ...[
            const SizedBox(height: 20),
            Text(_progress == null ? _status! : '$_status $_progress%'),
          ],
          if (_downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _progress == null ? null : _progress!.clamp(0, 100) / 100,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _downloading ? null : _install,
              child: Text(_downloading ? '正在下载' : '下载并安装'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _openRelease,
              child: const Text('打开发布页面'),
            ),
          ),
        ],
      ),
    ),
  );
}
