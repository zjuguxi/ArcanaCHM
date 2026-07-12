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
- 路径沙箱保护 — 不会访问 app 数据目录以外的文件。
- 130 个单元测试，覆盖安全策略、TOC 解析、书库持久化、CHM 导入、编码、数据模型。

## 系统要求

- macOS 14+

## 构建

```bash
swift build                       # 编译可执行文件
Scripts/package_app.sh            # 生成 dist/ArcanaCHM.app
Scripts/package_dmg.sh 1.3.2      # 生成可分发的 DMG
```

打包过程中会自动对 app 进行 ad-hoc 签名，避免 macOS 误报「应用已损坏」。

## 使用

- `⌘O`：导入 CHM 文件
- `⇧⌘O`：导入已解压的文件夹
- 目录标签页：文档导航
- 搜索标签页：全文搜索
- 收藏标签页：书签

## 许可证

MIT
