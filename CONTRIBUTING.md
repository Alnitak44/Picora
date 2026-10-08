# 参与 Picora

欢迎提交问题、界面改进、图床连接器和插件。Picora 从 1.0.0 起独立维护，基础版本为 PicHoro v3.0.1。

## 提交问题

使用 GitHub Issue 模板，提供 Picora 完整版本、Android 版本、设备型号、复现步骤及预期结果。上传失败应注明图床类型、HTTP 状态或诊断编号。

从“设置 → 诊断日志”导出相关片段，并检查其中没有账号密钥、私人图片链接或其他不想公开的信息。截图可遮挡私人数据；不要把图床账号和配置导出文件发到公开 Issue。

## 开发与提交

1. Fork 并克隆仓库，新建自己的分支。
2. 阅读 [README](README.md)、[代码地图](docs/IMPLEMENTATION.md)和 [打包说明](打包说明.md)，安装匹配工具。
3. 保留锁文件、上游业务目录、Android vendor 补丁和现有数据兼容路径。
4. 只验证与修改相关的行为；修改上传、存储、插件或迁移逻辑时，补充有实际意义的测试。
5. 提交 PR，说明具体问题、改后的行为和实际运行的检查；未做真机验证时如实说明。

常用检查：

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub lib/hero lib/main.dart test
flutter test --no-pub
```

不需要每次文档修改都编译 Android。需要 APK 时只构建 ARM64。源码中保留部分上游实现，勿把继承代码的历史提示误当成新增改动。

## 插件贡献

先读 [插件开发文档](docs/PLUGINS.md)，从 [template](plugins/template) 开始。保持 ID 稳定，上传 ZIP 中不能包含用户 Token 或测试账号。普通插件建议使用独立仓库和 GitHub Release；在线插件目录仍在规划中。

## 版权

贡献应具有可发布的来源，保留必要许可与版权说明。不要将第三方素材或库一概标为 Picora 自有代码。项目代码使用 [MIT License](LICENSE)，第三方适用许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
