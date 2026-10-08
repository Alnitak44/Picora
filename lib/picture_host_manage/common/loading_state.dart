import 'package:flutter/material.dart';
import 'package:picora/hero/hero_theme.dart';

enum LoadState { loading, empty, error, success }

abstract class BaseLoadingPageState<T extends StatefulWidget> extends State<T> {
  LoadState? state;
  @override
  void initState() {
    super.initState();
    state = LoadState.loading;
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: appBar, body: buildStateWidget);
  Widget get buildStateWidget => switch (state) {
    LoadState.empty => buildEmpty(),
    LoadState.loading => buildLoading(),
    LoadState.success => buildSuccess(),
    _ => buildError(),
  };
  String get emptyText => '这里还没有文件，可以添加一个。';
  List<Widget> get extraEmptyWidgets => [];
  String get errorText => '云端数据加载失败';
  String get errorButtonText => '重新加载';
  void onErrorRetry() => setState(() => state = LoadState.loading);
  Widget buildEmpty() => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HeroEmpty(
              icon: Icons.cloud_queue_rounded,
              title: '一片新的空间',
              message: emptyText,
            ),
            ...extraEmptyWidgets,
          ],
        ),
      ),
    ),
  );
  Widget buildError() => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: HeroEmpty(
          icon: Icons.wifi_off_rounded,
          title: errorText,
          message: '请检查网络和仓库配置，诊断日志可查看错误详情。',
          action: FilledButton.icon(
            onPressed: onErrorRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(errorButtonText),
          ),
        ),
      ),
    ),
  );
  Widget buildLoading() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        SizedBox(height: 18),
        Text('正在连接云端…', style: TextStyle(fontSize: 12, color: heroMuted)),
      ],
    ),
  );
  Widget buildSuccess();
  AppBar get appBar;
}
