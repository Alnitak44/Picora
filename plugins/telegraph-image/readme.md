# Telegraph-Image

![插件图标](assets/icon.svg)

为 Picora 添加 [cf-pages/Telegraph-Image](https://github.com/cf-pages/Telegraph-Image)自建图床支持。需要先搭建起项目并配置好域名。
## 安装与配置

1. 在“插件中心 → 模块仓库”安装 Telegraph-Image，也可通过“安装插件”导入此 ZIP 文件。
2. 在“仓库 → 添加配置”找到 Telegraph-Image。
3. 直接填入你的域名，如``https://example.com``，不需要任何多余参数，不要在域名后加``/upload``

## 上传鉴权

未开启上传鉴权时，用户名与密码都留空。开启后，两项必须同时填写，这是**上传接口的账号**，可能与后台管理账号不同。请求使用 HTTP Basic Authorization。

上传地址为基础 URL 后的 `/upload`，以 multipart 的 `file` 字段发送图片。成功响应应包含 `[0].src`；相对路径会自动转换为完整图片链接。

## 常见问题

- **401**：检查上传用户名和密码，确认服务端允许 Basic 鉴权。
- **403**：检查 Cloudflare Access、WAF 或站点访问限制。
- **404**：检查基础 URL；确认部署提供 `/upload`。
- **413**：图片超过站点或代理大小限制。
- **429**：降低批量上传频率，稍后重试。
- **重定向 / 返回 HTML**：本示例关闭跟随重定向。填写上传服务的最终 HTTPS 地址，检查登录拦截。

失败时可在“设置 → 诊断日志”查找错误编号。本示例不提供云端删除接口。

## 权限与资源

该图床地址由用户配置，因此网络主机声明为 `*`。示例同时允许 HTTP 以兼容自建测试环境，实际站点建议填写 HTTPS。仅处理用户主动选择的上传文件。

`plugin.json` 保存名称、版本、作者和项目链接；`uploader.json` 保存配置项和上传程序；`assets/icon.svg` 为图床列表、选择器与教程提供图标。

[Telegraph-Image 项目与部署说明](https://github.com/cf-pages/Telegraph-Image)
