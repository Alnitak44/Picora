# 插件开发文档

Picora 原生插件使用 **ZIP 包 + 声明式 HTTP 请求**，不执行脚本。每个插件注册一个图床类型，用户可为同一类型建立多组独立配置。

[基础模板](../plugins/template) · [Telegraph-Image 示例](../plugins/telegraph-image) · [插件提交流程](插件提交流程.md)

## 目录

- [协议版本](#协议版本)
- [插件包与元信息](#插件包与元信息)
- [程序入口与能力声明](#程序入口与能力声明)
- [配置字段](#配置字段)
- [网络与文件权限](#网络与文件权限)
- [HTTP 请求与响应](#http-请求与响应)
  - [请求体](#请求体)
  - [条件 JSON 字段](#条件-json-字段)
  - [响应解析与业务判断](#响应解析与业务判断)
  - [重定向](#重定向)
- [前置请求与凭证](#前置请求与凭证)
  - [响应导出](#响应导出)
  - [凭证缓存](#凭证缓存)
  - [受控刷新](#受控刷新)
- [单张图片删除](#单张图片删除)
- [模板与资源](#模板与资源)
- [更新与安全边界](#更新与安全边界)
- [打包与发布](#打包与发布)

## 协议版本

| 运行时 | 程序版本 | 最低 Picora 版本 | 功能 |
| --- | --- | --- | --- |
| `http-v1` | `schemaVersion: 1` | `1.0.0` | 基础单次上传 |
| `http-v2` | `schemaVersion: 2` | `1.0.1` | 前置请求、凭证缓存、业务判断、受控刷新与单张删除 |
| `http-v2` + `conditional-json-fields` | `schemaVersion: 2` | `1.0.4` | 按配置值选择 JSON 请求字段 |

`plugin.json` 的 `runtime` 必须与入口程序的 `schemaVersion` 对应。发布到模块仓库时，登记文件的 `minAppVersion` 应覆盖插件使用的全部能力。

未知程序字段、不支持的运行时或能力、越权模板引用均会在安装阶段报错，不会忽略关键字段。PicGo 的 Node.js 插件不能直接作为 Picora 原生插件安装。

## 插件包与元信息

```text
host.picora-plugin.zip
├── plugin.json
├── uploader.json
├── readme.md
└── assets/
    └── icon.svg
```

| 文件或目录 | 用途 |
| --- | --- |
| `plugin.json` | 插件名称、版本、作者、入口与图标等元信息 |
| `uploader.json` | 声明配置字段、权限与 HTTP 请求；文件名由 `entry` 指定 |
| `readme.md` | 面向用户的插件介绍、配置说明与使用教程，使用 UTF-8 编码 |
| `assets/` | 图标、教程配图及请求所需的静态资源；资源内容不会执行 |

这些文件放在 ZIP 根目录，不要额外套一层插件文件夹。路径区分大小写，使用 `/`；`assets/` 可以为空。

### 元信息示例

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

### 元信息参数

| 参数 | 类型 | 必填 | 功能与用法 |
| --- | --- | --- | --- |
| `packageVersion` | 整数 | 是 | ZIP 包格式版本，当前固定为 `1` |
| `runtime` | 字符串 | 是 | 使用 `http-v1` 或 `http-v2`，与入口程序的 `schemaVersion` 对应 |
| `entry` | 字符串 | 是 | 包内 JSON 程序路径，例如 `uploader.json`；不能指向 `plugin.json` 或 `assets/` |
| `id` | 字符串 | 是 | 插件唯一标识，使用小写反向域名格式，最长 80 字符；发布后保持稳定 |
| `name` | 字符串 | 是 | 插件与图床类型的显示名称，最长 60 字符 |
| `version` | 字符串 | 是 | 插件版本，使用 SemVer，例如 `1.0.0`，最长 30 字符 |
| `description` | 字符串 | 是 | 功能简介，最长 160 字符 |
| `author` | 字符串 | 是 | 作者或维护者名称，最长 80 字符 |
| `repository` | 字符串 | 否 | 源码仓库地址；与 `homepage` 均须为 HTTP/HTTPS URL，不能含账号密码 |
| `homepage` | 字符串 | 否 | 项目主页地址；应用的 GitHub 入口仅识别 `https://github.com/…`，优先使用 `repository` |
| `icon` | 字符串 | 否 | 指向 `assets/` 中的 PNG、JPEG、WebP、GIF 或 SVG，例如 `assets/icon.svg` |
| `mark` | 字符串 | 否 | 无图片图标时的文字标识，1–3 字符，默认 `P`，会转为大写 |
| `color` | 字符串 | 否 | 标识颜色，格式为 `#RRGGBB`，默认 `#6377E8` |

“开发示例”由模块仓库维护者指定，不属于插件元信息，也不授予额外权限。插件包不能通过自行声明字段获得该标记。

## 程序入口与能力声明

入口程序负责描述请求，名称、版本和作者等元信息由 `plugin.json` 提供。

| 参数 | 类型 | 必填 | 用途 |
| --- | --- | --- | --- |
| `schemaVersion` | 整数 | 是 | `http-v1` 使用 `1`，`http-v2` 使用 `2` |
| `permissions` | 对象 | 是 | 声明网络目标与文件权限 |
| `config` | 数组 | 是 | 用户可填写的配置字段；无需配置时使用 `[]` |
| `upload` | 对象 | 是 | 上传请求及图片链接解析规则 |
| `delete` | 对象 | 否 | 单张云端图片的删除请求 |
| `prepare` | 数组 | 否，v2 | 上传前按顺序执行的请求，最多 4 步 |
| `requires` | 字符串数组 | 否，v2 | 声明依赖的运行时能力；未知能力拒绝安装 |

### 能力名称

| 能力 | 用途 | 最低 Picora 版本 |
| --- | --- | --- |
| `prepare` | 有序前置请求与响应变量导出 | `1.0.1` |
| `credential-cache` | 按配置组隔离凭证缓存 | `1.0.1` |
| `response-conditions` | 判断业务成功条件并提取错误信息 | `1.0.1` |
| `credential-refresh` | 明确凭证失效后刷新，并最多重试一次 | `1.0.1` |
| `safe-redirects` | 逐跳校验重定向目标和权限 | `1.0.1` |
| `scoped-delete` | 绑定原配置及单张图片的删除操作 | `1.0.1` |
| `conditional-json-fields` | 按文本配置选择前置 JSON 请求的字段；使用时必须声明 | `1.0.4` |

例如，需要前置认证和条件字段时，在程序根部设置 `"requires": ["prepare", "conditional-json-fields"]`。

## 配置字段

`config` 最多包含 30 个字段。字段的 `key` 在本插件中唯一，模板通过 `${config.<key>}` 读取当前配置组的值。

| 参数 | 类型 | 必填 | 功能与用法 |
| --- | --- | --- | --- |
| `key` | 字符串 | 是 | 字段键，匹配 `[A-Za-z][A-Za-z0-9_]{0,39}`；更新插件时保持稳定 |
| `label` | 字符串 | 是 | 配置表单中的名称，最长 50 字符 |
| `type` | 字符串 | 否 | `text` 文本、`secret` 密码或 Token、`toggle` 开关、`select` 选项；默认 `text` |
| `hint` | 字符串 | 否 | 输入提示 |
| `required` | 布尔值 | 否 | 是否必须填写，默认 `false` |
| `default` | 字符串、数字或布尔值 | 否 | 初始值；`toggle` 默认 `false` |
| `options` | 字符串数组 | `select` 必填 | 可选值列表，不能为空 |

## 网络与文件权限

```json
{
  "network": ["api.example.com", "config.baseUrl"],
  "readSelectedFile": true,
  "allowInsecureHttp": false,
  "deleteUploadedFile": false
}
```

| 参数 | 类型 | 默认值与约束 |
| --- | --- | --- |
| `network` | 字符串数组 | 必填，1–16 项。v2 使用明确主机名或 `config.<key>`；不能使用通配主机 |
| `readSelectedFile` | 布尔值 | 必须为 `true`；仅上传请求可读取用户选中的图片 |
| `allowInsecureHttp` | 布尔值 | 默认 `false`；每次请求及每一跳重定向均检查 |
| `deleteUploadedFile` | 布尔值 | 仅 v2，默认 `false`；声明删除请求时必须设为 `true` |

`config.<key>` 须引用当前插件的非密码配置字段，并绑定用户填写 URL 的**协议、主机和端口**。v1 保留通配主机权限，新插件应使用明确端点。

删除上传记录时同步删除云端图片，需要用户在插件详情单独开启；安装和覆盖更新后，该授权默认关闭。图片详情中的“删除云端图片”需单独确认，只授权本次操作，不改变同步删除开关。

## HTTP 请求与响应

`upload`、`prepare[]` 和 `delete` 使用共同的请求字段。方法、文件访问及模板范围按操作类型限制。

| 参数 | 类型 | 功能与约束 |
| --- | --- | --- |
| `method` | 字符串 | 上传：`POST`/`PUT`/`PATCH`；前置：`GET`/`HEAD`/`POST`；删除：`GET`/`POST`/`DELETE`。默认前置 `GET`，其余 `POST` |
| `url` | 字符串 | 必填，HTTP/HTTPS URL，支持模板；不能含账号密码或锚点 |
| `headers` | 对象 | 请求头，最多 64 项；禁止 `Host`、`Content-Length`、代理与连接控制头 |
| `query` | 对象 | 查询参数，最多 64 项，支持模板 |
| `body` | 对象 | 上传必填；前置和删除省略时不发送请求体 |
| `response` | 对象 | 上传必填图片链接路径；前置和删除不要求图片链接 |
| `timeoutSeconds` | 整数 | 包含重定向的总期限，5–300 秒，默认 `60` |
| `followRedirects` | 布尔值 | 是否允许重定向，默认 `false` |
| `maxRedirects` | 整数 | 仅 v2，最多允许的跳转次数，0–5，默认 `5` |
| `errors` | 对象 | HTTP 状态码到错误提示的映射，例如 `{"401": "Token 无效"}`，最多 64 项 |
| `refreshCredentials` | 对象 | 仅 v2 上传可用，见[受控刷新](#受控刷新) |

### 请求体

| `body` 参数 | 类型 | 功能与用法 |
| --- | --- | --- |
| `type` | 字符串 | 请求体格式，默认 `multipart`；可选类型见下表 |
| `fileField` | 字符串 | `multipart` 的图片文件字段，默认 `file`；不能与 `fields` 重名 |
| `fields` | 对象 | 固定请求参数，默认 `{}`；支持递归对象、数组和模板 |
| `conditionalFields` | 数组 | 按条件加入的 JSON 字段，1–32 项；仅 v2 前置 JSON 请求可用 |

| `type` | 请求内容 | 适用操作 |
| --- | --- | --- |
| `multipart` | 图片文件与 `fields` 中的附加参数 | 上传 |
| `json` | `fields` 构成的 JSON 对象；前置请求可追加条件字段 | 上传、前置、删除 |
| `form` | 将 `fields` 编码为表单 | 上传、前置、删除 |
| `binary` | 选中图片的原始字节 | 上传 |
| `none` | 不发送请求体 | 上传、前置、删除 |

`GET` 和 `HEAD` 必须不带请求体。前置和删除操作不能发送文件。

### 条件 JSON 字段

**最低版本：Picora `1.0.4`；必需能力：`conditional-json-fields`。**

条件字段不改变 `fields` 的行为。条件不成立时，字段**完全不加入请求体**；不会发送 `null` 或空字符串，也不会渲染该字段的 `value`。

| `conditionalFields[]` 参数 | 类型 | 功能与约束 |
| --- | --- | --- |
| `key` | 字符串 | 要加入的 JSON 键，1–128 字符，不含控制字符；不能与固定字段或其他条件字段重名 |
| `value` | JSON 值 | 条件成立时发送的值，支持模板、对象、数组和标量 |
| `when.config` | 字符串 | 当前插件中已声明的 `text` 配置键，例如 `account`；不能引用密码、开关或选项字段 |
| `when.contains` | 字符串 | 配置文本包含此字符串时成立，区分大小写 |
| `when.notContains` | 字符串 | 配置文本不包含此字符串时成立，区分大小写 |

`contains` 与 `notContains` 必须二选一，匹配字符串长度为 1–256 字符。此能力只支持 `prepare[].body` 且 `type: "json"`。

以下请求体演示聚合图床登录：`account` 为 `text`，`password` 为 `secret`。

```json
{
  "type": "json",
  "fields": {
    "password": "${config.password}",
    "remember_me": false
  },
  "conditionalFields": [
    {
      "key": "email",
      "value": "${config.account}",
      "when": {"config": "account", "contains": "@"}
    },
    {
      "key": "username",
      "value": "${config.account}",
      "when": {"config": "account", "notContains": "@"}
    }
  ]
}
```

将这个 `body` 用于 `POST https://www.superbed.cn/api/v1/auth/login`，在程序根部声明所需 `requires`，并按接口的实际响应设置 `response` 和导出变量。

| `account` 示例 | 发出的 JSON |
| --- | --- |
| `alice@example.com` | `{"email":"alice@example.com","password":"…","remember_me":false}`，不含 `username` |
| `alice` | `{"username":"alice","password":"…","remember_me":false}`，不含 `email` |

### 响应解析与业务判断

响应路径支持 `data.url`、`items[0].url`、`[0].src`，不支持完整 JSONPath。相对图片链接按最终请求 URL 解析。

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

| `response` 参数 | 适用操作 | 用途与默认值 |
| --- | --- | --- |
| `successStatuses` | 全部 | 可接受的 HTTP 状态码，只能为 2xx；上传默认 `[200, 201]`，前置和删除默认全部 2xx |
| `success` | 全部，v2 | 业务成功条件；与 HTTP 状态条件须同时成立 |
| `errorMessage` | 全部，v2 | 响应中的错误消息路径，提取后脱敏 |
| `errorCode` | 全部，v2 | 响应中的错误码路径 |
| `url` | 上传，必填 | 图片链接路径 |
| `thumbnail` | 上传 | 缩略图链接路径 |
| `deleteKey` | 上传 | 单张图片的删除凭证路径，不能返回列表或对象 |
| `deleteUrl` | 上传，v2 | 单张图片的删除 URL 路径 |
| `exports` | 前置，v2 | 显式导出供后续请求使用的变量，见[响应导出](#响应导出) |

`success` 包含一个 `path`，并从以下操作中选择一个：

| 操作 | 值类型 | 判定方式 |
| --- | --- | --- |
| `equals` | 字符串、数字、布尔值或 `null` | 按原始类型比较，不做字符串或数字转换 |
| `exists` | 布尔值 | `true` 要求路径对应值非 `null`；`false` 要求为空或不存在 |
| `containsAny` | 字符串数组 | 匹配其中任一关键词，忽略大小写；1–8 项，每项 2–80 字符 |

### 重定向

重定向默认关闭，启用后每一跳仍检查网络权限和 HTTP 权限。请求不继承全局 Cookie、请求头或查询参数。

- **跨来源跳转**：仅允许无请求体的 `GET`/`HEAD`；移除全部自定义头和原查询参数，拒绝在 `Location` 中携带已知凭证。
- **同来源跳转**：`303`，以及 `POST` 的 `301`/`302`，转为无请求体 `GET`；其它要求重发请求体的跳转停止。
- **文件发送**：不允许跨来源重发文件，也不通过重定向重发上传请求体。

## 前置请求与凭证

`prepare` 最多 4 步，按顺序执行。每步须有唯一的 `id`，格式与配置字段键相同，并至少声明一个响应导出变量。

前置请求只能读取当前配置、包内资源和更早步骤的显式导出，不能读取图片。

```json
{
  "id": "auth",
  "method": "GET",
  "url": "https://api.example.com/token",
  "response": {
    "successStatuses": [200],
    "success": {"path": "ok", "equals": true},
    "errorMessage": "message",
    "exports": {
      "token": {"path": "token", "type": "string", "secret": true}
    }
  },
  "cache": {
    "ttlFrom": "ttl",
    "refreshBeforeSeconds": 30,
    "maxTtlSeconds": 3600
  }
}
```

后续请求通过 `${steps.auth.token}` 使用导出的凭证。

### 响应导出

`response.exports` 最多 16 项，键为导出变量名，格式与配置字段键相同。每项参数如下：

| 参数 | 类型 | 默认值与约束 |
| --- | --- | --- |
| `path` | 字符串 | 必填；JSON 字段路径或响应头名称，最长 120 字符 |
| `type` | 字符串 | `string`、`number` 或 `boolean`，默认 `string`；字符串值最多 4096 字符 |
| `source` | 字符串 | `json` 或 `header`，默认 `json` |
| `required` | 布尔值 | 默认 `true`；缺失必填值时停止上传 |
| `secret` | 布尔值 | 默认 `true`；将导出值视为凭证并用于错误脱敏 |

类型不符或前置请求业务失败时，停止上传，不缓存失败响应。

### 凭证缓存

`cache` 可选；不声明时，每次上传都执行该前置请求。

| 参数 | 类型 | 默认值与约束 |
| --- | --- | --- |
| `scope` | 字符串 | 仅支持 `configuration`，也是默认值 |
| `ttlFrom` | 字符串 | 从响应 JSON 数值路径读取 TTL，单位为秒；与 `ttlSeconds` 二选一 |
| `ttlSeconds` | 整数 | 固定 TTL，1–86400 秒；与 `ttlFrom` 二选一 |
| `refreshBeforeSeconds` | 整数 | 提前刷新量，0–300 秒，默认 `30`；实际提前量不超过 TTL 一半 |
| `maxTtlSeconds` | 整数 | TTL 上限，1–86400 秒，默认 `3600` |

响应 TTL 为 `0` 时不缓存；负数或非数值报错。缓存只存于内存，按插件程序与资源、配置组、配置值及前序导出隔离。

并发上传合并同一凭证获取请求。修改配置，或安装、更新、停用、卸载插件时，会清空缓存。

### 受控刷新

在 `upload.refreshCredentials` 中声明明确的凭证失效响应：

```json
{
  "steps": ["auth"],
  "statuses": [403],
  "condition": {"path": "message", "containsAny": ["凭证", "token"]},
  "maxAttempts": 1
}
```

| 参数 | 类型 | 功能与约束 |
| --- | --- | --- |
| `steps` | 字符串数组 | 必填，1–4 个前置步骤 ID；引用步骤必须有缓存 |
| `statuses` | 整数数组 | 默认 `[401]`，最多 8 项；仅支持 `200`、`201`、`400`、`401`、`403`、`409`、`410`、`422` |
| `condition` | 对象 | 使用响应条件语法；匹配明确错误码或凭证错误关键词，不能以 `ok == false` 作为重传条件 |
| `maxAttempts` | 整数 | 固定为 `1`，也是默认值 |

只有 `401` 可仅按状态判断，其它状态必须同时匹配凭证失效条件。规则应依据目标服务的实际响应设置。

> **重试边界：**刷新后最多重试一次，第二次失败即停止。已返回图片 URL、超时、断线和 5xx 不自动重传；前置和删除操作不自动重试。并发旧凭证失败不会撤销已经获取的新凭证。

## 单张图片删除

v2 删除由用户在图片详情中单独确认，或在已开启同步删除授权时从相册删除记录触发。单独删除云端图片会保留上传记录和本地文件；成功状态会保存，后续删除记录不再重复请求云端接口。

- 模板使用 `${upload.deleteKey}` 或 `${upload.deleteUrl}`，也可读取 `${upload.url}`；不提供 `config`、`steps`、`file` 或 `assets`。
- 上传记录须匹配插件、原配置组及配置修订；配置修改后停止删除，网络端点仍依据原配置校验。
- 缺失删除凭证或原配置时停止并保留记录，不使用其它配置作为后备。
- 插件不接收相册列表、目录或其它图床凭证；删除须同时通过 HTTP 与业务判断。

## 模板与资源

| 表达式 | 值或用途 |
| --- | --- |
| `${config.key}` | 当前配置组中声明的字段 |
| `${steps.auth.token}` | 前序步骤显式导出的值，v2 |
| `${file.name}`、`${file.mime}`、`${file.bytes}`、`${file.base64}` | 选中图片的文件名、MIME 类型、字节或 Base64；`${file.path}` 仅 v1 可用 |
| `${upload.url}`、`${upload.deleteKey}`、`${upload.deleteUrl}` | 单张上传记录，供删除请求使用 |
| `${uuid}`、`${time.millis}`、`${time.unix}` | UUID、毫秒时间戳、秒时间戳 |
| `${base64(file.bytes)}`、`${sha256(file.bytes)}` | Base64 编码、SHA-256 摘要 |
| `${hmacSha256(config.secret,file.bytes)}` | HMAC-SHA256 |
| `${basicAuth(config.username,config.password)}` | Basic 认证；两项均空时返回空串，用于请求头时省略该头；只填一项则报错 |
| `${normalizeBaseUrl(config.baseUrl)}` | 规范化基础 URL |
| `${urlEncode(config.key)}` | URL 参数编码 |
| `${assets/data.bin}`、`${assetText(assets/template.txt)}` | 包内资源的字节或 UTF-8 文本 |

整串表达式保留原始类型；嵌入文本时转为字符串，字节转为 Base64。函数参数为变量，不支持脚本、嵌套函数、循环或动态文件路径。

`icon` 用于插件与图床列表。教程配图使用 `![图示](assets/example.png)`，不会自动加载远程图片；SVG 应包含自身需要的全部资源。

## 更新与安全边界

### 覆盖更新

同 ID 更新会替换程序、教程和资源，保留配置与启用状态。允许同版本重装，拒绝降级；插件版本遵循 SemVer，`id` 和 `config.key` 应保持稳定。更新后，云端删除权限需要用户重新开启。

### 资源限制

| 对象 | 上限 |
| --- | --- |
| 程序结构 | 5000 个节点、16 层嵌套；单个字符串 16384 字符 |
| ZIP 文件 | 10 MB；解压合计 20 MB；最多 128 个条目 |
| 包内文件 | 单文件 2 MB；元信息与程序各 1 MB；`readme.md` 512 KB |
| 上传图片 | 100 MB |
| HTTP 响应 | 1 MB |
| 凭证缓存与并发凭证请求 | 各最多 128 项 |

安装器拒绝路径穿越、链接文件、加密、CRC 错误与不支持的压缩方式。

### 权限边界

插件不能执行系统命令、枚举文件、读取其它配置组或直接删除本地文件。诊断记录插件、配置组、步骤、HTTP 状态及失败类型，不写入响应正文、请求头或凭证。

网络权限限制请求目标，但不能证明服务端接口没有破坏性副作用。插件仍能使用交给它的当前配置凭证；应审核来源，使用仅上传或单对象权限的凭证，不向第三方插件提供管理员密钥。ZIP 摘要用于完整性检查，不是作者身份签名；同 ID 更新也应核对来源。

## 打包与发布

在项目根目录执行：

```powershell
.\tools\package-plugin.ps1 -SourceDirectory '.\plugins\my-host' -OutputPath '.\releases\plugins\my-host-1.0.0.picora-plugin.zip'
```

用户可从模块仓库、本地 ZIP 或下载 URL 安装插件；错误详情位于“设置 → 诊断日志”。

投稿登记与发布更新见[插件提交流程](插件提交流程.md)。
