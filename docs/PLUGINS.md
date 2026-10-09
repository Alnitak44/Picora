
# 插件开发与发布

原生插件使用 ZIP + 声明式 HTTP 请求，不执行脚本。每个插件注册一个图床类型，可建立多组独立配置。

| 运行时 | 程序版本 | 支持 |
| --- | --- | --- |
| http-v1 | schemaVersion: 1 | 基础单次上传 |
| http-v2 | schemaVersion: 2 | Picora 1.0.1 起：前置请求、缓存、业务判断、受控刷新 |

[基础模板](../plugins/template) · [Telegraph-Image 示例](../plugins/telegraph-image)

## 包结构与元信息

```text
host.picora-plugin.zip
├── plugin.json
├── uploader.json
├── readme.md
└── assets/
    └── icon.svg
```

文件位于 ZIP 根目录，路径区分大小写，使用 `/`。`plugin.json` 保存元信息，`uploader.json` 为程序入口，`readme.md` 为用户教程；资源内容不会执行。

```json
{
  "packageVersion": 1,
  "runtime": "http-v2",
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

`packageVersion` 为 1，`runtime` 与 schema 必须匹配。ID 为小写反向域名，最长 80；name/version/description/author 必填，上限为 60/30/160/80。homepage/repository 为可选 HTTP/HTTPS 地址；icon 指向 assets/ 中的 PNG/JPEG/WebP/GIF/SVG。mark 为 1–3 字符，color 为 #RRGGBB；example 为可选示例标记。

未知程序字段、不支持的运行时或能力，以及越权模板引用均在安装阶段报错，不会忽略关键字段。模块目录中的 `minAppVersion` 至少为 `1.0.1`。

## 程序与权限

程序必填 `schemaVersion`、`permissions`、`config`、`upload`，可选 `delete`；v2 另支持 `prepare` 和 `requires`。

```json
{
  "network": ["api.example.com", "config.baseUrl"],
  "readSelectedFile": true,
  "allowInsecureHttp": false,
  "deleteUploadedFile": false
}
```

- network 最多 16 项。v2 使用明确主机名，或当前配置中非密码字段的 `config.<key>`；后者绑定用户填写 URL 的协议、主机和端口。v1 保留通配权限，建议迁移为明确端点。
- readSelectedFile 必须为 true；只有上传能读取用户选中的文件。
- allowInsecureHttp 默认 false，每一步请求与重定向均检查。
- v2 声明删除请求时须设 deleteUploadedFile 为 true；用户仍须在插件详情单独授权，安装和覆盖更新后默认关闭。

`requires` 支持 prepare、credential-cache、response-conditions、credential-refresh、safe-redirects、scoped-delete；未知能力拒绝安装。

`config` 最多 30 个字段。key 唯一，匹配 `[A-Za-z][A-Za-z0-9_]{0,39}`；label 必填，最长 50。type 支持 text/secret/toggle/select，可选 hint/required/default，select 需非空 options。`config: []` 用于无需用户凭证的服务。

## 请求与响应

| 字段 | 行为 |
| --- | --- |
| method | 上传 POST/PUT/PATCH；前置 GET/HEAD/POST；删除 GET/POST/DELETE |
| url | HTTP/HTTPS URL，支持模板；拒绝用户信息和锚点 |
| headers / query | 各最多 64 项；拒绝 Host、Content-Length、代理与连接控制头 |
| body | multipart/json/form/binary/none；仅上传可用 multipart/binary |
| response | 上传必填 url，前置与删除不要求图片链接 |
| timeoutSeconds | 含重定向的总期限，5–300 秒，默认 60 |
| followRedirects / maxRedirects | 默认关闭；启用后最多 5 跳，每跳校验权限 |
| errors | HTTP 状态码到错误提示的映射，适用于所有请求 |
| refreshCredentials | 仅 v2 上传可用 |

multipart 用 fileField 指定文件字段（默认 file），附加参数为 fields，不能覆盖文件字段。json/form 使用 fields，支持递归对象、数组和模板。binary 发送图片字节；GET/HEAD 必须无请求体。

响应路径支持 `data.url`、`items[0].url`、`[0].src`，不支持完整 JSONPath；相对图片链接按最终请求 URL 解析。

```json
{
  "successStatuses": [200],
  "success": {"path": "ok", "equals": true},
  "errorMessage": "message",
  "errorCode": "code",
  "url": "data.url",
  "deleteKey": "data.deleteKey"
}
```

successStatuses 只能为 2xx；上传默认 [200, 201]，前置/删除默认全部 2xx。v2 可追加 success 条件，equals 标量、exists 布尔值或 containsAny 关键词数组择一，HTTP 与业务条件必须同时成立。错误消息与错误码按路径提取并脱敏。

仅上传响应支持 url/thumbnail/deleteKey/deleteUrl；删除凭证必须对应单张图片，不能返回列表或对象。

重定向不继承全局 Cookie 或请求头。跨来源只允许无请求体 GET/HEAD，移除全部自定义头和原 query，并拒绝携带已知凭证的 Location。禁止跨来源重发文件；同来源 303（或 POST 的 301/302）转为无请求体 GET，其它要求重发请求体的跳转停止。

## 前置请求与缓存（v2）

prepare 最多 4 步，按顺序执行，ID 唯一。步骤仅访问当前配置、包内资源和更早步骤的显式导出，不读取图片。

```json
{
  "id": "auth",
  "method": "GET",
  "url": "https://api.example.com/token",
  "response": {
    "successStatuses": [200],
    "success": {"path": "ok", "equals": true},
    "errorMessage": "message",
    "exports": {"token": {"path": "token", "type": "string", "secret": true}}
  },
  "cache": {"ttlFrom": "ttl", "refreshBeforeSeconds": 30, "maxTtlSeconds": 3600}
}
```

上传引用 `${steps.auth.token}`。

exports 最多 16 项，每项包含 path、type（string/number/boolean）；source 为 json/header（默认 json），required 和 secret 默认 true。字符串最多 4096 字符；缺失必填项、类型错误或前置业务失败会停止上传。

cache 仅支持 scope: configuration，ttlFrom（响应 JSON 数值路径）与 ttlSeconds（固定 TTL）择一。返回 0 不缓存；负数、非数值报错。maxTtlSeconds 默认 3600，上限 86400；refreshBeforeSeconds 默认 30，最多 300，实际提前量不超过 TTL 一半。

缓存仅存于内存，按插件程序/资源、配置组、配置值和前序导出隔离。并发合并同一凭证获取请求；修改配置，安装/更新/停用/卸载插件时清空缓存。

### 受控刷新

`upload.refreshCredentials` 示例：

```json
{
  "steps": ["auth"],
  "statuses": [403],
  "condition": {"path": "message", "containsAny": ["凭证", "token"]},
  "maxAttempts": 1
}
```

引用步骤必须有缓存。401 可仅按状态判断；其它拒绝响应须匹配明确错误码或凭证错误关键词，不能以 ok == false 作为重传条件。403 等规则应依据目标服务的凭证失效响应配置，不应宽泛匹配业务失败。

刷新后只重试一次，第二次失败停止；并发旧凭证失败不会撤销新凭证。已返回图片 URL、超时、断线与 5xx 不自动重传。前置与删除不自动重试。

## 单张删除（v2）

用户在相册主动删除且单独开启插件云端删除权限后执行。模板使用 `${upload.deleteKey}` 或 `${upload.deleteUrl}`，可读取 `${upload.url}`；不提供 config/steps/file/assets。网络端点权限仍依据原配置校验。

记录须匹配插件、原配置组及配置修订，配置修改后停止删除；缺失删除凭证或原配置时停止并保留记录；不选择其它配置作后备，不向插件提供相册列表、目录或其它图床凭证。删除须同时通过 HTTP 与业务判断。

## 模板与资源

| 表达式 | 值 |
| --- | --- |
| `${config.key}` | 当前配置中声明的字段 |
| `${steps.auth.token}` | 前序步骤导出（v2） |
| `${file.name}` / `${file.mime}` / `${file.bytes}` / `${file.base64}` | 选中图片；file.path 仅保留在 v1 |
| `${upload.url}` / `${upload.deleteKey}` / `${upload.deleteUrl}` | 单张上传记录，供删除使用 |
| `${uuid}` / `${time.millis}` / `${time.unix}` | UUID / 毫秒 / 秒 |
| `${base64(file.bytes)}` / `${sha256(file.bytes)}` | 编码 / 摘要 |
| `${hmacSha256(config.secret,file.bytes)}` | HMAC-SHA256 |
| `${basicAuth(config.username,config.password)}` | Basic 认证，两项空时省略 |
| `${normalizeBaseUrl(config.baseUrl)}` / `${urlEncode(config.key)}` | 基础 URL 规范化 / URL 参数编码 |
| `${assets/data.bin}` / `${assetText(assets/template.txt)}` | 包内字节 / UTF-8 文本 |

整串表达式保留类型，嵌入文本转为字符串，字节转 Base64。函数参数为变量，不支持脚本、嵌套函数、循环或动态文件路径。

icon 用于图床与插件列表。教程以 `![图示](assets/example.png)` 引用资源，不自动加载远程图片；SVG 应自包含。

## 更新、限制与信任边界

同 ID 更新替换程序、教程和资源，保留配置与启用状态。允许同版本重装，拒绝降级；版本遵循 SemVer，保持 ID/config.key 稳定。

程序最多 5000 个节点、16 层嵌套；字符串上限 16384 字符。ZIP 上限 10 MB，解压合计 20 MB，最多 128 个条目；单文件 2 MB，元信息与程序各 1 MB，readme 512 KB。拒绝路径穿越、链接、加密、CRC 错误与不支持的压缩方式。运行时文件上限 100 MB，响应上限 1 MB；缓存与并发凭证请求各最多 128 项。

插件不能执行系统命令、枚举文件、读取其它配置组或直接删除本地文件。诊断记录插件、配置组、步骤、HTTP 状态及失败类型；不写入响应正文、请求头或凭证。

网络权限限制请求去向，无法证明任意服务端接口没有破坏性副作用。插件仍能使用交给它的当前配置凭证，恶意 POST 可能伪装成上传；应审核来源，使用仅上传或单对象权限的凭证，不向第三方插件提供管理员密钥。ZIP 摘要用于完整性检查，不是作者身份签名；同 ID 覆盖安装也须来自可信来源。

## 打包

```powershell
.\tools\package-plugin.ps1 -SourceDirectory '.\plugins\my-host' -OutputPath '.\releases\plugins\my-host-1.0.0.picora-plugin.zip'
```

安装支持模块仓库、本地 ZIP 与下载 URL。错误详情见“设置 → 诊断日志”。

## 发布与模块仓库

客户端从 [Alnitak44/picora-plugins](https://github.com/Alnitak44/picora-plugins) 的 `main/index.json` 读取目录，下载 GitHub Release 中的插件 ZIP。目录缓存 12 小时，可手动刷新；连接失败时使用上次有效目录。

GitHub 镜像在客户端下载时应用，目录保留原始下载地址；图床上传和插件认证不使用镜像。

### 目录格式

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

`http-v2` 插件的 `minAppVersion` 至少为 `1.0.1`；runtime 与 ZIP 元信息必须一致。运行时要求以条目的 minAppVersion 和 ZIP 内的 runtime 为准。

### 发布流程

1. 使用稳定 ID 编写插件，更新 `plugin.json` 版本并打包 ZIP。
2. 将 ZIP 上传到作者仓库的 GitHub Release。
3. 向模块仓库提交目录条目的 PR，附上下载地址、大小和 SHA-256。
4. 更新时发布新的 ZIP 和条目，不以不同内容覆盖已发布版本。

插件源码与许可证归作者维护，目录合并由维护者审核请求目标、凭证使用及删除语义。
