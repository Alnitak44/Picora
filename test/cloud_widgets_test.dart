import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/picture_host_manage/common/base_file_explorer_page.dart';
import 'package:picora/picture_host_manage/common/loading_state.dart';
import 'package:picora/picture_host_manage/common/rename_dialog_widgets.dart';
import 'package:picora/picture_host_manage/imgur/imgur_login.dart';
import 'package:picora/picture_host_manage/upyun/upyun_login.dart';
import 'package:picora/utils/common_functions.dart';

class FixtureExplorer extends BaseFileExplorer {
  const FixtureExplorer({super.key});
  @override
  FixtureExplorerState createState() => FixtureExplorerState();
}

class FixtureExplorerState extends BaseFileExplorerState<FixtureExplorer> {
  int downloads = 0;
  void sortByName() => setState(
    () => sortListWithDirectories(
      (a, b, _) => a['name'].compareTo(b['name']),
      true,
    ),
  );
  @override
  Future<void> initializeData() async {
    allInfoList = [
      {'name': 'second.png', 'size': 12},
      {'name': 'first.png', 'size': 24},
    ];
    selectedFilesBool = [false, false];
    state = LoadState.success;
  }

  @override
  Future<void> refreshData() async {}
  @override
  Future<void> deleteFiles(List<int> indices) async {
    for (final index in indices.toList()..sort((a, b) => b.compareTo(a))) {
      allInfoList.removeAt(index);
      selectedFilesBool.removeAt(index);
    }
    setState(() {});
  }

  @override
  Future<String> getShareUrl(int index) async =>
      'https://example.com/${getFileName(index)}';
  @override
  String getFileDate(int index) => '2026-10-05';
  @override
  Future<Widget> getThumbnailWidget(int index) async =>
      const Icon(Icons.image_outlined);
  @override
  Future<void> onFileItemTap(int index) async {}
  @override
  Future<void> onDownloadButtonPressed() async {
    downloads++;
  }
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  bool narrow = false,
}) async {
  tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: heroTheme(narrow ? Brightness.dark : Brightness.light),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cloud batch actions and sorting preserve file identity', (
    tester,
  ) async {
    final key = GlobalKey<FixtureExplorerState>();
    await mount(tester, FixtureExplorer(key: key));
    expect(find.text('second.png'), findsOneWidget);
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2'), findsOneWidget);
    await tester.tap(find.byTooltip('下载所选文件'));
    expect(key.currentState!.downloads, 1);
    key.currentState!.sortByName();
    await tester.pumpAndSettle();
    expect(key.currentState!.getFileName(0), 'first.png');
    expect(key.currentState!.selectedFilesBool, [false, false]);
    expect(find.text('选择文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cloud file sheet and confirmed deletion work at 320px in dark mode',
    (tester) async {
      final key = GlobalKey<FixtureExplorerState>();
      await mount(tester, FixtureExplorer(key: key), narrow: true);
      await tester.tap(find.byTooltip('文件操作').first);
      await tester.pumpAndSettle();
      expect(find.text('文件详情'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('确定要删除second.png吗？'), findsOneWidget);
      expect(key.currentState!.allInfoList.length, 2);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(key.currentState!.allInfoList.length, 1);
      expect(key.currentState!.getFileName(0), 'first.png');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation awaits async work and cancellation does not invoke it',
    (tester) async {
      var calls = 0;
      var finished = false;
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showCupertinoAlertDialogWithConfirmFunc(
                  context: context,
                  content: '测试操作',
                  onConfirm: () async {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 50),
                    );
                    calls++;
                  },
                );
                finished = true;
              },
              child: const Text('开始'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(finished, true);
      finished = false;
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(finished, true);
    },
  );

  testWidgets('rename rejects an empty name and retains cover-file choice', (
    tester,
  ) async {
    final text = TextEditingController();
    addTearDown(text.dispose);
    bool? cover;
    await mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => RenameDialog(
                contentWidget: RenameDialogContent(
                  title: '重命名',
                  renameTextController: text,
                  isShowCoverFileWidget: true,
                  onCancel: () {},
                  onConfirm: (v) => cover = v,
                ),
              ),
            ),
            child: const Text('开始'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsOneWidget);
    expect(cover, isNull);
    await tester.enterText(find.byType(TextFormField), 'new.png');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(cover, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cloud login masks credentials and validates before making requests',
    (tester) async {
      await mount(tester, const UpyunLogIn(), narrow: true);
      final password = tester.widget<TextFormField>(
        find.byType(TextFormField).last,
      );
      expect(password.controller!.text, isEmpty);
      await tester.ensureVisible(find.text('登录管理空间'));
      await tester.tap(find.text('登录管理空间'));
      await tester.pumpAndSettle();
      expect(find.text('请输入用户名'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, const ImgurLogIn(), narrow: true);
      await tester.ensureVisible(find.text('连接 Imgur').last);
      await tester.tap(find.text('连接 Imgur').last);
      await tester.pumpAndSettle();
      expect(find.text('请输入访问令牌'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
