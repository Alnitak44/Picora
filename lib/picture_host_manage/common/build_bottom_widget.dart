import 'package:flutter/material.dart';
import 'package:picora/hero/hero_theme.dart';

class FileBottomSheetWidget extends StatelessWidget {
  final Future<Widget> thumbnailWidget;
  final String fileName, fileDate;
  final List<BottomSheetAction> actions;
  const FileBottomSheetWidget({
    super.key,
    required this.thumbnailWidget,
    required this.fileName,
    required this.fileDate,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: heroMuted.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: FutureBuilder<Widget>(
                          future: thumbnailWidget,
                          builder: (_, s) =>
                              s.data ??
                              const Icon(
                                Icons.insert_drive_file_outlined,
                                color: heroMuted,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (fileDate.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              fileDate,
                              style: const TextStyle(
                                fontSize: 11,
                                color: heroMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                for (final action in actions)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      action.icon,
                      color: action.title.contains('删除')
                          ? Theme.of(context).colorScheme.error
                          : heroBlue,
                      size: 23,
                    ),
                    title: Text(
                      action.title,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: action.onTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class BottomSheetAction {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;
  BottomSheetAction({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });
}
