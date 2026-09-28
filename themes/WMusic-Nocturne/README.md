# WMusic · Nocturne Compact

Foobar2000 macOS 的紧凑播放器布局，借鉴 Georgia-ReBORN 的 Compact / Playlist Mode 信息层级，优先保障连续播放时的高频操作：

- 顶部：当前封面
- 封面下方：歌曲信息、播放进度、播放控制、音量与输出信息
- 左下：播放列表选择器，可在不同列表之间切换
- 右下：SimPlaylist 分组歌曲列表，占据绝大多数空间
- 结构：去掉曲库侧栏与元数据工作区，减少视觉分割和鼠标移动；顶部可在窄窗口中继续收缩

Foobar2000 v2.25.10 的 macOS 原生界面没有独立的配色主题 API；当前使用 libfootheme 提供深蓝 Nocturne 配色，布局仍由可读的 UI-Layout 文件控制。

当前组件 + 换肤版预览保存在项目根目录的 `theme-preview.png`，原生版预览保留为 `theme-preview-native.png`。
移除波形前的布局与预览保存在 `backups/20260817-before-remove-waveform/`；本次上下排列与窗口调整前的无波形版、窗口偏好和 App 配置备份在 `backups/20260817-before-stacked-cover/`；更早的原生布局备份仍保存在 `backups/20260817-pre-theme/`、`backups/20260817-before-compact/` 和 `backups/20260817-georgia-compact/`。

## 原生布局变体

`variants/` 下保留三套不依赖第三方组件的布局：`01-georgia-compact`（封面 + 控制 + 播放列表选择器 + 歌曲列表）、`02-mini-player`（极简播放条）、`03-library-workbench`（曲库工作台）。

组件版和换肤版使用独立的布局文件与备份，不覆盖这些原生变体。

当前实际运行的是 `variants/06-stacked-cover-components-no-wave.txt`：封面位于播放控制和进度条上方，保留 Playlist Organizer 和 SimPlaylist，已从实际布局移除 Waveform Seekbar。`variants/05-compact-components-no-wave.txt` 保留为上一版无波形排版，`variants/04-waveform-components.txt` 保留为含波形回滚版；Waveform Seekbar 组件仍安装但未被布局引用。

窗口由 `window-resize-hook.m` 提供 macOS 运行时补丁：主窗口加入 Resizable 样式，清除内容纵横比限制，放开内容视图的最小/最大尺寸与 1pt 调整步长，并代理主窗口的 `windowWillResize` 回调。针对 Foobar 仍会把高度回写为固定值、把底部拖拽识别成整窗移动的问题，补丁在主窗口底边中央提供纵向拖拽把手，在右下角提供独立的二维 resize 区域，并关闭内容背景移动、用 frame guard 保持用户选定的高度。二维 resize 固定视觉左上角，只改变当前窗口宽高。布局中的封面区与播放列表选择器使用高 holding priority，歌曲列表使用低 holding priority，因此窗口增量只交给底部歌曲列表。嵌入的 `libwmusic-window-resize.dylib` 与当前 `libfootheme.dylib` 一起加载；完整原始 App 回滚副本位于 `backups/20260817-before-1-3/foobar2000.app/`。
