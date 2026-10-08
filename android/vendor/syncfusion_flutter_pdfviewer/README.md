# Android compatibility patch

Source: Kuingsmile/flutterdep, commit `2fe741b4849e4e2699ac1e2a5e4dee93c3f0a786`, directory `syncfusion_flutter_pdfviewer-22.2.10/android`.

The original LICENSE is retained alongside this file. Android settings redirect only this plugin's native Gradle project to this directory; the pinned Dart package and PDF API are unchanged.

Removed the obsolete `registerWith(PluginRegistry.Registrar)` method. Flutter 3.29 removed Android v1 embedding APIs; this application uses the existing `onAttachedToEngine` v2 registration. See [Flutter migration documentation](https://docs.flutter.dev/release/breaking-changes/v1-android-embedding).
