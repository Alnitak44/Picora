# 新电脑编译环境恢复记录

恢复日期：2026-10-07。实际工程根目录为 `D:\项目\Picora\PicHero`，应用仍为 Picora，包名仍为 `io.github.alnitak44.picora`。本次恢复工具与依赖，不生成 APK。

## 先执行这一条

在 PowerShell 中进入工程并加载项目环境。变量只影响当前终端，不修改系统 PATH、注册表或其他工程：

```powershell
Set-Location 'D:\项目\Picora\PicHero'
. .\scripts\android-env.ps1
```

脚本默认使用 FlClash 的 HTTP 代理 `http://127.0.0.1:7890`，设置 HTTP_PROXY / HTTPS_PROXY，localhost 不走代理。首次下载和日后联网前，确保 FlClash 正在运行、7890 是 HTTP 或混合端口。Java/Gradle 的代理另在 `.tooling/gradle-cache/gradle.properties` 中设置，因为 Java 不统一读取 HTTP_PROXY。

`PUB_HOSTED_URL=https://pub.dev`，保留原锁文件中记录的来源；Flutter SDK/Engine 使用 Flutter 官方文档列出的中国社区镜像 `https://storage.flutter-io.cn`。如果当前终端已有这两个变量，环境脚本保留用户值。

## 已恢复的工具

| 工具 | 版本 | 工程内路径 |
| --- | --- | --- |
| Flutter | stable 3.35.7；commit adc901062556672b4138e18a4dc62a4be8f4b3c2 | `.tooling/flutter/bin/flutter.bat` |
| Dart | 3.9.2，随 Flutter 提供 | `.tooling/flutter/bin/dart.bat` |
| Microsoft OpenJDK | 21.0.3+9，与原机器匹配 | `.tooling/jdk/bin/java.exe` / `javac.exe` / `jcmd.exe` |
| Git | 2.53.0.windows.3，便携版本 | `.tooling/git/cmd/git.exe` |
| Android Platform | android-36，revision 2 | `.tooling/android-sdk/platforms/android-36` |
| Build Tools | 35.0.0 | `.tooling/android-sdk/build-tools/35.0.0` |
| NDK | 27.0.12077973 / r27 | `.tooling/android-sdk/ndk/27.0.12077973` |
| CMake | 3.22.1 | `.tooling/android-sdk/cmake/3.22.1/bin` |
| Platform Tools / ADB | 37.0.1 | `.tooling/android-sdk/platform-tools/adb.exe` |
| Android Command-line Tools | 19.0 | `.tooling/android-sdk/cmdline-tools/latest/bin/sdkmanager.bat` |
| Gradle | Wrapper 8.10.2；AGP 8.8.0、项目 Kotlin plugin 2.1.0 | `android/gradlew.bat` |

Gradle `--version` 中自带的 Kotlin 1.9.24 是 Gradle 自身版本，不能据此把项目 Kotlin 2.1.0 改为 1.9.24。

保留的旧 Debug 密钥在 `.tooling/android-user/debug.keystore`。文件与迁移清单一致，keytool 能读取 androiddebugkey；证书 SHA-256：`7C:DE:27:65:21:14:A9:CD:B2:D9:E6:E2:F7:B9:D2:7A:2B:F3:56:62:14:7C:DA:06:20:09:4A:76:B4:5D:D9:05`。未来 APK 仍须用 apksigner 确认实际签名，不能用“密钥存在”代替 APK 验证。

## 缓存与本地配置

- Pub 缓存：`.tooling/pub-cache`；Gradle 缓存：`.tooling/gradle-cache`。
- Android 用户目录：`.tooling/android-user`；临时目录：`.tooling/tmp`。
- 下载 ZIP、官方元数据与校验记录：`.tooling/downloads`。
- 本机 Gradle 参数：`.tooling/gradle-cache/gradle.properties`，包含 Java UTF-8、7890 代理、Kotlin 进程内编译、关闭增量 Kotlin 和最多 2 个 worker。不改应用的 Java 21 目标。
- `android/local.properties` 已按本机路径生成；路径使用正斜杠与 Java Properties Unicode 转义，避免中文和反斜杠被错误解码。不要复制旧机 E: 路径。
- Maven 镜像入口为 `scripts/gradle-repositories.gradle`，每次加载环境时复制到项目 Gradle 缓存的 init.d，优先阿里云 public/google，保留原仓库回退。兼容 Flutter included build 的 FAIL_ON_PROJECT_REPOS，不能无条件给所有 project 添加仓库。
- `scripts/android-env.ps1` 优先选用工程 `.tooling/jdk`，不依赖原电脑 `C:\Program Files\Microsoft`。
- `tools/check-documents-native.ps1` 已改用环境脚本选择 Java；此专项检查还要求 Gradle 缓存中存在完整的 Kotlin、Flutter embedding 和 AndroidX JAR。缺少这些缓存时，不代表文档接口源码有错。
- `scripts/build-debug.ps1` 的路径还原写入改为 Windows PowerShell 5.1/PowerShell 7 均支持的 UTF-8 无 BOM API；仍只构建 ARM64。

普通终端可直接执行 `flutter` / `dart` / `java` / `git` / `adb`，前提是已经 dot-source 环境脚本；也可以用表中的完整相对路径。

