# Picora 插件开发说明

## 十分钟起步：创建自己的插件

完整可复制模板在 [plugins/template](../plugins/template)，接口为占位地址，需要改成实际服务。以下命令在 Picora 工程根目录执行：

```powershell
Copy-Item -LiteralPath '.\plugins\template' -Destination '.\plugins\my-host' -Recurse
# 编辑新目录中的 plugin.json、uploader.json、readme.md 和 assets/icon.svg
.\tools\package-plugin.ps1 -SourceDirectory '.\plugins\my-host' -OutputPath '.\releases\plugins\my-host-1.0.0.picora-plugin.zip'
```

不要沿用模板 ID，填写自己长期维护的反向域名 ID，例如 `io.github.yourname.imagehost`。源目录与输出目录必须分开。初次输出不需要 `-Force`；只在明确要替换旧 ZIP 时使用它。

假设实际接口接受 `POST https://api.example.com/upload`，图片字段为 `file`，Token 放入 Authorization，响应如下：

```json
{
  "data": {
    "url": "https://cdn.example.com/image.png",
    "thumbnail": "https://cdn.example.com/thumb.png",
    "id": "image-id"
  }
}
```

模板已经对应此接口形状：`response.url = data.url`。根据真实接口修改后，导入 ZIP → 确认权限 → 添加图床配置 → 填写 Token → 上传一张测试图 → 核对图片链接与教程图标。这里的 example.com 不提供实际服务。

若接口返回数组 `[{"src": "/file/image.png"}]`，将 response.url 改为 `[0].src`，并删除接口没有提供的 thumbnail / deleteKey 字段。相对链接按**实际请求 URL**解析，例如上传地址含路径时须核对服务的返回语义。

无需安装 Flutter 或编译 APK 就能用 PowerShell 打插件 ZIP；验证真实上传仍需 Picora 与实际服务。

## 用户如何安装和使用

打开“仓库 → 插件中心 → 安装插件”，选择本地 ZIP，或填写 ZIP 的 HTTP/HTTPS 下载地址。安装前显示名称、版本、作者、说明与网络权限；同一个普通插件 ID 再安装会更新程序和教程，已有图床配置保留；应用附带示例 ID 不可由外部包覆盖。

插件卡片的“使用教程”以及详情菜单的“插件主页与使用教程”会打开包内 `readme.md`。教程可离线阅读，支持 Markdown、代码块、HTTP/HTTPS 链接与本地资源图片。详情可导出整个 ZIP，也可停用或卸载。停用保留配置；卸载前先删除该插件的图床配置，历史上传记录仍保留。

每个原生上传插件注册一个图床类型。用户可以在此类型下创建多个独立配置，例如 Telegraph 主站/备用站，每个类型当前最多 26 组。不同配置使用各自的地址和凭据。

## 能力边界

- **Picora 原生 ZIP 插件**：Android 独立运行，`http-v1` 程序以 JSON 描述配置表单、HTTP 上传/删除、鉴权模板及响应映射；可访问自己包内的静态资源。
- **PicGo Bridge**：通过电脑或 NAS 上的 PicGo Server 调用现有 PicGo 插件。ZIP 格式不代表增加了 Node.js 或 JavaScript 运行环境；不能把 PicGo 的 npm ZIP 包直接导入 Picora。

PicGo Bridge 的 multipart 上传地址为 `POST /upload`。选择特定上传器/配置的兼容要求沿用此前实现。插件扩展暂不支持任意 Dart/JS 代码、动态应用页面、多步骤 OAuth 或自定义系统能力；需要新增运行能力时应单独扩展宿主 API。

## ZIP 目录结构

文件必须直接位于 ZIP 根目录，**不要把整个插件文件夹再套一层**。文件名区分大小写，路径分隔符必须为 `/`。

```text
my-plugin.picora-plugin.zip
├── plugin.json       # 机器可读的元信息和入口
├── readme.md         # 面向用户的介绍、教程、常见问题
├── uploader.json     # 插件程序；文件名由 entry 指定
└── assets/           # 图标、教程图片、静态文本等资源
    ├── icon.svg
    └── example.png
```

