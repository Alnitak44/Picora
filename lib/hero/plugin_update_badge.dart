import 'package:flutter/material.dart';

const pluginUpdateColor = Color(0xFF16846B);

class PluginUpdateBadge extends StatelessWidget {
  const PluginUpdateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: pluginUpdateColor.withValues(alpha: dark ? .22 : .10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '可更新',
        style: TextStyle(
          color: dark ? const Color(0xFF72DCC2) : pluginUpdateColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
