import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:picora/hero/hero_theme.dart';

void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  heroSnack(context, '已复制到剪贴板');
}

Widget buildInfoSection(String title, List<Widget> children) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
  child: HeroPanel(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionLabel(title),
        ),
        ...children,
      ],
    ),
  ),
);
Widget buildInfoItem({
  required BuildContext context,
  required String title,
  required String value,
  required IconData icon,
  bool copyable = false,
}) => ListTile(
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
  leading: Icon(icon, color: heroBlue, size: 21),
  title: Text(title, style: const TextStyle(fontSize: 12, color: heroMuted)),
  subtitle: Padding(
    padding: const EdgeInsets.only(top: 5),
    child: SelectableText(
      value,
      style: const TextStyle(fontSize: 14, height: 1.5),
    ),
  ),
  trailing: copyable
      ? IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy_rounded, size: 17, color: heroMuted),
          onPressed: () => copyToClipboard(context, value),
        )
      : null,
);
Widget buildFeatureCard({
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
}) => Card(
  child: InkWell(
    borderRadius: BorderRadius.circular(24),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: heroBlue.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: heroBlue, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: heroMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 20, color: heroMuted),
        ],
      ),
    ),
  ),
);
