# WMusic 本地候选验收记录

日期：2026-09-28。上游源码固定在 [Bòcan `fdce127`](player/UPSTREAM.md)；本记录对应当前工作区的 WMusic 本地开发候选，不代表可公开分发的版本。

## 已验证

- **构建**：在本机 Apple Silicon、Xcode 27 上执行 `./script/build_and_run.sh --verify`，完整 Xcode Debug 构建成功；产物为 `player/DerivedData/Build/Products/Debug/WMusic.app`，已实际启动。
- **身份与隔离**：产物的应用名为 WMusic，bundle ID 为 `com.willhsu.wmusic.local`，采用 ad-hoc 签名和沙盒。实际运行时数据库与锁位于 `~/Library/Containers/com.willhsu.wmusic.local/Data/Library/Application Support/WMusic/`；未观察到对 Bòcan 或 foobar2000 数据目录的访问。上游 Sparkle 更新源未进入产物。
- **真实界面**：查看了歌曲列表、侧栏、播放控制区及原创 W 图标的构建产物。首次启动是空曲库；导入独立合成音频目录后，列表正确显示两首歌、艺术家、专辑和 MP3／FLAC 编码。
- **本地播放**：从列表双击两首 12 秒合成音频，播放按钮切为暂停，进度条前进；从 MP3 切换到 FLAC 后信息区显示 FLAC、44.1 kHz、16-bit。此项验证的是 UI 与播放器状态，未测量实际声学输出。
- **开发重启**：再次执行构建脚本后，新进程启动且曲库仍有两首测试曲目；正常退出流程没有出现误报的异常恢复横幅。
- **定点测试**：UI 模块的对比度与本地化测试共 57 项通过；UserAgent、DatabaseLocation、OPMLWriter 定点测试共 11 项通过。

测试音频由 FFmpeg 的 sine 源生成，位于忽略版本控制的 `.build-logs/smoke-fixtures/`。没有导入私人音乐目录，也没有替换 `/Applications` 内的播放器。

## 尚未验收与发布前工作

- 上游 `make test-ui` 的完整 UI 测试存在 33 项截图基线等失败。Nocturne 改色会改变截图；尚未逐张复核或重录，因此不能把完整截图套件视为通过。
- 尚未用真实输出设备逐项听测无缝播放、均衡器、格式切换，也未连接 Subsonic、播客服务、Last.fm 或 Bòcan 手机客户端。
- 本机 Homebrew FFmpeg 构建标记为 GPL-3.0-or-later，且部分动态库针对 macOS 27 构建。公开分发前需按目标系统重新构建和审查所有捆绑库许可、签名、品牌与升级路径；本候选仅用于本地开发。

开发入口和依赖见 [README](README.md)，选型依据见 [PLAYER_SELECTION](PLAYER_SELECTION.md)。
