# Android 真机测试

## 安装测试包

测试包输出到 `releases/Picora-arm64-debug.apk`，用于 ARM64 手机，最低 Android 7.0（API 24）。这是使用 Android 调试证书签名的 Debug 包，不需要配置正式签名密钥。Android 不允许安装完全未签名的 APK。

调试包名为 `io.github.alnitak44.picora`，可以与原版 PicHoro 共存。首次启动使用独立的应用数据，需要重新添加图床配置。

改名后的 Picora 尚未生成 APK。现有旧应用 APK 的名称、包名和哈希不能作为新包的验收结果。完成构建后执行 `Get-FileHash .\releases\Picora-arm64-debug.apk -Algorithm SHA256` 获取本次哈希。

把 APK 通过 USB 文件传输复制到手机，在手机文件管理器中点击安装，按系统提示允许该文件管理器“安装未知应用”。安装后打开 Picora 即可测试。

也可以通过 USB 调试安装：手机开启开发者选项和 USB 调试，连接数据线，在手机上接受电脑的调试授权。在工程根目录运行 PowerShell：

```powershell
. .\scripts\android-env.ps1
adb devices
adb install -r .\releases\Picora-arm64-debug.apk
```

`adb devices` 应显示设备序列号及 `device`。若显示 `unauthorized`，解锁手机并接受授权。

## 建议先测的操作

1. 仓库 → 图床列表 → 右上角加号，添加实际图床参数并设为默认。
2. 上传 → 相册上传，选择一张图片；确认 URL、Markdown、Discuz 三种复制结果。
3. 测试拍照上传、链接上传，以及切换不同图床配置。
4. 相册中切换瀑布流、网格、列表，并检查图床筛选。
5. 设置中切换浅色、自动、深色；重启后确认选择仍保留。自动模式应随手机系统主题变化。
6. 使用错误参数或断网触发一次失败，确认错误提示与诊断记录。

## 提供错误记录

应用可打开时，到 **设置 → 诊断日志**，导出日志，并附上操作步骤、手机型号、Android 版本。诊断记录会脱敏图床凭据。

启动闪退时，通过电脑导出原生日志：

```powershell
. .\scripts\android-env.ps1
adb logcat -c
adb shell am start -n io.github.alnitak44.picora/io.github.alnitak44.picora.MainActivity
# 在手机上复现问题后执行：
adb logcat -d -v threadtime > .\artifacts\device-log.txt
```

原生系统日志可能包含其他应用信息，发送前检查内容。不要附上图床密钥或包含密钥的配置备份。

## 重新打包

本工程的 Flutter、Android SDK、Gradle 与依赖缓存位于 `.tooling/`。在根目录执行：

脚本会为中文路径创建临时盘符别名，完成后恢复真实 SDK/依赖路径并移除别名，构建文件始终保存在本工程中。

中国大陆网络下若已运行本地代理，可在同一个 PowerShell 会话中先设置 Gradle 代理。例如 FlClash 使用 7890 端口时：

```powershell
$env:GRADLE_OPTS = '-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890 -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890'
.\scripts\build-debug.ps1
```

```powershell
.\scripts\build-debug.ps1
```

脚本仅构建 ARM64，并明确指定 `--target-platform android-arm64 --split-per-abi`。不提供多架构或通用包分支。

Debug 包用于开发验收。正式发布仍需 `android/key.properties` 和发布密钥。
