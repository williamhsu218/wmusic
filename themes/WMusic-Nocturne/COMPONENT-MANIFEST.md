# WMusic Nocturne 组件清单

本机当前使用 Foobar2000 macOS 2.25.10，组件均为 arm64/x86_64 universal 包：

| 组件 | 版本 | 来源 |
|---|---:|---|
| SimPlaylist | 1.5.1 | `JendaT/fb2k-components-mac-suite` |
| Waveform Seekbar | 1.2.0 | `JendaT/fb2k-components-mac-suite` |
| Playlist Organizer | 1.3.0 | `JendaT/fb2k-components-mac-suite` |

当前布局入口：`variants/06-stacked-cover-components-no-wave.txt`

上一版无波形布局：`variants/05-compact-components-no-wave.txt`

回滚布局：`variants/04-waveform-components.txt`（含波形）

Waveform Seekbar 仍安装在 `user-components`，但当前布局不引用，因此不会出现在界面中。

换肤入口：`libfootheme-theme.conf`

窗口调整入口：`window-resize-hook.m` → `libwmusic-window-resize.dylib`（解除纵向 `windowWillResize` 和内容比例约束，并提供底边可见拖拽把手、纵向拖拽及高度回写处理）

`libfootheme` 会修改 Foobar App 的签名和启动环境，因此完整原始 App 保存在 `backups/20260817-before-1-3/foobar2000.app/`。
