import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Shared by plugin tutorials and release notes.
MarkdownStyleSheet picoraMarkdownStyle(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final foreground = theme.textTheme.bodyMedium!.color!;
  final panel = dark ? const Color(0xFF1B2940) : const Color(0xFFEDF2FA);
  final link = dark ? const Color(0xFF9ABEFF) : const Color(0xFF2458C6);
  final body = theme.textTheme.bodyMedium!.copyWith(
    color: foreground,
    fontSize: 14,
    height: 1.65,
  );
  TextStyle heading(double size) =>
      body.copyWith(fontSize: size, height: 1.35, fontWeight: FontWeight.w700);
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    textScaler: MediaQuery.textScalerOf(context),
    p: body,
    a: body.copyWith(color: link, decoration: TextDecoration.underline),
    h1: heading(24),
    h2: heading(20),
    h3: heading(18),
    h4: heading(16),
    h5: heading(15),
    h6: heading(14),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
    blockSpacing: 14,
    listIndent: 24,
    listBullet: body,
    listBulletPadding: const EdgeInsets.only(right: 6),
    blockquote: body,
    blockquotePadding: const EdgeInsets.all(14),
    blockquoteDecoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: link.withValues(alpha: .25)),
    ),
    code: body.copyWith(
      fontFamily: 'monospace',
      fontSize: 13,
      backgroundColor: panel,
      height: 1.55,
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(12),
    ),
    tableHead: body.copyWith(fontWeight: FontWeight.w700),
    tableBody: body,
    tableHeadAlign: TextAlign.left,
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableScrollbarThumbVisibility: true,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
    ),
  );
}
