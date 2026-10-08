import 'package:flutter/material.dart';
import 'filename_template.dart';
import 'hero_theme.dart';

class FilenameTemplateSheet extends StatefulWidget {
  final String initial;
  const FilenameTemplateSheet({super.key, required this.initial});
  @override
  State<FilenameTemplateSheet> createState() => _FilenameTemplateSheetState();
}

class _FilenameTemplateSheetState extends State<FilenameTemplateSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  final _focus = FocusNode();
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insert(String token) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() => _error = null);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '自定义文件名',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            hintText: '{date}_{md5-16}',
            errorText: _error,
            helperText: '点击下方变量插入光标处；扩展名自动保留，无需再写 .png 或 .jpg。',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 20),
        for (final group in ['日期与时间', '文件内容', '随机值']) ...[
          SectionLabel(group),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: filenameVariables
                  .where((e) => e.group == group)
                  .map(
                    (variable) => SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: Material(
                        color: heroBlue.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _insert(variable.token),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  variable.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  variable.token,
                                  style: const TextStyle(
                                    color: heroBlue,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  variable.description,
                                  style: const TextStyle(
                                    color: heroMuted,
                                    fontSize: 10,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 22),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final error = validateFilenameTemplate(_text.text);
              if (error != null) {
                setState(() => _error = error);
                return;
              }
              Navigator.pop(context, _text.text.trim());
            },
            child: const Text('保存'),
          ),
        ),
      ],
    ),
  );
}