## 验证与后续命令

本次执行了原始 611 个迁移文件的 SHA-256 对比与 Git 完整性检查，恢复前无文件差异。大量原有未提交修改保留，未 reset/clean/check-out 工作树。

首次依赖恢复使用 `flutter pub get --enforce-lockfile`；完成后 `pubspec.lock` SHA-256 与迁移清单一致，文件未改动。Flutter 首次启动输出的 `Running pub upgrade` 属于 SDK 自己的 flutter_tools 引导，不是升级 Picora 项目依赖。

静态检查：`flutter analyze --no-pub lib/hero lib/main.dart test` 通过。完整测试：55 项通过。Flutter Doctor 的 Flutter、Android 工具链、Android 许可证、代理与网络项通过。`android/gradlew.bat help --console=plain -Ptarget-platform=android-arm64` 配置成功（首次依赖补齐约 10 分钟）；包含 Flutter included Gradle build 和所有 Android 插件配置，未执行 assembleDebug、没有生成 APK。后续实际 APK 构建仍可能需要下载尚未使用的运行时 Maven/Engine 依赖，本机未宣称完整离线构建已通过。

日常修改后：

```powershell
. .\scripts\android-env.ps1
flutter analyze --no-pub lib/hero lib/main.dart test
flutter test --no-pub
```

锁文件未改且缓存存在时，可用 `flutter pub get --offline --enforce-lockfile`；新增依赖需按实际任务联网解析，不能把 `pub upgrade` 当作恢复命令。所有 Flutter 命令串行执行，避免启动锁竞争。

需要打包时再执行 `./scripts/build-debug.ps1`。当前用户设备是 ARM64，交付 `releases/Picora-arm64-debug.apk`；不得默认生成通用 APK。原始输出为 `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`。中文工作目录由脚本临时映射英文盘符，结束后恢复依赖路径。

## 本次遇到的网络与工具问题

1. 7890 端口已验证监听，代理可访问 GitHub、Pub、Flutter 镜像。不要只看到端口监听就认定所有目标网站高速可用。
2. `dl.google.com` 的部分 SDK 大文件通过当前代理仍很慢；改用 Google 官方 CDN `https://redirector.gvt1.com/edgedl/android/repository/`，并与官方 repository XML 中的 SHA-1 校验值逐个比对。安装后 sdkmanager 可识别组件，并实际验证 adb / aapt2 / cmake。手动解压的 NDK 另补齐标准 package.xml（基于 SDK Manager 生成的 generic package 模板、NDK 的真实路径和修订版本），保留 SDK 许可引用，使 SDK Manager 能识别它并避免重复下载。
3. Android Command-line Tools 23.0 的 sdkmanager 已变成 Android CLI 兼容入口，旧的带分号包名参数被错误拆分，而且退出码可能为 0。不能凭退出码声称已安装，必须检查组件文件和安装列表。本次使用传统 19.0；23.0 保存于 `.tooling/commandlinetools-23-unused`，放在 SDK 之外，避免被 Flutter 自动选中。
4. Windows curl 遇到 `CRYPT_E_REVOCATION_OFFLINE`：为 SDK 下载使用 `--ssl-revoke-best-effort`，仅容许无法获取吊销信息时尽力检查，保留正常 TLS 证书校验。没有使用 `-k` / `--insecure`，没有修改系统证书策略。
5. 下载大文件慢时可使用 curl `--continue-at -` 断点续传；完成后再校验官方 hash，不能直接把不完整的 `.part` 当 ZIP。Flutter ZIP 的 SHA-256、JDK ZIP 的官方 SHA-256、Android 包的官方校验值均已验证。
6. 原 Maven Central 对旧插件固定 Kotlin 1.8.10 的若干 JAR 返回 HTTP 403；镜像提供相同坐标版本，未把插件升级到新 Kotlin。后续如果看到同样下载异常，先看仓库/代理和实际 URL，避免误改插件源码或反复清缓存。
7. 本项目只针对 Android；Flutter Doctor 中缺少 Chrome、Visual Studio、Android Studio 并不要求补装桌面或 Web 开发套件。Android 工具链、许可证和项目 Gradle 配置应单独核对。

日志和版本记录位于 `artifacts/environment-restore/`，包括 `pub-get.log`、`analyze.log`、`test.log`、`flutter-doctor.log`、`sdk-installed.log`、`android-licenses.log`、`gradle-version.log`、`gradle-configure.log`、`debug-certificate.log` 和修改前脚本备份。

参考下载来源：[Flutter 官方中国网络说明](https://docs.flutter.dev/community/china)、[Microsoft JDK 历史发行版](https://learn.microsoft.com/en-us/java/openjdk/older-releases)、[Android SDK 工具说明](https://developer.android.com/tools)。本次恢复脚本在 `.tooling/restore-download.ps1`、`.tooling/restore-android-package.ps1`，仅针对已记录的下载清单；以后更换版本时必须重新获取官方元数据和 hash。
Flutter pub get 同时重写了 iOS 的 Generated.xcconfig / flutter_export_environment.sh 中的机器路径，这是生成配置，不代表完成 iOS 验证。项目业务 lib/test、pubspec.yaml/lock、应用包名、签名密钥均未更改；Git 索引的文件 hash 变化来自状态刷新，未暂存或提交修改。
