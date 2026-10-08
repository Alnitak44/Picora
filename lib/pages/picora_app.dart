import 'package:flutter/material.dart';
import 'package:picora/hero/hero_app.dart';

/// Compatibility entry point used by the inherited routes.
class PicoraAppEntry extends StatelessWidget {
  final int selectedIndex;
  const PicoraAppEntry({super.key, this.selectedIndex = 0});
  @override
  Widget build(BuildContext context) => HeroShell(
    controller: HeroScope.of(context),
    selectedIndex: selectedIndex,
  );
}
