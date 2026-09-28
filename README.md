# WMusic

WMusic 是面向 macOS 本地曲库的播放器开发工作区。`player/` 是从开源 [Bòcan](https://github.com/bocan/bocan-music) 引入的独立 SwiftUI 播放器候选；`themes/WMusic-Nocturne/` 与现有 foobar2000 配置保留作视觉参考和回滚资料。两个播放器的数据与安装目录彼此独立。

## 本地开发

开发机需要 Apple Silicon、macOS 15+、Xcode 26+、Homebrew，以及 FFmpeg、Chromaprint、TagLib、XcodeGen。依赖与首次生成步骤见 [player/DEVELOPMENT.md](player/DEVELOPMENT.md)。`player/Secrets.xcconfig` 可从同目录模板复制，空值即可编译本地播放；不要填入或提交个人 API 凭据。

```sh
./script/build_and_run.sh --verify
```

该命令构建工作区内的 WMusic 候选并启动构建产物，不安装到 `/Applications`。导入曲库时请先使用独立的测试音频目录；不要直接指向 foobar2000 的配置库或个人音乐目录做开发验收。

## 目录

- `player/`：播放器源码与其原始 Apache-2.0 许可、第三方声明；[来源与本地改动](player/UPSTREAM.md)。
- `themes/WMusic-Nocturne/`：现有 foobar2000 深蓝主题、布局和组件清单。
- `window-resize-hook.m`、`build/`、`backups/`：旧 foobar2000 定制与回滚材料，不属于新播放器构建。
- [选型与验收口径](PLAYER_SELECTION.md)：候选项目比较与取舍。
- [本地候选验收记录](VALIDATION.md)：构建、运行、合成音频播放和仍待确认的能力。

`DEVELOPMENT_PLAN.md` 是 2025 年从零开发 Rust/Tauri 跨平台播放器的历史提案；当前 macOS 实施方案以本文和 `PLAYER_SELECTION.md` 为准。
