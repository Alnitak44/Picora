import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:flutter/services.dart' as flutter_services;
import 'package:picora/picture_host_manage/common/build_bottom_widget.dart';

import 'package:picora/picture_host_manage/common/file_list_widget.dart';
import 'package:picora/widgets/common_widgets.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:path/path.dart' as my_path;
import 'package:share_plus/share_plus.dart';
import 'package:msh_checkbox/msh_checkbox.dart';

import 'package:picora/picture_host_manage/common/common_widget.dart';
import 'package:picora/picture_host_manage/common/loading_state.dart'
    as loading_state;
import 'package:picora/utils/common_functions.dart';

abstract class BaseFileExplorer extends StatefulWidget {
  const BaseFileExplorer({super.key});

  @override
  BaseFileExplorerState createState();
}

abstract class BaseFileExplorerState<T extends BaseFileExplorer>
    extends loading_state.BaseLoadingPageState<T> {
  List allInfoList = [];
  List fileAllInfoList = [];
  List dirAllInfoList = [];
  List selectedFilesBool = [];
  bool sorted = true;
  RefreshController refreshController = RefreshController(
    initialRefresh: false,
  );

  @override
  void initState() {
    super.initState();
    dirAllInfoList.clear();
    allInfoList.clear();
    fileAllInfoList.clear();
    initializeData();
  }

  // Abstract methods to be implemented by subclasses
  Future<void> initializeData();
  Future<void> refreshData();
  Future<void> deleteFiles(List<int> toDelete);

  bool isShowSortByDate() {
    return true;
  }

  // Optional abstract methods with default implementations
  Future<String> getShareUrl(int index);
  String getFileName(int index) => allInfoList[index]['name'];

  Map<String, String> getHeaders(int index) => {};

  Future<Widget> getThumbnailWidget(int index) async {
    Map<String, String> headers = getHeaders(index);

    return index < dirAllInfoList.length
        ? const Icon(Icons.folder_rounded, color: heroBlue, size: 40)
        : iconImageLoad(
            await getShareUrl(index),
            getFileName(index),
            headers: headers,
          );
  }

  String getFileDate(int index);
  String? getFileSizeForList(int index) {
    int size = int.parse(
      (allInfoList[index]['size'] ?? 0).toString().split('.')[0],
    );
    return size > 0 ? getFileSize(size) : null;
  }

  String getPageTitle() => '文件';

  @override
  AppBar get appBar => buildAppBar();

  void onRefresh() async {
    await refreshData();
    refreshController.refreshCompleted();
  }

  @override
  void dispose() {
    refreshController.dispose();
    super.dispose();
  }

  List<Widget> getSlidableActions(int index) {
    return [
      getSlidableAction(
        onPressed: (BuildContext context) async {
          String shareUrl = await getShareUrl(index);
          Share.share(shareUrl);
        },
        backgroundColor: const Color.fromARGB(255, 109, 196, 116),
        icon: Icons.share,
        label: '分享',
        position: 'left',
      ),
      getSlidableAction(
        onPressed: (BuildContext context) async {
          showCupertinoAlertDialogWithConfirmFunc(
            context: context,
            content: '确定要删除${getFileName(index)}吗？',
            onConfirm: () async {
              try {
                await deleteFiles([index]);
                showToast('删除完成');
              } catch (e) {
                flogErr(e, {}, runtimeType.toString(), "delete_button");
                showToast('删除失败');
              }
            },
          );
        },
        backgroundColor: const Color(0xFFFE4A49),
        icon: Icons.delete,
        label: '删除',
        position: 'right',
      ),
    ];
  }

  Widget buildFloatingActionButton() {
    final selected = selectedFilesBool.where((item) => item == true).length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: heroMuted.withValues(alpha: .12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: selected > 0 ? '取消全选' : '全选',
                onPressed: onSelectAllButtonPressed,
                icon: Icon(
                  selected > 0
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  color: heroBlue,
                ),
              ),
              Text(
                selected > 0 ? '已选 $selected' : '选择文件',
                style: const TextStyle(fontSize: 11, color: heroMuted),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: '下载所选文件',
                onPressed: selected > 0 ? onDownloadButtonPressed : null,
                icon: const Icon(Icons.download_rounded),
              ),
              IconButton(
                tooltip: '复制所选链接',
                onPressed: selected > 0 ? onCopyButtonPressed : null,
                icon: const Icon(Icons.copy_rounded, size: 21),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void onSelectAllButtonPressed() {
    if (allInfoList.isEmpty) {
      showToastWithContext(context, '目录为空');
      return;
    } else if (selectedFilesBool.contains(true)) {
      setState(() {
        for (int i = 0; i < selectedFilesBool.length; i++) {
          selectedFilesBool[i] = false;
        }
      });
    } else {
      setState(() {
        for (int i = 0; i < selectedFilesBool.length; i++) {
          selectedFilesBool[i] = true;
        }
      });
    }
  }

  void onCopyButtonPressed() async {
    if (!selectedFilesBool.contains(true)) {
      showToastWithContext(context, '请先选择文件');
      return;
    } else {
      List multiUrls = [];
      for (int i = 0; i < allInfoList.length; i++) {
        if (!selectedFilesBool[i]) continue;
        String? rawurl = await getShareUrl(i) as String?;
        if (rawurl != null && rawurl.isNotEmpty) {
          String fileName = getFileName(i);
          multiUrls.add(getFormatedUrl(rawurl, fileName));
        }
      }
      if (!mounted) return;
      if (multiUrls.isEmpty) {
        showToastWithContext(context, '没有可复制的链接');
        return;
      }
      await flutter_services.Clipboard.setData(
        flutter_services.ClipboardData(text: multiUrls.join('\n')),
      );
      if (mounted) {
        showToastWithContext(context, '已复制全部链接');
      }
    }
  }

  // Subclasses should implement this
  Future<void> onDownloadButtonPressed();

  @override
  void onErrorRetry() {
    setState(() {
      state = loading_state.LoadState.loading;
    });
    initializeData();
  }

  isAbnormalState() {
    return state == loading_state.LoadState.error ||
        state == loading_state.LoadState.loading ||
        state == loading_state.LoadState.empty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(),
      body: buildStateWidget,
      floatingActionButtonLocation: isAbnormalState()
          ? null
          : FloatingActionButtonLocation.centerFloat,
      floatingActionButton: isAbnormalState()
          ? null
          : buildFloatingActionButton(),
    );
  }

  AppBar buildAppBar() {
    return AppBar(
      elevation: 0,
      flexibleSpace: getFlexibleSpace(context),
      leading: getLeadingIcon(context),
      titleSpacing: 0,
      title: titleText(getPageTitle()),
      actions: buildAppBarActions(),
    );
  }

  // Default sort options, can be overridden by subclasses
  List<PopupMenuItem> getSortMenuItems() {
    return [
      if (isShowSortByDate())
        buildSortMenuItem(
          '修改时间排序',
          (a, b, ascending) => ascending
              ? getFormatedFileDate(a).compareTo(getFormatedFileDate(b))
              : getFormatedFileDate(b).compareTo(getFormatedFileDate(a)),
        ),
      buildSortMenuItem(
        '文件名称排序',
        (a, b, ascending) => ascending
            ? getFormatedFileName(a).compareTo(getFormatedFileName(b))
            : getFormatedFileName(b).compareTo(getFormatedFileName(a)),
      ),
      buildSortMenuItem('文件大小排序', (a, b, ascending) {
        return ascending
            ? getFormatedSize(a).compareTo(getFormatedSize(b))
            : getFormatedSize(b).compareTo(getFormatedSize(a));
      }),
      buildSortMenuItem('文件类型排序', (a, b, ascending) {
        return ascending
            ? getFormatedExtension(a).compareTo(getFormatedExtension(b))
            : getFormatedExtension(b).compareTo(getFormatedExtension(a));
      }),
    ];
  }

  // Helper for building sort menu items
  PopupMenuItem buildSortMenuItem(
    String title,
    int Function(dynamic a, dynamic b, bool ascending) comparator,
  ) {
    return PopupMenuItem(
      child: Center(child: Text(title, style: const TextStyle(fontSize: 15))),
      onTap: () {
        setState(() {
          bool ascending = !sorted;
          sortListWithDirectories(comparator, ascending);
          sorted = ascending;
        });
      },
    );
  }

  // Default implementation for sorting with directories preserved
  void sortListWithDirectories(
    int Function(dynamic a, dynamic b, bool ascending) comparator,
    bool ascending,
  ) {
    selectedFilesBool = List.filled(allInfoList.length, false);
    if (dirAllInfoList.isEmpty) {
      allInfoList.sort((a, b) => comparator(a, b, ascending));
    } else {
      List temp = allInfoList.sublist(
        dirAllInfoList.length,
        allInfoList.length,
      );
      temp.sort((a, b) => comparator(a, b, ascending));
      allInfoList = [...dirAllInfoList, ...temp];
    }
  }

  // Helper method to extract DateTime from an item (override as needed)
  DateTime getFormatedFileDate(dynamic item) {
    return DateTime.parse(item['created_at']);
  }

  // Helper method to format URL (override as needed)
  String getFormatedFileName(dynamic item) => item['name'] ?? '';

  int getFormatedSize(dynamic item) {
    return item['size'] ?? 0;
  }

  String getFormatedExtension(dynamic item) {
    return getFormatedFileName(item).split('.').last;
  }

  List<Widget> getExtraAppBarActions() {
    return [];
  }

  // Build the app bar actions
  List<Widget> buildAppBarActions() {
    return [
      ...getExtraAppBarActions(),
      PopupMenuButton(
        icon: const Icon(Icons.sort_rounded, size: 25),
        position: PopupMenuPosition.under,
        itemBuilder: (BuildContext context) => getSortMenuItems(),
      ),
      // Add/upload button
      IconButton(
        onPressed: () => showUploadOptions(context),
        icon: const Icon(Icons.add, size: 30),
      ),
      // Download management button
      IconButton(
        onPressed: () => navigateToDownloadManagement(),
        icon: const Icon(Icons.sync_alt_rounded, size: 25),
      ),
      // Delete button
      IconButton(
        icon: selectedFilesBool.contains(true)
            ? const Icon(
                Icons.delete,
                color: Color.fromARGB(255, 236, 127, 120),
                size: 30.0,
              )
            : const Icon(Icons.delete_outline, size: 30.0),
        onPressed: () => onDeleteButtonPressed(),
      ),
    ];
  }

  // Methods to override in subclasses
  void showUploadOptions(BuildContext context) {
    // Default implementation
    showToastWithContext(
      context,
      'Override this method to implement upload options',
    );
  }

  void navigateToDownloadManagement() async {
    // Default implementation
    showToast('Override this method to implement download management');
  }

  void onDeleteButtonPressed() {
    if (!selectedFilesBool.contains(true) || selectedFilesBool.isEmpty) {
      showToastWithContext(context, '没有选择文件');
      return;
    }

    showCupertinoAlertDialogWithConfirmFunc(
      title: '删除全部文件',
      content: '是否删除全部选择的文件？\n请谨慎选择!',
      context: context,
      onConfirm: () async {
        try {
          List<int> toDelete = [];
          for (int i = 0; i < allInfoList.length; i++) {
            if (selectedFilesBool[i]) {
              toDelete.add(i);
            }
          }
          await deleteFiles(toDelete);
          showToast('删除完成');
        } catch (e) {
          flogErr(e, {}, runtimeType.toString(), "deleteAll_button");
          showToast('删除失败');
        }
      },
    );
  }

  @override
  Widget buildSuccess() {
    if (allInfoList.isEmpty) {
      return buildEmpty();
    }
    return SmartRefresher(
      controller: refreshController,
      enablePullDown: true,
      enablePullUp: false,
      header: const ClassicHeader(
        refreshStyle: RefreshStyle.Follow,
        idleText: '下拉刷新',
        refreshingText: '正在刷新',
        completeText: '刷新完成',
        failedText: '刷新失败',
        releaseText: '释放刷新',
      ),
      footer: const ClassicFooter(
        loadStyle: LoadStyle.ShowWhenLoading,
        idleText: '上拉加载',
        loadingText: '正在加载',
        noDataText: '没有更多啦',
        failedText: '没有更多啦',
        canLoadingText: '释放加载',
      ),
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 120),
        itemCount: allInfoList.length,
        itemBuilder: (context, index) {
          return getFileListWidget(
            context: context,
            slidableActions: getSlidableActions(index),
            isSelected: selectedFilesBool[index],
            fileName: getFileName(index),
            thumbnailWidget: getThumbnailWidget(index),
            fileDate: getFileDate(index),
            fileSize: getFileSizeForList(index),
            onButtonPressed: () => showBottomActionSheet(context, index),
            onTap: () => onFileItemTap(index),
            onLongPress: () {
              setState(() {
                selectedFilesBool[index] = !selectedFilesBool[index];
              });
            },
            mshCheckbox: MSHCheckbox(
              colorConfig: MSHColorConfig.fromCheckedUncheckedDisabled(
                checkedColor: Theme.of(context).primaryColor,
                uncheckedColor: Colors.grey,
                disabledColor: Colors.grey.withValues(alpha: 0.5),
              ),
              size: 18,
              value: selectedFilesBool[index],
              style: MSHCheckboxStyle.fillScaleCheck,
              onChanged: (selected) {
                setState(() {
                  selectedFilesBool[index] = selected;
                });
              },
            ),
          );
        },
      ),
    );
  }

  void showBottomActionSheet(BuildContext context, int index) {
    showModalBottomSheet(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      context: context,
      builder: (context) {
        return buildBottomSheetWidget(context, index);
      },
    );
  }

  List<BottomSheetAction> getExtraActions(int index) {
    return [];
  }

  void onFileInfoTap(int index) {
    // Default implementation
    showToast('Override this method to implement file info tap action');
  }

  Widget buildBottomSheetWidget(BuildContext context, int index) {
    return FileBottomSheetWidget(
      thumbnailWidget: getThumbnailWidget(index),
      fileName: getFileName(index),
      fileDate: getFileDate(index),
      actions: [
        if (index >= dirAllInfoList.length)
          BottomSheetAction(
            icon: Icons.info_outline_rounded,
            iconColor: const Color.fromARGB(255, 97, 141, 236),
            title: '文件详情',
            onTap: () {
              Navigator.pop(context);
              onFileInfoTap(index);
            },
          ),
        if (index >= dirAllInfoList.length)
          BottomSheetAction(
            icon: Icons.link_rounded,
            iconColor: const Color.fromARGB(255, 97, 141, 236),
            title: '复制链接(设置中的默认格式)',
            onTap: () async {
              await flutter_services.Clipboard.setData(
                flutter_services.ClipboardData(
                  text: getFormatedUrl(
                    await getShareUrl(index),
                    my_path.basename(getFileName(index)),
                  ),
                ),
              );
              if (context.mounted) {
                Navigator.pop(context);
              }
              showToast('复制完毕');
            },
          ),
        if (index >= dirAllInfoList.length)
          BottomSheetAction(
            icon: Icons.share,
            iconColor: const Color.fromARGB(255, 76, 175, 80),
            title: '分享链接',
            onTap: () async {
              Navigator.pop(context);
              Share.share(await getShareUrl(index));
            },
          ),
        ...getExtraActions(index),
        BottomSheetAction(
          icon: Icons.delete_outline,
          iconColor: const Color.fromARGB(255, 240, 85, 131),
          title: '删除',
          onTap: () async {
            Navigator.pop(context);
            showCupertinoAlertDialogWithConfirmFunc(
              context: context,
              title: '通知',
              content: '确定要删除${getFileName(index)}吗？',
              onConfirm: () async {
                try {
                  await deleteFiles([index]);
                  showToast('删除完成');
                } catch (e) {
                  flogErr(e, {}, runtimeType.toString(), "delete_button");
                  showToast('删除失败');
                }
              },
            );
          },
        ),
      ],
    );
  }

  // Method to be overridden by subclasses
  Future<void> onFileItemTap(int index);
}
