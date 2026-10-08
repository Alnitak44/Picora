import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:picora/hero/hero_theme.dart';

Widget getSlidableAction({
  required IconData icon,
  required Color backgroundColor,
  Color foregroundColor = Colors.white,
  required void Function(BuildContext context) onPressed,
  required String label,
  String position = 'left',
}) => SlidableAction(
  onPressed: onPressed,
  backgroundColor: label.contains('删除') ? const Color(0xFFDC5667) : heroBlue,
  foregroundColor: foregroundColor,
  icon: icon,
  label: label,
  borderRadius: BorderRadius.circular(20),
);

Widget getFileListWidget({
  required BuildContext context,
  required List<Widget> slidableActions,
  required bool isSelected,
  required Future<Widget> thumbnailWidget,
  required String fileName,
  required String fileDate,
  String? fileSize,
  required VoidCallback onButtonPressed,
  required VoidCallback onTap,
  required VoidCallback onLongPress,
  required Widget mshCheckbox,
}) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
  child: Slidable(
    endActionPane: slidableActions.isEmpty
        ? null
        : ActionPane(motion: const ScrollMotion(), children: slidableActions),
    child: Material(
      color: isSelected
          ? heroBlue.withValues(alpha: .09)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 24, height: 24, child: mshCheckbox),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: FutureBuilder<Widget>(
                    future: thumbnailWidget,
                    builder: (_, snapshot) =>
                        snapshot.data ??
                        const ColoredBox(
                          color: Color(0xFFEFF3FB),
                          child: Icon(
                            Icons.insert_drive_file_outlined,
                            color: heroMuted,
                          ),
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (fileDate.isNotEmpty) fileDate,
                        if (fileSize != null) fileSize,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: heroMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '文件操作',
                onPressed: onButtonPressed,
                icon: const Icon(Icons.more_horiz_rounded, color: heroMuted),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
