# WMusic macOS 开源播放器选型

核查日期：2026-09-28。目标是在本机持续开发一个视觉清晰、曲库功能完整的 macOS 本地播放器，并保留 WMusic Nocturne 的深蓝视觉方向。这里的“具备”指公开源码和项目文档可核查；运行表现仍由本机构建与界面验收单独证明。

| 候选 | 视觉与 macOS 适配 | 本地曲库与播放 | 本地开发与许可 | 结论 |
| --- | --- | --- | --- | --- |
| [Bòcan](https://github.com/bocan/bocan-music) | SwiftUI 原生三栏、专辑封面网格、迷你播放器；可在语义色层加入 Nocturne | 文件夹扫描、搜索、标签、歌单、歌词、无缝播放、EQ、ReplayGain、CUE；还含 Subsonic、播客与电台 | Apache-2.0；Xcode 26+、Apple Silicon；需 FFmpeg、Chromaprint、TagLib 等构建依赖 | **选为整体底座**：功能和原生交互最均衡，源码分层和测试较完整 |
| [Airmedy](https://github.com/misa198/airmedy) | 封面与沉浸式歌词表现突出，Vue/WebView | 曲库、歌词、交叉淡入淡出、EQ、智能歌单、统计等 | GPL-3.0；Go/Wails 3；macOS 首次构建还需编译 SFBAudioEngine、FFmpeg、aubio、FFTW | 借鉴封面/歌词呈现，不整体引入 |
| [hihat](https://github.com/johnnyshankman/hihat) | Electron 列表界面紧凑，接近旧播放器布局 | 本地扫描、标签、歌单、无缝播放、系统媒体键；无在线串流 | MIT；Node 24+，上手直接 | 本地开发容易，但功能与视觉扩展工作量更大 |
| [EKO](https://github.com/reactivepixels/eko) | Rust/Tauri；界面有明确保留的视觉识别 | 高保真音频与 Navidrome 较强；公开版本地歌单尚未实现 | MIT 代码，但 NOTICE 对名称/视觉另有限制；本机缺 Rust | 参考音频管线，不作为可直接复用的视觉和功能底座 |
| [MadTunes](https://github.com/ShikiSuen/MadTunes) | SwiftUI 原生，经典 iTunes 11 专辑网格 | 本地播放、搜索、队列和歌单；主播放链强调纯净输出，不内置 DSP | AGPL-3.0；Xcode 26 编译 | 可参考专辑网格，功能广度与许可不如本次选用底座合适 |
| [Petrichor](https://github.com/kushalpandya/Petrichor) | SwiftUI 界面成熟 | 功能丰富 | 仓库注明核心 CrescendoKit 为闭源二进制 | 不作为完整开源底座 |

## 整合范围

1. 以 Bòcan 源码建立独立的 `player/` 开发候选，保留其许可证与第三方声明，使用独立的 WMusic 应用标识、数据目录和密钥服务。
2. 将现有 Nocturne 的深蓝底与紫蓝强调色加入 SwiftUI 语义主题；默认维持易读的常规密度，紧凑密度仍可选择。
3. 保留 Bòcan 的扫描、曲库、歌单、歌词和音频模块，不移植 foobar2000 的闭源实现、SQLite 数据库或注入式窗口补丁。
4. 关闭原上游的自动更新通道；如需把应用包交给朋友，先核对附带库许可、目标系统兼容性与签名方式。

## 验收边界

- **源码**：核查功能入口、许可证、品牌和数据隔离。
- **构建**：Xcode 编译通过，记录确切源码版本和依赖；单项 Swift Package 检查不能替代应用构建。
- **运行**：只启动工作区构建的候选，确认进程、独立数据路径和窗口；测试曲目只用合成或公开测试音频。
- **听感/设备**：无缝、EQ、输出设备和各格式需逐项实际播放才能确认；源码声明不等于本机听感验收。

## 参考资料

- [Bòcan README 与功能](https://github.com/bocan/bocan-music#readme)、[开发要求](https://github.com/bocan/bocan-music/blob/main/DEVELOPMENT.md)、[许可证](https://github.com/bocan/bocan-music/blob/main/LICENSE)
- [Airmedy 功能与构建说明](https://github.com/misa198/airmedy#readme)、[官方截图](https://airmedy.pages.dev/#screenshots)
- [hihat README 与许可证](https://github.com/johnnyshankman/hihat#readme)
- [EKO README](https://github.com/reactivepixels/eko#readme)、[NOTICE](https://github.com/reactivepixels/eko/blob/main/NOTICE)
- [MadTunes README 与许可说明](https://github.com/ShikiSuen/MadTunes#readme)
- [Petrichor 许可说明](https://github.com/kushalpandya/Petrichor#-license)
