import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'hero_theme.dart';
import 'diagnostics.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});
  Future<void> _export(BuildContext context) async {
    try {
      final file = await HeroDiagnostics.instance.export();
      await Share.shareXFiles([XFile(file.path)], text: 'Picora 诊断日志（已脱敏）');
    } catch (e) {
      if (context.mounted) heroSnack(context, '日志导出失败');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('诊断日志', style: TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          tooltip: '导出日志',
          onPressed: () => _export(context),
          icon: const Icon(Icons.ios_share_rounded),
        ),
        IconButton(
          tooltip: '清空日志',
          onPressed: () async {
            final clear = await heroSheet<bool>(
              context,
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '清空诊断记录？',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认清空'),
                    ),
                  ],
                ),
              ),
            );
            if (clear == true) await HeroDiagnostics.instance.clear();
          },
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: HeroDiagnostics.instance,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '记录异常编号、时间、操作、请求状态与堆栈。\n密钥与认证信息自动隐藏，最多保留 300 条。',
            style: TextStyle(color: heroMuted, fontSize: 12, height: 1.8),
          ),
          const SizedBox(height: 20),
          if (HeroDiagnostics.instance.entries.isEmpty)
            const HeroPanel(
              child: HeroEmpty(
                icon: Icons.task_alt_rounded,
                title: '一切运行正常',
                message: '出现问题时，诊断记录会显示在这里。',
              ),
            ),
          for (final entry in HeroDiagnostics.instance.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: HeroPanel(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text(
                    entry['operation'] ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${entry['time']} · #${entry['id']}',
                    style: const TextStyle(color: heroMuted, fontSize: 10),
                  ),
                  leading: const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFE77878),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SelectableText(
                            const JsonEncoder.withIndent('  ').convert(entry),
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.6,
                              fontFamily: 'monospace',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: jsonEncode(entry)),
                              );
                              if (context.mounted) {
                                heroSnack(context, '已复制诊断记录');
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            label: const Text('复制此记录'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
