import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:picora/hero/plugins/plugin_catalog.dart';
import 'package:picora/hero/plugins/plugin_package.dart';

// Build fixtures from source; example plugins are never Flutter assets.
PicoraPluginPackage telegraphPackage({String? version}) {
  final archive = Archive();
  final root = Directory('plugins/telegraph-image');
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final path = file.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    var bytes = file.readAsBytesSync();
    if (path == 'plugin.json' && version != null) {
      final metadata = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      metadata['version'] = version;
      bytes = utf8.encode(jsonEncode(metadata));
    }
    archive.add(ArchiveFile.bytes(path, bytes));
  }
  return PicoraPluginPackage.decode(ZipEncoder().encode(archive));
}

class FixtureCatalogService extends PluginCatalogService {
  final PluginCatalog catalog;
  FixtureCatalogService(this.catalog);

  @override
  Future<PluginCatalog> load({bool forceRefresh = false}) async => catalog;
}
