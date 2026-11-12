import 'package:flutter/material.dart';

const pluginUpdateColor = Color(0xFF16846B);

class PluginUpdateBadge extends StatelessWidget {
  const PluginUpdateBadge({this.dense = false, super.key});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: pluginUpdateColor.withValues(alpha: dark ? .22 : .10),
        borderRadius: BorderRadius.circular(dense ? 6 : 8),
      ),
      child: Text(
        '可更新',
        style: TextStyle(
          color: dark ? const Color(0xFF72DCC2) : pluginUpdateColor,
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