作者、版本、GitHub 地址等放在 `plugin.json`，保证应用不需要解析教程才能显示。README 可以补充介绍，但不会覆盖元信息。一个包对应一个上传对象类型，该类型可添加多个配置。

## plugin.json 元信息

```json
{
  "packageVersion": 1,
  "runtime": "http-v1",
  "entry": "uploader.json",
  "id": "com.example.image-host",
  "name": "Example Host",
  "version": "1.0.0",
  "description": "上传到 Example Host",
  "author": "Your Name",
  "homepage": "https://example.com/plugin",
  "repository": "https://github.com/YourName/YourPlugin",
  "icon": "assets/icon.svg",
  "mark": "EX",
  "color": "#6377E8"
}
```

| 字段 | 要求与作用 |
| --- | --- |
| packageVersion | 必须为数字 `1`，代表 ZIP 包协议版本 |
| runtime | 必须为 `http-v1`，代表声明式 HTTP 程序 |
| entry | 必填，指向包内 JSON 程序；不能是 plugin.json 或 assets/ 文件 |
| id | 必填，反向域名式小写 ID，最长 80；更新必须保持相同 ID |
| name | 必填，图床和插件名称，最长 60 |
| version | 必填，最长 30，建议语义版本；显示用，同 ID 安装会替换，不阻止降级 |
| description | 必填，简述功能，最长 160 |
| author | 必填，作者或组织名，最长 80 |
| homepage | 可选，HTTP/HTTPS 项目网站或帮助页 |
| repository | 可选，HTTP/HTTPS 源码地址，可以填 GitHub 仓库 |
| icon | 可选，必须引用 assets/ 中存在的 PNG/JPG/JPEG/WebP/GIF/SVG |
| mark | 可选，1–3 字符，无图标或图片解码失败时回退，默认 P |
| color | 可选，图床识别色，`#RRGGBB` |

图标会用于图床列表、添加类型菜单、配置编辑器、上传目标选择和插件页面。推荐使用简洁的 96×96 或 192×192 图标，SVG 必须自包含；不依赖外部 URL 或字体。

## uploader.json 程序

```json
{
  "schemaVersion": 1,
  "permissions": {
    "network": ["api.example.com", "*.cdn.example.com"],
    "readSelectedFile": true,
    "allowInsecureHttp": false
  },
  "config": [
    { "key": "token", "label": "API Token", "type": "secret", "required": true }
  ],
  "upload": {
    "method": "POST",
    "url": "https://api.example.com/upload",
    "headers": { "Authorization": "Bearer ${config.token}" },
    "body": { "type": "multipart", "fileField": "file" },
    "response": {
      "url": "data.url",
      "thumbnail": "data.thumbnail",
      "deleteKey": "data.id",
      "successStatuses": [200, 201]
    },
    "timeoutSeconds": 60,
    "followRedirects": false,
    "errors": { "401": "Token 无效" }
  }
}
```

`schemaVersion` 必须为数字 1。`config.type` 支持 text、secret、toggle、select，select 必须提供非空 options；配置 key 唯一。请求方法支持 POST、PUT、PATCH、DELETE，请求体支持 multipart、json、form、binary、none。`delete` 可选，结构与上传请求相同但不需要 response 字段。

网络权限支持精确主机、`*.example.com` 或 `*`。HTTP 还必须声明 allowInsecureHttp。宿主限制目标主机，并禁止设置 Host 与 Content-Length。配置由用户输入、各配置独立存储，插件程序不能读取别的配置。

## 资源与教程

在 README 中使用 `![示意图](assets/example.png)` 或 `![图标](assets/icon.svg)`。可用 `./assets/...`，不允许逃出资源目录。教程不自动加载远程图片；联网教程可提供网页链接。图片解析失败会显示占位文字，图床图标失败会回退到 mark。

程序也能引用自己的资源：

- `${assets/data.bin}`：完整表达式返回资源字节数组，可作为摘要/编码函数的输入。binary 请求体仍发送用户选择的上传文件。
- `${base64(assets/icon.png)}`：将资源编码为 Base64，可用作 JSON 值。
- `${assetText(assets/template.txt)}`：将 UTF-8 文本资源作为字符串，适用于字段或请求头。
- `${sha256(assets/data.bin)}`：计算包内资源摘要。

