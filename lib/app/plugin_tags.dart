import 'package:flutter/material.dart';

import 'hero_theme.dart';
import 'plugins/plugin_catalog.dart' show PluginTag;

const pluginAuthColor = Color(0xFFB26A00);

enum PluginTagTone { auth, info, accent }

class PluginTagChip extends StatelessWidget {
  const PluginTagChip(
    this.label, {
    this.tone = PluginTagTone.info,
    this.dense = false,
    super.key,
  });

  final String label;
  final PluginTagTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (tone) {
      PluginTagTone.auth => pluginAuthColor,
      PluginTagTone.info => heroMuted,
      PluginTagTone.accent => heroBlue,
    };
    final foreground = dark ? Color.lerp(color, Colors.white, .38)! : color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: dark ? .16 : .09),
        borderRadius: BorderRadius.circular(dense ? 6 : 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Auth state first, then one chip per declared role in a stable order.
List<Widget> pluginTagChips(
  Set<PluginTag> tags, {
  required bool requiresAuth,
  bool dense = false,
}) {
  final ordered = tags.toList()..sort((a, b) => a.index.compareTo(b.index));
  return [
    PluginTagChip(
      requiresAuth ? '需认证' : '无需认证',
      tone: PluginTagTone.auth,
      dense: dense,
    ),
    for (final tag in ordered)
      PluginTagChip(
        tag.label,
        tone: tag.isAuth ? PluginTagTone.info : PluginTagTone.accent,
        dense: dense,
      ),
  ];
}
