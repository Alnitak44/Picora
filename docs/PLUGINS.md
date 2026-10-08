# 插件协议

Picora 原生插件使用 `http-v1`：配置表单、HTTP 上传/删除、响应映射和静态资源。每个插件注册一个图床类型，最多 26 组配置。PicGo 的 Node.js 插件通过 PicGo Bridge 调用。

## 包结构

```text
host.picora-plugin.zip
├── plugin.json
├── uploader.json
├── readme.md
└── assets/
    └── icon.svg
```

文件位于 ZIP 根目录，路径区分大小写，使用 `/`。`plugin.json` 保存元信息，`uploader.json` 为程序入口，`readme.md` 为用户教程。

[模板](../plugins/template) · [Telegraph-Image 示例](../plugins/telegraph-image)

## plugin.json

```json
{
  "packageVersion": 1,
  "runtime": "http-v1",
  "entry": "uploader.json",
  "id": "io.github.example.host",
  "name": "Example Host",
  "version": "1.0.0",
  "description": "Example 图床",
  "author": "Author",
  "repository": "https://github.com/Author/Plugin",
  "icon": "assets/icon.svg",
  "mark": "EX",
  "color": "#6377E8"
}
```

| 字段 | 约束 |
| --- | --- |
| packageVersion / runtime | 必须为 `1` / `http-v1` |
| entry | 包内 JSON 路径，不能是 plugin.json 或 assets/ 中的文件 |
| id | 小写反向域名格式，最长 80；作为图床与更新标识 |
| name / version / description / author | 必填，长度上限分别为 60 / 30 / 160 / 80 |
| homepage / repository | 可选 HTTP/HTTPS 地址 |
| icon | 可选，assets/ 中的 PNG/JPEG/WebP/GIF/SVG |
| example | 可选布尔值，标记开发示例，不限制更新或卸载 |
| mark / color | 可选；1–3 字符 / #RRGGBB，无图标时回退到 mark |

## uploader.json

```json
{
  "schemaVersion": 1,
  "permissions": {
    "network": ["api.example.com"],
    "readSelectedFile": true,
    "allowInsecureHttp": false
  },
  "config": [
    {"key": "token", "label": "API Token", "type": "secret", "required": true}
  ],
  "upload": {
    "method": "POST",
    "url": "https://api.example.com/upload",
    "headers": {"Authorization": "Bearer ${config.token}"},
    "body": {"type": "multipart", "fileField": "file"},
    "response": {
      "url": "data.url",
      "thumbnail": "data.thumbnail",
      "deleteKey": "data.id",
      "successStatuses": [200, 201]
    },
    "followRedirects": false,
    "timeoutSeconds": 60,
    "errors": {"401": "Token 无效"}
  }
}
```

`schemaVersion` 为 `1`。`network` 接受主机名、`*.example.com` 或 `*`；子域通配不包含根域。初始请求 URL 必须匹配权限，HTTP 需开启 `allowInsecureHttp`，`readSelectedFile` 必须为 true。

### 配置字段

`key` 唯一，符合 `[A-Za-z][A-Za-z0-9_]{0,39}`；`label` 必填，最长 50。可选 `hint`、`required`、`default`。最多 30 个字段。

| type | 用途 |
| --- | --- |
| text | 文本 |
| secret | 密钥 |
| toggle | 布尔值，default 默认为 false |
| select | 字符串选项，需非空 options 数组 |

### 请求

`upload` 必填；`delete` 可选，结构相同但不读取 response。

| 字段 | 行为 |
| --- | --- |
| method | POST / PUT / PATCH / DELETE，默认 POST |
| url | 完整 HTTP/HTTPS URL，支持模板 |
| headers / query | 请求头 / 查询参数对象；空请求头省略，禁止 Host 与 Content-Length |
| body | 上传必填；删除省略时为 none |
| response | 上传必填，url 为响应路径；thumbnail / deleteKey 可选 |
| timeoutSeconds | 5–300，默认 60，控制发送与接收超时 |
| followRedirects | 默认 true；建议 false，避免跳转绕过初始主机检查 |
| errors | HTTP 状态码到提示的映射，目前用于上传 |

| body.type | 请求体 |
| --- | --- |
| multipart | 图片字段由 fileField 指定，默认 file；附加参数放 fields |
| json | fields 作为 JSON；图片可用 `${file.base64}` |
| form | fields 作为 URL 编码表单 |
| binary | 用户选择的图片字节 |
| none | 无请求体 |

`fields` 的值支持递归对象、数组和模板。响应路径支持 `data.url`、`items[0].url`、`[0].src`；相对链接按请求 URL 解析，不支持完整 JSONPath。

上传按 `successStatuses` 判断，默认 `[200, 201]`，且需返回有效图片 URL。删除按 HTTP 2xx 判断。当前不支持响应业务状态条件或多步骤请求。

## 模板

| 表达式 | 值 |
| --- | --- |
| `${config.key}` | 当前图床配置 |
| `${file.name}` / `${file.path}` / `${file.mime}` | 文件名 / 路径 / MIME |
| `${file.bytes}` / `${file.base64}` | 字节 / Base64 |
| `${upload.url}` / `${upload.deleteKey}` | 已保存的上传结果，供删除使用 |
| `${uuid}` / `${time.millis}` / `${time.unix}` | UUID / 毫秒 / 秒时间戳 |
| `${base64(file.bytes)}` / `${sha256(file.bytes)}` | 编码 / 摘要 |
| `${hmacSha256(config.secret,file.bytes)}` | HMAC-SHA256 |
| `${basicAuth(config.username,config.password)}` | Basic 认证；两项空时省略请求头 |
| `${normalizeBaseUrl(config.baseUrl)}` | 补 HTTPS，拒绝用户信息、query、fragment 和末尾 /upload |
| `${assets/data.bin}` / `${assetText(assets/template.txt)}` | 包内资源字节 / UTF-8 文本 |

整串表达式保留值类型，嵌入文本时转为字符串；字节转 Base64。函数参数为变量，不支持字面量、函数嵌套、条件、循环或任意脚本。

## 资源与教程

`icon` 用于图床与插件列表。教程使用 `![图示](assets/example.png)` 引用本地资源；不自动加载远程图片。SVG 应自包含。

资源也可用于模板编码和摘要，例如 `${base64(assets/icon.png)}`。资源内容不执行。

## 更新与限制

同 ID 安装替换程序、教程和资源，保留配置与启用状态；允许同版本重装，拒绝降级。版本使用 SemVer，升级保持 ID 与 config.key 稳定。Telegraph-Image 是模块仓库中的首个插件及开发示例，不随应用内置，与其他插件采用相同安装和更新流程。

ZIP 上限 10 MB，解压合计 20 MB，最多 128 个条目；单文件 2 MB，元信息和程序各 1 MB，readme 512 KB。安装器校验路径、CRC、体积和必要文件，拒绝链接、加密和不支持的压缩方式。

运行时不支持自定义页面、OAuth 流程、分片上传或云端浏览扩展。错误详情见“设置 → 诊断日志”。

## 打包

```powershell
.\tools\package-plugin.ps1 -SourceDirectory '.\plugins\my-host' -OutputPath '.\releases\plugins\my-host-1.0.0.picora-plugin.zip'
```

安装入口支持模块仓库、本地 ZIP 与下载 URL。插件发布使用 GitHub Release 附件，模块目录协议见 [PLUGIN_MARKETPLACE.md](PLUGIN_MARKETPLACE.md)。
