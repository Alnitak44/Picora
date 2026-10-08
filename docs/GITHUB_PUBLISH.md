# GitHub 发布准备

本文面向 Picora 维护者。源码根目录为工程本身，当前 Windows 路径为 `D:\项目\Picora\PicHero`；目录名仍为 PicHero，不影响 GitHub 项目名 Picora。

## 当前整理结果

- README、插件开放说明、协议文档、模板、界面预览和 Issue / PR 模板已整理。
- 版本为 `1.0.0+2`，显示版本从 1.0.0 起独立维护，说明基于 PicHoro v3.0.1。
- 保留 LICENSE、上游历史、第三方声明、锁文件和 Android vendor 补丁。
- 主 Android Gradle Wrapper 应提交，避免新克隆缺失启动脚本或 JAR；.gitattributes 固定脚本换行，提交时为 gradlew 设置可执行位。
- 本机 SDK、缓存、构建产物、日志、密钥、环境脚本和插件分发 ZIP 已由忽略规则排除；应用所需的 assets/plugins 示例 ZIP 仍保留。
- 源码仓库由 Alnitak44/PicHoro 改名为 Alnitak44/Picora，保留原 fork 的 ID 和历史。APK 构建、tag 与 Release 单独处理；在线插件市场仍未实现。

**当前 origin 指向 Alnitak44/Picora，upstream 保留 Kuingsmile/PicHoro。** 发布前检查 remote URL；只向自己的 origin 推送，不向 upstream 发布。

## 提交前检查

使用工具中的 git 或系统 git，在工程根目录运行：

```powershell
git status --short
git remote -v
git ls-files -ci --exclude-standard
git diff --cached --stat
```

git ls-files -ci 若仍有输出，说明文件已被跟踪，后来写入 .gitignore 不会自动取消跟踪，需要针对具体文件处理。iOS 的生成环境脚本已取消跟踪，工作树文件仍保留。

不得上传 `.tooling/`、`artifacts/`、`build/`、`.dart_tool/`、APK/AAB、key.properties、local.properties、keystore、私人配置导出或日志。不要通过删除整个目录、reset --hard 或 git clean 来整理，它们可能包含未提交的业务修改和本机工具。

源码导出可独立执行：

```powershell
.\tools\export-source.ps1
```

结果位于 `artifacts/github/Picora-source-1.0.0.zip`，以及同目录的文件 SHA-256 清单。导出读取**当前工作树**，包含新增源码，过滤已删除及忽略文件；不是 git archive HEAD。ZIP 不含 .git 历史，也不包含 SDK 或可安装 APK，可供审阅或解压后上传；推荐正式发布保留现有 Git 历史。

脚本检查禁止路径与文件大小，并拒绝链接文件，但它不是完整内容/历史密钥审计工具。提交前仍应审阅候选源码；不要把真实图床配置混进示例。根目录 .gitignore 不会追溯删除旧 Git 历史中的数据。

## 远程仓库与后续提交

发布目标为 `https://github.com/Alnitak44/Picora.git`，由现有 fork 改名而来，不需要重新建仓库。本地 origin 为 Picora，upstream 为 Kuingsmile/PicHoro，保留上游历史便于追溯。

以后在工程根目录提交修改：

```powershell
git remote -v
git branch --show-current
git add --all
git update-index --chmod=+x android/gradlew
git diff --cached --stat
git diff --cached --check
git status --short
git commit -m "Describe the change"
git -c http.proxy=http://127.0.0.1:7890 push origin main
```

推送前确认分支是 main、origin 指向自己的 Picora 仓库，提交包括新增文件及必要的删除状态。首次推送用 `push -u origin main` 建立跟踪关系，之后可以直接使用 git push。代理仅作用于该条命令；FlClash 7890 必须可用。

新克隆的工程自然使用 Picora 作为 origin。旧副本若仍指向上游，可以按实际远程清单配置；已有 upstream 时不要重复 rename：

```powershell
git remote rename origin upstream
git remote add origin https://github.com/Alnitak44/Picora.git
git remote -v
```

GitHub 页面上的仓库名在 Settings → General → Repository name 中调整；仓库改名不等于重新创建，也不移除 fork 关系。本工程已完成该改名。

不要把 GitHub Token 写进 URL 或脚本，使用系统 Git Credential Manager 认证。当前工程提交身份为 Alnitak44 和 GitHub noreply 邮箱，只设置在本仓库。目标分支有其他提交时先 fetch 并比较，不默认 force push。

## APK 与 Release

源码上传不等于 APK 已发布。需要安装包时按 [打包说明](../打包说明.md)执行，只构建 ARM64，保留发布签名。

- 下次按当前源码构建的 Debug 显示版本应为 `1.0.0-debug`，分 ABI ARM64 versionCode 应为 2002；现有旧包为 3.0.1-debug / 2001，不要改个文件名就当成新版。
- Release 显示版本为 1.0.0，正式 keystore 与 Debug 签名不同，无法直接覆盖对方。
- APK 附加到 GitHub Release，不提交进源码树；记录架构、版本、签名与 APK SHA-256。
- v1.0.0 tag 应指向实际交付的源码提交，未构建/验收时不要宣称对应 APK 已测试通过。
- 插件 ZIP 在插件自己的仓库 Release 中分发；本仓库的 template 和 telegraph-image 是源码。GitHub 自动生成的 Source code ZIP 不是可安装插件包。

## 验证记录

本次文件整理的实际检查结果见导出时生成的清单与工作日志；Flutter 测试使用已有包缓存，不需要为文档整理触发 APK 编译。其他机器需要自行安装 README 中的工具，不应上传或复制维护者的私人密钥。
