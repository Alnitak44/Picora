import 'package:flutter/material.dart';

class RenameDialog extends AlertDialog {
  RenameDialog({super.key, required Widget contentWidget})
    : super(
        content: contentWidget,
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      );
}

class RenameDialogContent extends StatefulWidget {
  final String title, cancelButtonText, confirmButtonTitle, isCoverMsg;
  final VoidCallback onCancel;
  final Function(bool isCoverFile) onConfirm;
  final TextEditingController renameTextController;
  final double buttonHeight, borderWidth;
  final bool isShowCoverFileWidget;
  const RenameDialogContent({
    super.key,
    required this.title,
    this.cancelButtonText = '取消',
    this.confirmButtonTitle = '确定',
    this.buttonHeight = 50,
    this.borderWidth = 1,
    this.isShowCoverFileWidget = false,
    this.isCoverMsg = '是否覆盖同名文件',
    required this.onCancel,
    required this.onConfirm,
    required this.renameTextController,
  });
  @override
  RenameDialogContentState createState() => RenameDialogContentState();
}

class RenameDialogContentState extends State<RenameDialogContent> {
  bool isCoverFile = false;
  final _form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: widget.renameTextController,
              autofocus: true,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入名称' : null,
              decoration: const InputDecoration(labelText: '新名称'),
            ),
            if (widget.isShowCoverFileWidget)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: isCoverFile,
                onChanged: (value) =>
                    setState(() => isCoverFile = value ?? false),
                title: Text(
                  widget.isCoverMsg,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      widget.renameTextController.clear();
                      widget.onCancel();
                      Navigator.pop(context);
                    },
                    child: Text(widget.cancelButtonText),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (!_form.currentState!.validate()) return;
                      widget.onConfirm(isCoverFile);
                      Navigator.pop(context);
                      widget.renameTextController.clear();
                    },
                    child: Text(widget.confirmButtonTitle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
