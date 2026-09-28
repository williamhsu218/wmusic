# WMusic 本地候选验收记录

日期：2026-09-28。上游源码固定在 [Bòcan `fdce127`](player/UPSTREAM.md)；本记录对应仅供本机使用或私下给朋友使用的 WMusic 开发候选。

## 已验证

- **构建**：在本机 Apple Silicon、Xcode 27 上执行 `./script/build_and_run.sh --verify`，完整 Xcode Debug 构建成功；产物为 `player/DerivedData/Build/Products/Debug/WMusic.app`，已实际启动。
- **身份与隔离**：产物的应用名为 WMusic，bundle ID 为 `com.willhsu.wmusic.local`，采用 ad-hoc 签名和沙盒。实际运行时数据库与锁位于 `~/Library/Containers/com.willhsu.wmusic.local/Data/Library/Application Support/WMusic/`；未观察到对 Bòcan 或 foobar2000 数据目录的访问。上游 Sparkle 更新源未进入产物。
- **真实界面**：查看了歌曲列表、侧栏、播放控制区及原创 W 图标的构建产物。首次启动是空曲库；导入独立合成音频目录后，列表正确显示两首歌、艺术家、专辑和 MP3／FLAC 编码。
- **本地播放**：从列表双击两首 12 秒合成音频，播放按钮切为暂停，进度条前进；从 MP3 切换到 FLAC 后信息区显示 FLAC、44.1 kHz、16-bit。此项验证的是 UI 与播放器状态，未测量实际声学输出。
- **APE 解码与标签**：从 [FFmpeg 官方样本目录](https://samples.ffmpeg.org/monkeyaudio/)下载 `sh3.ape`（SHA-256 `9b8e89b81a87001648d58dc9ef440a5b9b8c214a4df07bd22776da1ff6e32004`），存放在忽略版本控制的 `.build-logs/ape-eval/`。本机 `ffprobe` 读出 Monkey's Audio、44.1 kHz、16-bit、双声道；临时定点测试分别验证 TagLib 能读取其属性，以及 WMusic 的 `DecoderFactory` 选用 FFmpeg 并成功解出 PCM 帧。测试代码在验证后移除，样本未提交。
- **开发重启**：再次执行构建脚本后，新进程启动且曲库仍有两首测试曲目；正常退出流程没有出现误报的异常恢复横幅。
- **定点测试**：UI 模块的对比度与本地化测试共 57 项通过；UserAgent、DatabaseLocation、OPMLWriter 定点测试共 11 项通过。

测试音频由 FFmpeg 的 sine 源生成，位于忽略版本控制的 `.build-logs/smoke-fixtures/`。没有导入私人音乐目录，也没有替换 `/Applications` 内的播放器。

## 尚未验收与私下交付前工作

- 上游 `make test-ui` 的完整 UI 测试存在 33 项截图基线等失败。Nocturne 改色会改变截图；尚未逐张复核或重录，因此不能把完整截图套件视为通过。
- APE 已做文件解码与标签测试，尚未从应用界面完整导入并听测；也未用真实输出设备逐项听测无缝播放、均衡器、格式切换，或连接 Subsonic、播客服务、Last.fm 与 Bòcan 手机客户端。
- 当前 Debug 产物的 `WMusic.debug.dylib` 仍引用 `/opt/homebrew/opt/` 下的 FFmpeg 与 TagLib；即使应用包中有部分 FFmpeg 资源，也不能把这个 `.app` 直接复制给没有相同依赖的朋友使用。本机 Homebrew FFmpeg 构建标记为 GPL-3.0-or-later，且部分动态库针对 macOS 27 构建。私下交付前需完成依赖重定位、目标系统兼容性与附带库声明核查；当前构建仅在本机验收。

开发入口和依赖见 [README](README.md)，选型依据见 [PLAYER_SELECTION](PLAYER_SELECTION.md)。
