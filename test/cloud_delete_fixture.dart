import 'package:picora/hero/plugins/uploader_registry.dart';

class TestDeleteRegistry extends UploaderRegistry {
  bool supported = true;
  Object? result = const ['success'];
  Future<dynamic> Function()? pending;
  final calls = <Map<String, dynamic>>[];

  @override
  bool supportsDelete(String host) => supported;

  @override
  Future<dynamic> delete(
    String host, {
    required Map<String, dynamic> deleteMap,
    required Map<String, dynamic> config,
    String? configurationId,
    bool allowCloudDelete = false,
  }) async {
    calls.add({
      'host': host,
      'row': deleteMap,
      'config': config,
      'configurationId': configurationId,
      'allowCloudDelete': allowCloudDelete,
    });
    return pending == null ? result : pending!();
  }
}
