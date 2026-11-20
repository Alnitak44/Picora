import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import 'diagnostics.dart';

/// Requests camera access before opening the system camera.
///
/// The dependencies are injectable so the dialog flow can be tested without a
/// device. A denied permission always ends in a visible explanation instead of
/// an upload error.
class CameraPermissionGate {
  final Future<permissions.PermissionStatus> Function() status;
  final Future<permissions.PermissionStatus> Function() request;
  final Future<bool> Function() openSettings;
  final bool Function()? isMobile;

  const CameraPermissionGate({
    required this.status,
    required this.request,
    required this.openSettings,
    this.isMobile,
  });

  factory CameraPermissionGate.platform() => CameraPermissionGate(
    status: () => permissions.Permission.camera.status,
    request: () => permissions.Permission.camera.request(),
    openSettings: permissions.openAppSettings,
    isMobile: _isMobilePlatform,
  );

  static bool _isMobilePlatform() => Platform.isAndroid || Platform.isIOS;

  Future<bool> ensure(BuildContext context) async {
    if (!(isMobile ?? _isMobilePlatform)()) return true;
    try {
      var current = await status();
      if (_granted(current)) return true;
      if (current.isDenied) current = await request();
      if (_granted(current)) return true;
      if (!context.mounted) return false;
      final open = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要相机权限'),
          content: const Text('拍照上传需要访问相机。请在系统设置中允许 Picora 使用相机。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
      if (open == true) await openSettings();
      return false;
    } catch (error, stack) {
      HeroDiagnostics.instance.record('检查相机权限', error, stack: stack);
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('无法使用相机'),
          content: const Text('读取相机权限失败，请稍后重试或前往系统设置检查权限。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await openSettings();
              },
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
      return false;
    }
  }

  static bool _granted(permissions.PermissionStatus value) =>
      value.isGranted || value.isLimited || value.isProvisional;
}
