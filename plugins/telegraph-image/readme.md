# Telegraph-Image

![插件图标](assets/icon.svg)

为 Picora 添加 cf-pages/Telegraph-Image 自建图床上传功能。本示例移植原 PicGo 插件的上传流程，可以为多个站点分别创建配置。

## 安装与配置

1. 在“插件中心 → 安装插件”导入此 ZIP 文件。
2. 在“仓库 → 添加配置”搜索 Telegraph-Image。
3. 填写配置名称，例如“主站”或“备用站”。
4. 填写图床基础 URL，例如 `https://images.example.com`；不要附加 `/upload`、查询参数或锚点。
5. 保存后在上传页面选择此配置，再选择图片上传。

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