资源路径是字面量，不加引号；函数不能嵌套。不会执行资源中的脚本，也不会读取插件包外的文件。

## 生成 ZIP 与示例

完整 Telegraph 示例源码在 `plugins/telegraph-image/`，可安装包在 `releases/plugins/telegraph-image-1.1.0.picora-plugin.zip`。应用自带相同的“示例”包，ID 保持 `dev.picora.telegraph-image`；这个 ID 由示例占用，开发新插件请改为自己的唯一 ID。

在项目根目录使用 PowerShell：

```powershell
.\tools\package-plugin.ps1 `
  -SourceDirectory '.\plugins\telegraph-image' `
  -OutputPath '.\releases\plugins\telegraph-image-1.1.0.picora-plugin.zip' `
  -Force
```

脚本只打插件 ZIP，不编译 Android。它检查基础结构、资源目录、链接文件和体积，输出文件不能放在源码目录内。完整协议与运行校验由 Picora 安装器执行；脚本通过不等于插件 API 一定可用。修改应用自带示例后，还要将新 ZIP 复制到 `assets/plugins/telegraph-image.picora-plugin.zip`。

## 旧版插件迁移与存储

启动时将应用私有目录 `picora-plugins/` 内旧版单文件 JSON 自动封装为 ZIP，插件 ID、图床 ID、配置槽位不变。旧文件成功转换后保留为 `.json.legacy` 备份。缺失的 README 会补一页迁移说明，原文件没有教程时不会虚构教程。

新包保存在 `<应用支持目录>/picora-plugins/<id>.zip`；配置保存在旁边 `picora-plugin-repositories.json`，不写入分享 ZIP。包会先写 `.pending`、成功后重命名，校验失败不替换现有版本。资源从 ZIP 读到内存，**不解压到任意磁盘路径**。

安装器拒绝绝对路径、反斜杠、`..`、大小写重复路径、链接文件、加密 ZIP、非 Store/Deflate 压缩；检查实际解压大小、CRC 和必要文件。版本信息和教程应使用 UTF-8。错误会经统一诊断记录显示编号，查看“设置 → 诊断日志”。

## 模板变量

- 配置：`${config.token}`
- 文件：`${file.name}`、`${file.path}`、`${file.mime}`、`${file.bytes}`、`${file.base64}`
- 上传结果：`${upload.url}`、`${upload.deleteKey}`
- 运行值：`${uuid}`、`${time.millis}`、`${time.unix}`
- 函数：`${base64(config.token)}`、`${sha256(file.bytes)}`、`${hmacSha256(config.secret,file.bytes)}`
- HTTP Basic：`${basicAuth(config.username,config.password)}`；两项都为空时省略该请求头
- 基础 URL：`${normalizeBaseUrl(config.baseUrl)}`；自动补 `https://` 并拒绝用户信息、查询参数、锚点和末尾 `/upload`

响应路径支持 `data.url`、`items[0].url` 和 `[0].src`。相对图片地址会按上传请求 URL 转为绝对地址。

## 删除请求

上传响应声明 `deleteKey` 后，可以增加与 `upload` 同级的 `delete` 请求。删除模板可使用保存到上传记录中的 `${upload.url}` 与 `${upload.deleteKey}`。没有 `delete` 的插件仍可正常上传；启用“同步删除云端文件”时，Picora 会明确提示该插件不支持删除。

## 安全与调试

插件配置与其他图床配置一样保存在应用私有目录。诊断日志会过滤密码、Token、Authorization、Cookie、签名参数和 `pictureKey`。ZIP 上限 10 MB，解压内容合计 20 MB，最多 128 个条目。每个文件最多 2 MB，plugin.json 和程序文件各最多 1 MB，readme.md 最多 512 KB。配置字段最多 30 个，请求超时范围为 5–300 秒。

