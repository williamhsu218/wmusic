# WMusic

WMusic 是面向 macOS 本地曲库的播放器开发工作区，仅计划本机使用或私下给朋友使用。`player/` 是从开源 [Bòcan](https://github.com/bocan/bocan-music) 引入的独立 SwiftUI 播放器候选；`themes/WMusic-Nocturne/` 与现有 foobar2000 配置保留作视觉参考和回滚资料。两个播放器的数据与安装目录彼此独立。

## 下载

源码仓库：[williamhsu218/wmusic](https://github.com/williamhsu218/wmusic)。安装包见 [GitHub Releases](https://github.com/williamhsu218/wmusic/releases/latest)，当前版本为 **1.0.1 (2)**。

下载 `WMusic-1.0.1-macos-arm64.zip`，解压后将 `WMusic.app` 放入 `/Applications`。更新前先正常退出旧应用，并保留旧应用与曲库备份；本工作区的更新继续使用下文的安装脚本维护唯一回滚。安装包不包含音乐文件或用户数据库，运行时无需安装 Homebrew。

此预编译包要求 **Apple Silicon 和 macOS 27+**：主程序的构建目标为 macOS 15，但本次附带音频库的最低系统版本为 macOS 27。应用采用 ad-hoc 签名，未经过 Apple 公证；其他 Mac 的首次打开与实际播放仍需对应机器验收。附件包含 SHA-256 校验值与构建信息，版本内容和验证范围见 [1.0.1 发布说明](docs/releases/v1.0.1.md)。

## 本地开发

开发机需要 Apple Silicon、macOS 15+、Xcode 26+、Homebrew，以及 FFmpeg、Chromaprint、TagLib、XcodeGen。依赖与首次生成步骤见 [player/DEVELOPMENT.md](player/DEVELOPMENT.md)。`player/Secrets.xcconfig` 可从同目录模板复制，空值即可编译本地播放；不要填入或提交个人 API 凭据。

```sh
./script/build_and_run.sh --verify
```

该命令构建工作区内的 WMusic 候选并启动构建产物，不安装到 `/Applications`。导入曲库时请先使用独立的测试音频目录；不要直接指向 foobar2000 的配置库或个人音乐目录做开发验收。

## 本机应用

```sh
./script/build_local_app.sh
```

该命令构建 Release 候选，将 TagLib、FFmpeg、`fpcalc` 及其依赖装入应用包，保留沙盒权限并使用 ad-hoc 签名。候选固定为 `dist/WMusic.app`，重新构建会替换该候选，不再累积 `dist/previous/`。构建环境需要上节列出的开发依赖，运行成品无需这些 Homebrew 音频库。

正式版固定安装到 `/Applications/WMusic.app`。候选验收通过后，先正常退出 WMusic，再安装：

```sh
./script/install_local_app.sh
open /Applications/WMusic.app
```

安装脚本需要 Python 3 和当前用户对 `/Applications` 的写入权限；该位置的正式 WMusic 仍在运行时会拒绝安装，其他路径的隔离测试包不受影响。脚本核对候选的固定身份 `com.willhsu.wmusic.local`、数字版本、ad-hoc 签名与沙盒权限，并拒绝带调试权限的包。暂存应用后逐一比对所有文件的 SHA-256、目录、符号链接与可执行权限，再替换正式版并读回检查。候选与正式版完全一致时直接返回，保留原有回滚。成功安装后刷新正式应用的系统登记；应用图标变更时重启 Dock 以刷新图标缓存。脚本不会启动或强制结束 WMusic。

每次成功安装只保留一个回滚位置：`.build-logs/install-backups/current-rollback/`。其中 `WMusic.app` 是安装前的正式版，`library.sqlite` 是安装前曲库的 SQLite 在线快照，JSON 文件记录版本与完整文件校验清单。快照包含已提交的 WAL 数据并使用独立的 DELETE 日志模式，真实曲库不会被替换；首次安装没有上一个应用或曲库时会在记录中明确标注。新正式版与回滚快照全部校验通过后才淘汰旧回滚；失败时恢复旧应用，无法自动恢复时保留暂存路径并报错，处理遗留事务前不要再次安装。

需要回滚时，先正常退出 WMusic，核对回滚包和 `previous-app-files.json`，再用其中的 `WMusic.app` 替换 `/Applications/WMusic.app`。曲库快照用于另行恢复，不能在应用运行时覆盖数据库；恢复前需同时处理现存 `library.sqlite-wal` 与 `library.sqlite-shm`，避免旧 WAL 与快照混用。不要把候选、旧安装目录或其他历史备份当作正式启动入口。

已导入的单个音频文件若要修改标签，请先在应用的 Settings → Library 中用 Add Folder 选取它们所在的文件夹，再重新执行编辑。macOS 会为该文件夹授予写入权限；旧版逐文件导入时保存的权限不会自动升级。添加文件夹不会复制音频文件。主窗口左下角封面现在打开覆盖整个窗口的播放页，显示大封面和播放控制，右侧可切换实时队列与大字歌词。歌词支持逐句高亮、自动跟随和点击跳转；“播放当前曲后停止”仍可从 Playback 菜单使用。

目前验收的是本机 Apple Silicon 环境；其他 Mac 的系统兼容性和首次打开流程仍需在对应机器上验证。ad-hoc 包没有 Apple 公证。

## NAS 曲库

在 Settings → Sources 中选择 **NAS Folders**，即可接入群晖等 NAS 的 SMB 音乐共享：

1. 输入群晖的内网 IP、Tailscale IP 或设备名，例如 `nas.example`、`smb://nas.example`、`nas.example` 或 MagicDNS 名称。共享目录可选：既可直接填服务器地址、连接后选择共享，也可填 `smb://nas.example/music`。点击 **Connect in Finder…**，在 macOS 窗口中选择共享并登录。Tailscale 地址需要当前 Mac 与群晖之间的 Tailscale 网络已连通。WMusic 不保存 NAS 账户密码；是否记住登录由 macOS 钥匙串处理。
2. 完成连接后回到 Sources，点击 **Choose NAS Folder…**，选取已挂载共享中的音乐文件夹，授予 WMusic 持续访问权限。已在 Finder 连接的共享可以直接选择文件夹。
3. 导入的 NAS 文件夹会出现在侧栏 Sources 中，点击即可浏览该文件夹的歌曲；歌曲也会并入现有曲库。WMusic 直接读取共享文件，不复制音频到 Mac。

NAS 断开或目录读取失败时，扫描保留已导入歌曲，不将临时断线当作文件删除。Sources 显示上次扫描的可用状态；使用 **Reconnect…** 重新连接后点击 **Rescan**。服务器上的新增或修改文件可能需要手动扫描才能更新。若 macOS 把同一个共享挂载到不同路径，应恢复原挂载路径后再扫描；本轮不自动迁移来源、队列或历史。

Sources 的 **Music Servers** 仍支持 Subsonic/OpenSubsonic 兼容音乐服务，例如 NAS 上的 Navidrome；填写服务的 HTTP(S) 地址和账户信息即可浏览、串流其曲库。群晖 DSM 网页地址和 `smb://` 共享地址分别使用各自入口。本轮新增连接流程针对 SMB；其他已挂载的文件共享仍可通过 Settings → Library → Add Folder 添加。

目前通过源码、隔离数据库与候选应用验证，尚未连接用户的群晖实机验收。

## 目录

- `player/`：播放器源码与其原始 Apache-2.0 许可、第三方声明；[来源与本地改动](player/UPSTREAM.md)。
- `script/build_local_app.sh`：可重复构建独立、ad-hoc 签名的本机应用。
- `script/install_local_app.sh`：固定安装正式版并维护唯一应用与曲库回滚快照。
- `themes/WMusic-Nocturne/`：现有 foobar2000 深蓝主题、布局和组件清单。
- `window-resize-hook.m`、`build/`、`backups/`：旧 foobar2000 定制与回滚材料，不属于新播放器构建。
- [选型与验收口径](PLAYER_SELECTION.md)：候选项目比较与取舍。
- [本地候选验收记录](VALIDATION.md)：构建、运行、合成音频播放和仍待确认的能力。

`DEVELOPMENT_PLAN.md` 是 2025 年从零开发 Rust/Tauri 跨平台播放器的历史提案；当前 macOS 实施方案以本文和 `PLAYER_SELECTION.md` 为准。
