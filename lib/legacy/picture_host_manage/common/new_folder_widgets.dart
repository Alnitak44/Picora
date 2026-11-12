import 'package:flutter/material.dart';

class NewFolderDialog extends AlertDialog {
  NewFolderDialog({super.key, required Widget contentWidget})
    : super(
        content: contentWidget,
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      );
}

class NewFolderDialogContent extends StatefulWidget {
  final double buttonHeight, borderWidth;
  final String title, cancelButtonLabel, confirmButtonTitle;
  final VoidCallback onCancel, onConfirm;
  final TextEditingController folderNameController;
  const NewFolderDialogContent({
    super.key,
    required this.title,
    this.cancelButtonLabel = '取消',
    this.confirmButtonTitle = '确定',
    this.buttonHeight = 50,
    this.borderWidth = 1,
    required this.onCancel,
    required this.onConfirm,
    required this.folderNameController,
  });
  @override
  NewFolderDialogContentState createState() => NewFolderDialogContentState();
}

class NewFolderDialogContentState extends State<NewFolderDialogContent> {
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
              controller: widget.folderNameController,
              autofocus: true,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入文件夹名称' : null,
              decoration: const InputDecoration(
                labelText: '文件夹名称',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      widget.folderNameController.clear();
                      widget.onCancel();
                      Navigator.pop(context);
                    },
                    child: Text(widget.cancelButtonLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (!_form.currentState!.validate()) return;
                      widget.onConfirm();
                      Navigator.pop(context);
                      widget.folderNameController.clear();
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
