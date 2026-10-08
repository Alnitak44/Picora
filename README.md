<div align="center">
  <img src="assets/images/picora.png" alt="Picora" width="112" />
  <h1>Picora</h1>
  <p>Android 图床与对象存储聚合客户端</p>
</div>

## 简介

Picora 是 [PicHoro](https://github.com/Kuingsmile/PicHoro) 的派生项目，基于 [PicHoro v3.0.1](https://github.com/Kuingsmile/PicHoro) 修改而来并独立维护。

Picora在继承[PicHoro](https://github.com/Kuingsmile/PicHoro)大部分功能与逻辑的基础上，添加了更加现代化的界面，并以[PicGo](https://github.com/Molunerfinn/PicGo)的工作流为参考，提供图片上传、相册管理和图床插件扩展。

## 功能

- 相册、拍照、链接和系统分享上传，支持批量上传与失败重试。
- URL、Markdown、Discuz / BBCode 链接复制。
- 相册支持瀑布流、网格、列表，以及搜索、筛选和多选管理。
- 同一图床可添加多组配置，支持默认目标和快捷切换。
- Markdown 图片迁移：下载原图、上传到指定图床、替换链接。
- 自定义文件命名、图片处理、配置导入导出和诊断日志。
- 浅色 / 自动 / 深色主题。

## 支持的图床与存储

阿里云 OSS、腾讯云 COS、七牛云、又拍云、S3 兼容存储、GitHub、SM.MS、Imgur、兰空图床、OpenList(Alist)、WebDAV、FTP / SFTP、自定义 Web 图床。

原生插件使用 ZIP + JSON HTTP 协议，支持资源图标、离线教程和同 ID 覆盖更新。PicGo 插件可通过 PicGo Bridge 调用。

[插件开放说明](%E6%8F%92%E4%BB%B6%E5%BC%80%E6%94%BE%E8%AF%B4%E6%98%8E.md) · [插件模板](plugins/template) · [Telegraph-Image 示例](plugins/telegraph-image)

## 下载

[GitHub Releases](https://github.com/Alnitak44/Picora/releases)

## 应用展示

<p align="center">
  <img src="docs/images/upload.png" width="210" alt="上传" />
  <img src="docs/images/album-dark.png" width="210" alt="相册" />
  <img src="docs/images/repositories.png" width="210" alt="图床列表" />
  <img src="docs/images/settings-dark.png" width="210" alt="设置" />
</p>

## 开发

Flutter **3.35.7** / Dart **3.9.2**，JDK **21**，Android SDK **36**，NDK **27.0.12077973**。

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub lib/hero lib/main.dart test
flutter test --no-pub
flutter build apk --debug --no-pub --split-per-abi
```

## License

本项目使用[MIT](LICENSE)开源协议。
保留上游版权，Picora 的修改与新增部分归 Alnitak44 和贡献者所有。

```text
Copyright (c) 2022-present, Kuingsmile
Copyright (c) 2026 Alnitak44 and Picora contributors
```

[第三方声明](THIRD_PARTY_NOTICES.md) · [更新日志](Version_update_log.md)
