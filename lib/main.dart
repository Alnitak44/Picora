import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluro/fluro.dart';
import 'package:picora/router/application.dart';
import 'package:picora/router/routers.dart';
import 'package:picora/hero/hero_app.dart';
import 'package:picora/hero/diagnostics.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(const [
          'Picora',
        ], await rootBundle.loadString('assets/files/Picora-LICENSE.txt'));
      });
      Application.router = FluroRouter();
      Routes.configureRoutes(Application.router);
      FlutterError.onError = (details) {
        HeroDiagnostics.instance.record(
          'Flutter framework',
          details.exception,
          stack: details.stack,
        );
        if (kDebugMode) FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        HeroDiagnostics.instance.record(
          'Platform dispatcher',
          error,
          stack: stack,
        );
        return true;
      };
      runApp(const HeroApp());
    },
    (error, stack) => HeroDiagnostics.instance.record(
      'Uncaught asynchronous error',
      error,
      stack: stack,
    ),
  );
}