开发时可复制 plugins/telegraph-image/ 作为起点。安装后先用无敏感信息的测试图床验证；请求失败会在 Snackbar 显示诊断编号，完整上下文可在“设置 → 诊断日志”查看。

## 配置字段完整示例

字段格式可直接放入 uploader.json 的 `config` 数组：

```json
[
  {
    "key": "token",
    "label": "API Token",
    "type": "secret",
    "hint": "在服务控制台获取",
    "required": true
  },
  {
    "key": "folder",
    "label": "保存目录",
    "type": "text",
    "default": "images"
  },
  {
    "key": "visibility",
    "label": "可见性",
    "type": "select",
    "options": ["public", "private"],
    "default": "public"
  },
  {
    "key": "keepOriginal",
    "label": "保留原图",
    "type": "toggle",
    "default": false
  }
]
```

`key` 必须符合 `[A-Za-z][A-Za-z0-9_]{0,39}`，不得重复；label 必填且不超过 50 字符。required 仅在明确为 true 时启用；default 使用相应类型的 JSON 值。select 的 options 当前是字符串数组，不支持“显示标签 / 实际值”对象。

升级插件时不要随意改 key 或原字段的语义，已有配置按 key 保存，不会自动迁移为新字段。不要把用户的真实 Token 写成 default。

## 请求、请求体与结果映射

upload 和 delete 的可用字段：

| 字段 | 行为 |
| --- | --- |
| method | POST / PUT / PATCH / DELETE；默认 POST，不支持 GET 上传请求 |
| url | 支持模板的完整 HTTP/HTTPS URL，必填 |
| headers | 对象；空字符串值会省略该请求头；不可设置 Host / Content-Length |
| query | 对象；用于查询参数，交给 HTTP 客户端编码 |
| body | 上传时必填；删除时省略则为 none |
| followRedirects | 缺省为 true，建议显式 false；主机授权校验发生在初始请求地址 |
| timeoutSeconds | 默认 60，5–300；应用于发送和接收超时，不是整个操作的总时限 |
| errors | HTTP 状态码字符串 → 用户提示；目前自定义提示用于上传 |
| response | 上传必须提供；删除不读取此字段 |

| body.type | 内容与写法 |
| --- | --- |
| multipart | 用户图片由 fileField 指定字段名，默认 file；附加参数放 fields |
| json | 整个请求体来自 fields，不自动附加图片；可用 file.base64 填入字段 |
| form | fields 发送为表单编码，不自动附加二进制图片 |
| binary | 直接发送本次用户图片字节；不会拿 assets 资源替换用户图片 |
| none | 不发送请求体，适用于某些删除接口 |

例如 JSON 上传：

```json
{
  "type": "json",
  "fields": {
    "filename": "${file.name}",
    "content": "${file.base64}",
    "settings": {
      "visibility": "${config.visibility}"
    }
  }
}
```

fields 的对象和数组会递归解析模板；字典 key 不会解析。整串 `"${...}"` 保留解析结果类型，例如布尔、整数或字节列表；混在文本中的模板转为字符串，字节列表转为 Base64。缺失配置值会变为空字符串，未知变量会报错。模板函数只接受变量参数，不支持字面量、嵌套函数、条件表达式、循环、JavaScript 或任意 URL 编码函数。

上传成功条件为：HTTP 状态在 response.successStatuses 中，response.url 指向非空的 HTTP/HTTPS 图片链接。response.thumbnail 和 response.deleteKey 可省略；无缩略图时用原图链接。路径只支持对象键和数字索引，不是完整 JSONPath，不支持通配符、过滤器或递归搜索。

当前不支持按响应中的业务 code / success 布尔值进行额外条件判断；如果服务 HTTP 200 但业务失败，通常会表现为“没有找到图片链接”，应查看服务响应与诊断。不能把 minAppVersion 放进 ZIP 就认为宿主会检查兼容性：目前 ZIP 协议未实现此字段的校验，在线目录中的 minAppVersion 仍是规划。

## 可选删除接口示例

以下对象可添加到 uploader.json 的同级 delete 字段；根据实际 API 修改路径和认证：

