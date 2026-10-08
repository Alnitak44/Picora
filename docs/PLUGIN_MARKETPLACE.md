# 模块仓库

客户端从 [Alnitak44/picora-plugins](https://github.com/Alnitak44/picora-plugins) 的 `main/index.json` 读取目录，下载 GitHub Release 中的插件 ZIP。目录缓存 12 小时，可手动刷新；连接失败时使用上次有效目录并提示缓存时间。

Telegraph-Image 是首个插件，也是 [http-v1 开发示例](../plugins/telegraph-image)，不随应用内置。旧版留下的配置保持原 ID，安装同 ID 插件后恢复使用。

## 目录格式

```json
{
  "schemaVersion": 1,
  "plugins": [
    {
      "id": "io.github.example.host",
      "name": "Example Host",
      "description": "Example 图床",
      "author": "Author",
      "repository": "https://github.com/Author/Plugin",
      "version": "1.0.0",
      "runtime": "http-v1",
      "packageVersion": 1,
      "minAppVersion": "1.0.0",
      "mark": "EX",
      "example": false,
      "downloadUrl": "https://github.com/Author/Plugin/releases/download/v1.0.0/host.picora-plugin.zip",
      "sha256": "<ZIP 文件的 64 位十六进制 SHA-256>",
      "size": 12345
    }
  ]
}
```

`id`、`name`、`author`、`version` 与 ZIP 元信息一致。`size` 为 ZIP 字节数，`sha256` 为整个 ZIP 的摘要；`downloadUrl` 与 `repository` 必须使用 HTTPS。`mark`、`example` 可选，分别用于下载前的文字图标和示例标记。图床图标由 ZIP 内的 `assets/` 提供。

客户端核对大小、摘要、插件身份和协议，安装前展示权限；兼容性与更新按 SemVer 比较。更新保留图床配置和启用状态，拒绝降级；相同版本可从本地 ZIP 重装。校验或安装失败保留原插件。

## 发布

1. 按 [插件协议](PLUGINS.md) 编写插件，以稳定 ID 标识插件和配置。
2. 更新 `plugin.json` 版本，打包 ZIP 并上传到作者仓库的 GitHub Release。
3. 向模块仓库提交目录条目的 PR，附上下载地址、大小和 SHA-256。
4. 更新版本时发布新的 ZIP 和条目；不要以不同内容覆盖已有版本。

插件源码与许可证归作者维护，目录合并由维护者审核。客户端无需 GitHub Token，且不会执行 Node.js / JavaScript；PicGo 插件通过 PicGo Bridge 使用。
