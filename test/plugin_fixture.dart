import 'dart:io';
import 'package:archive/archive.dart';
import 'package:picora/hero/plugins/plugin_package.dart';

// Build fixtures from source; example plugins are never Flutter assets.
PicoraPluginPackage telegraphPackage() {
  final archive = Archive();
  final root = Directory('plugins/telegraph-image');
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final path = file.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    archive.add(ArchiveFile.bytes(path, file.readAsBytesSync()));
  }
  return PicoraPluginPackage.decode(ZipEncoder().encode(archive));
}
