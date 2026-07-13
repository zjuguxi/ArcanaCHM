[English](./README.md)

# ArcanaCHM

本地优先的 macOS CHM 阅读器。原生 SwiftUI，离线运行。

**主页：** https://zjuguxi.github.io/ArcanaCHM/

## 功能

- 三栏 SwiftUI 布局，WebKit 阅读引擎。
- 直接导入 `.chm` 文件 — 解压工具（`7zz`）内置在 app 中，无需安装 Homebrew。
- 支持导入已解压的文件夹。
- 阅读记忆：每本书记住最后页面和滚动位置（500ms 防抖）。
- 书签、搜索历史、全文搜索。
- 页面内查找（Cmd+F）支持前后匹配导航。
- 双语界面：中文 / English（默认跟随系统，可在工具栏切换）。
- 浅色 / 深色主题，字体缩放，专注模式。
- `library.json` 自动备份 — 文件损坏时自动从备份恢复。
- 可预览并从托管书籍目录重建书库，替换元数据前自动保存只读快照。
- 路径沙箱保护 — 不会访问 app 数据目录以外的文件。
- 180 个单元与性能测试，覆盖安全策略、TOC 解析、隔离的书库持久化、恢复快照、受限 CHM 导入、编码和数据模型。

## 系统要求

- macOS 14+

## 构建

```bash
swift build                       # 编译可执行文件
Scripts/package_app.sh 1.3.6      # 生成本地 ad-hoc 签名应用
Scripts/package_dmg.sh 1.3.6      # 生成可分发的 DMG
```

本地包使用 ad-hoc 签名。Git 标签发布必须在 GitHub Actions 中完成 Developer ID 签名、Hardened Runtime、公证和 stapling。内置 7-Zip 的归档与二进制都会校验固定 SHA-256。

导入归档受文件数量、大小、目录深度、磁盘空间和执行时间限制。应用数据路径采用依赖注入，测试只使用带唯一名称的临时目录，不会访问生产书库。

## 使用

- `⌘O`：导入 CHM 文件
- `⇧⌘O`：导入已解压的文件夹
- App 菜单 → 从 Books 重建书库：预览并恢复书库元数据
- 目录标签页：文档导航
- 搜索标签页：全文搜索
- 收藏标签页：书签

## 许可证

MIT
