# GitHub 在线插件生态方案

本文是下一阶段的设计建议。当前客户端已有 ZIP/URL 安装、教程、资源图标及同 ID 覆盖更新；尚未实现在线插件目录、索引 SHA-256 核对、版本大小比较或自动检查更新。本次未创建或发布 GitHub 仓库。

## 先准备一个目录仓库

建议新建公开仓库 `Alnitak44/picora-plugins`，名称可以自行决定。它维护插件目录、审核规则和收录 PR；每个作者可以保留自己的源码仓库。无需先搭建后台服务器。

```text
picora-plugins/
├── README.md                # 用户入口与收录规则
├── CONTRIBUTING.md          # 提交和维护教程
├── index.v1.json             # Picora 读取的聚合目录
├── schema/index.v1.schema.json
├── plugins/                 # 每个插件的目录条目，由 CI 聚合
├── scripts/validate.*       # 校验元数据、ZIP 和摘要
└── .github/workflows/       # PR 校验与目录生成
```

客户端可读取 `https://raw.githubusercontent.com/Alnitak44/picora-plugins/main/index.v1.json`。这里是建议地址，仓库和文件创建、发布之后才会可用。目录文件宜小且有 schemaVersion，客户端缓存最后一次验证成功的目录。

## 作者怎么发布

1. 建立自己的开源仓库，提供源码、许可证和使用教程。
2. 保持目前 Picora 安装包格式：`plugin.json + readme.md + uploader.json + assets/`，根目录文件必须齐全；可以用 `tools/package-plugin.ps1`。
3. 为版本打 tag，例如 `v1.0.0`，在 GitHub Release 附加打包好的 `*.picora-plugin.zip`。应使用真正的插件安装 ZIP，而不是直接拿 GitHub 自动生成的 Source code ZIP 当安装包。
4. 计算整个 ZIP 的 SHA-256，然后向目录仓库提交 PR。维护者审核合并后，客户端即可发现插件。
5. 发布新版本时，上传新的 tag/ZIP，提交目录更新 PR；已有版本的下载文件保持一致，不以不同内容替换同一个版本。

示例条目（以下 example 地址与摘要均为占位，不能直接发布）：

```json
{
  "schemaVersion": 1,
  "plugins": [
    {
      "id": "io.github.example.demo",
      "name": "示例图床",
      "description": "图床功能简介",
      "author": "example",
      "repository": "https://github.com/example/picora-plugin-demo",
      "version": "1.0.0",
      "runtime": "http-v1",
      "packageVersion": 1,
      "minAppVersion": "1.0.0",
      "tags": ["图床"],
      "downloadUrl": "https://github.com/example/picora-plugin-demo/releases/download/v1.0.0/demo.picora-plugin.zip",
      "sha256": "填写该 ZIP 的真实 64 位十六进制 SHA-256",
      "size": 12345
    }
  ]
}
```

目录 `schemaVersion` 是目录自身协议版本；不要混淆现有 ZIP 的 `packageVersion: 1`、程序的 `schemaVersion: 1` 或 `runtime: http-v1`。插件 ID 必须与包内一致且长期稳定；改名展示名称不需要改 ID。作者/源码仓库/版本信息以 ZIP 内的 plugin.json 为准，安装时与目录核对。

初版目录可只发布最新稳定版本。之后增加历史版本列表，允许旧客户端选择最近一个兼容版本；禁止仅按字符串排序版本号，需正确比较 SemVer，包括预发布版本。应用兼容性比较需处理 Android 的 `-debug` 构建后缀，不能让调试版本被错误判为不兼容。

## Picora 客户端要补什么

- 插件中心分为“在线插件 / 已安装”，在线页可搜索、筛选、查看作者、版本、源码主页与使用教程。
- 新增目录解析和缓存服务：schema 校验、重复 ID 检查、受支持 runtime/packageVersion、版本兼容性、HTTPS 下载地址、大小限制、失败诊断。默认目录源可配置，方便将来迁移域名或使用维护者认可的镜像。
- 下载后核对 `size` 和 SHA-256，再解析 ZIP，核对 ID/版本；复用已有安装审核 Bottom Sheet，展示网络权限与更新权限变化。
- 复用 `PicoraPluginManager.fetch()`、`inspectPackage()` 和 `installPackage()`；不要重新写一套互不相通的插件安装器。当前 fetch 有 10 MB 限制、连接/接收超时和重定向限制，目录下载安装保持这些约束。
- 更新应先保存并验证新包，成功后替换；更新失败保留旧包和已有图床配置。上线“更新”按钮前补齐严格版本比较、同版本重装/回退策略、更新日志和启用状态保持；当前 installPackage 只按相同 ID 覆盖，并会重新启用插件。
- 当前随应用提供的 Telegraph 示例 ID 受到保护，无法从外部同 ID 覆盖。如果要让它参与线上更新，应先调整为可升级的普通示例插件，迁移时保留现有 ID 和图床配置，避免旧配置失去关联。

现有原生 runtime 为声明式 HTTP 上传/删除，不在 Android 任意执行 Node.js/JavaScript。在线目录提供分发和发现能力，不能自动让现有 PicGo Node.js 插件在 Android 原生运行；PicGo Bridge 继续作为独立扩展途径。

## 为什么聚合目录优于逐个查 GitHub

一次拉目录，再按需要下载指定 Release ZIP，能减少等待、请求次数和共享 IP 的限流风险。GitHub REST API 的未认证请求通常限制为每 IP 每小时 60 次；此限制不能直接套用到所有 Raw/Release 下载，也不能理解为 Raw/Release 没有限流。

不建议每次进入插件中心都逐个请求每个仓库的 latest Release。可以按约 12 小时缓存目录，手动刷新；离线/超时显示旧目录和最后更新时间。中国大陆用户应有重试与明确报错、可选可信镜像，不能关闭 HTTPS 校验来“解决”下载问题。不要把维护者 GitHub Token 写进 APK；公共目录和公共 Release 下载无需应用内维护者密钥。

## 开源生态的维护方式

维护者控制目录，不接管作者源码。PR CI 检查条目、插件格式、摘要、权限和许可证；作者保留署名，插件包使用自己的开源许可证并列明来源。目录和模板可沿用 MIT。SHA-256 用于确认包与目录一致，作者身份和权限变化仍需审核。

先提供插件模板、ZIP 打包脚本、一个可升级示例和清晰开发文档；再完成客户端目录/安装/更新界面。后续增加 GitHub Actions 自动打包和提交通知、历史版本、镜像和评分等，不必一开始引入账号体系。

现有代码入口：`lib/hero/plugin_page.dart`、`lib/hero/plugins/plugin_manager.dart`、`plugin_package.dart`、`plugin_manifest.dart`；现有协议见 [插件开发说明](PLUGINS.md)。

参考：[GitHub Releases API](https://docs.github.com/en/rest/releases/releases)、[GitHub REST API 限流](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)、[PicGo 插件使用说明](https://picgo.github.io/PicGo-Doc/guide/config.html)。