```json
{
  "method": "DELETE",
  "url": "https://api.example.com/images/${upload.deleteKey}",
  "headers": {
    "Authorization": "Bearer ${config.token}"
  },
  "body": { "type": "none" },
  "followRedirects": false,
  "timeoutSeconds": 30
}
```

删除成功按 HTTP 2xx 判断，不读取上传的 response.successStatuses，也不解析服务业务状态。服务如果将失败藏在 2xx 响应中，现有协议不能准确识别这种业务失败。配置 key 与历史 deleteKey 必须继续兼容，删除接口变更时明确说明旧记录是否还可删除。

## 覆盖更新与兼容约定

| 操作 | 当前结果 |
| --- | --- |
| 相同 ID 导入新 ZIP | 校验通过后替换程序、资源与教程，保留图床配置；重新启用插件 |
| ID 改成新值 | 注册另一个图床类型，不会迁移旧配置 |
| 同版本重装 / 较低版本导入 | 当前允许，尚未比较版本大小 |
| ZIP 校验失败 | 不替换现有插件 |
| 安装应用附带示例 ID | 拒绝覆盖；示例只可停用，不可卸载 |
| 卸载普通插件 | 先删除其图床配置；不删除历史上传记录 |

示例保留 ID 为 `dev.picora.telegraph-image`；自己的插件必须换 ID。版本建议使用 `1.0.0`、`1.0.1` 等语义版本，但目前它是展示信息。一次上传用一条请求，复杂签名协议、多步骤认证、分片上传、动态表单、自定义页面和云端浏览不在当前 http-v1 扩展能力内。

## 发布与调试顺序

1. 对照服务官方 API 文档确认请求，检查凭据、字段与返回 JSON。
2. 在 plugin.json 更新版本、作者、源码地址，readme.md 写配置教程和改动说明。
3. 打包 ZIP，使用新安装和同 ID 覆盖分别验证；已有配置无需重新建立。
4. 验证图标、离线教程、至少一张图片上传、缺失凭据、错误 HTTP 状态；支持删除时单独验证。
5. 在自己的 GitHub 仓库打 tag 并上传安装 ZIP 到 Release。用户填的是 **Release 附件下载 URL**，不是源码仓库首页，也不是 GitHub 自动生成的 Source code ZIP。
6. 下载 ZIP 后复装核对名称、版本、文件结构；需要时另行提供 ZIP SHA-256。

```powershell
Get-FileHash -LiteralPath '.\releases\plugins\my-host-1.0.0.picora-plugin.zip' -Algorithm SHA256
```

| 症状 | 检查点 |
| --- | --- |
| 无法读取 ZIP / 缺少 plugin.json | ZIP 根目录是否又套了一层；下载的是否 HTML 页面或源码 ZIP |
| 无权访问主机 | network 填主机名，不带协议、端口或路径；子域通配不包含根域 |
| 无明文 HTTP 权限 | 使用 HTTPS，或在确有需要时声明 allowInsecureHttp |
| 找不到图片链接 | 真实返回 JSON、url 路径、HTTP 200 中的业务失败 |
| 模板变量不存在 / 函数参数无效 | 拼写、支持列表、不要嵌套函数或使用带引号的字面量 |
| 401 / 403 / 413 / 429 | 鉴权、访问控制、文件大小、限流；在 errors 中给明确提示 |
| 图标 / 教程图片不显示 | assets 路径与大小写、SVG 是否自包含、图片格式是否可解码 |
| 更新后配置不生效 | 插件 ID 或 config.key 是否变化、安装是否重新启用 |
| 真实 PicGo 插件导入失败 | 原生 JSON 协议与 Node.js 插件不同，改用 PicGo Bridge 或移植 |

网络权限是插件的请求声明，不是任意脚本沙箱；初始 URL 校验不意味着允许跟随重定向到任何主机，推荐关闭重定向并直接配置最终上传地址。教程中的外部网页由用户点击后在浏览器打开。

## 在线插件目录（设计方案）

GitHub 目录仓库、Release ZIP 分发、版本与摘要校验的下一阶段方案见 [在线插件生态方案](PLUGIN_MARKETPLACE.md)。当前应用尚未接入线上目录。
