import 'package:fluro/fluro.dart';
import 'package:picora/pages/picora_app.dart';
import 'hero_app.dart';
import 'models.dart';
import 'repositories_page.dart';

Handler modernPageHandler(int page) => Handler(
  handlerFunc: (context, params) => PicoraAppEntry(selectedIndex: page),
);
Handler modernRepositoryHandler(String host) => Handler(
  handlerFunc: (context, params) {
    final controller = HeroScope.of(context!);
    final target = controller.target;
    final existing = target?.host == host
        ? target
        : controller.repositories.where((r) => r.host == host).firstOrNull;
    return RepositoryEditor(
      controller: controller,
      spec: hostSpec(host),
      existing: existing,
    );
  },
);
Handler modernSlotHandler(String host) => Handler(
  handlerFunc: (context, params) {
    final controller = HeroScope.of(context!);
    final slot = params['storeKey']?.first;
    final existing = controller.repositories
        .where((r) => r.host == host && r.slot == slot)
        .firstOrNull;
    return RepositoryEditor(
      controller: controller,
      spec: hostSpec(host),
      existing: existing,
    );
  },
);
