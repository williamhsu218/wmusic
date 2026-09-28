# WMusic 布局变体

`01`—`03` 只使用 foobar2000 macOS 原生布局元素；`04`—`06` 使用已安装的 macOS 组件。

- `01-georgia-compact.txt`：原生封面 + 播放控制 + 播放列表选择器 + 歌曲列表。
- `02-mini-player.txt`：更窄的 MiniPlayer，适合只保留封面、进度和歌曲列表。
- `03-library-workbench.txt`：曲库 / 筛选 / 正在播放 / 播放列表工作台。
- `04-waveform-components.txt`：组件版回滚方案，使用 Waveform Seekbar、Playlist Organizer 和 SimPlaylist。
- `05-compact-components-no-wave.txt`：上一版无波形方案，封面与播放控制左右排列。
- `05-cover-focus-components.txt`：实验性封面焦点方案，曾将播放列表选择器放到顶部，当前不作为默认布局。
- `06-stacked-cover-components-no-wave.txt`：当前方案，封面在上，播放进度与播放控制在下，实际布局不显示波形。

Waveform Seekbar 组件仍保留在 `user-components` 中，便于回滚，但当前 UI-Layout 不再引用它。

libfootheme 配置模板位于主题根目录的 `libfootheme-theme.conf`；当前实际配置位于 `~/.config/foo/theme.conf`。窗口可调整补丁源文件为主题项目根目录的 `window-resize-hook.m`，其中包含底边可见拖拽把手、右下角二维 resize 区域、窗口事件兜底、内容背景移动隔离、纵向拖拽 fallback 和高度 frame guard。当前 `06-stacked-cover-components-no-wave.txt` 还将封面区和播放列表选择器设为高保持优先级，让歌曲列表吸收窗口宽高变化。

应用某个变体前，先复制一份当前 `/Users/willhsu/Library/foobar2000-v2/UI-Layout.txt`，再覆盖该文件并重启 foobar2000。
