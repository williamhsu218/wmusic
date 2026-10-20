# WMusic 本地候选验收记录

最新正式安装：**2026-10-20，1.0.8 (12)**。依据用户追加优化方案完成六项交互修整，见 [本轮记录](player/docs/audits/2026-10-20-interaction-refinement.md) 与 [1.0.8 发布说明](docs/releases/v1.0.8.md)。最终 UI 回归 **1,187 项 / 211 个套件**、受影响快照 **10 项 / 5 个套件**通过；20 个改动 Swift 文件格式检查及 AppKit 引入审计通过。

最终候选与隔离 QA 包的 51 个代码/数据区段一致。原生确认首轮滚动收起长专辑、顶部展开、短列表稳定、Command 封面和标题多选、键盘打开、歌词定位、清空确认、侧栏宽度拖拽和辅助调整、展开返回及沉浸退出；最终包另复验合成音频暂停、重启恢复 0:11、底栏续播。未将截图当作逐帧性能证明，未覆盖真实 NAS 断线重连或其他 Mac。

已通过项目脚本替换 `/Applications/WMusic.app`，118 个文件与候选一致，严格签名及沙盒通过，“关于”确认 1.0.8 (12)。正常退出旧版保存当前曲目和 53.16 秒位置，新版恢复同一状态；启动日志确认跳过扫描。安装前与首次启动比较全部 49 张表，48 张完全一致，settings 仅本地备份时间发生语义变化；队列与 UI 状态语义一致。首次启动快照保留 2,767 首曲目、7 个播放列表、1,293 项队列及 491 条历史，数据库 `quick_check=ok`。偏好仅 NSTableView 排序自动保存项更新，其余保持；退出后偏好落盘有延迟，使用安装完成、启动前快照核对最终保存的续播值。随后正式应用已继续播放，验收未再中断或主动点击真实媒体播放。唯一回滚为 **1.0.7 (11)** 与精确的安装前数据库。本机证据保留在 `.build-logs/interaction-ux-20261020/`。

## 1.0.7 历史验收

上一正式安装：**2026-10-20，1.0.7 (11)**。启动扫描方案 A 与六项 UI/UX 优化见 [本轮审计](player/docs/audits/2026-10-20-startup-scan-ui-ux.md)。UI 回归 1,138 项、最终专项 48 项及 10 项受影响快照通过。发布版本重新构建并另做隔离合成音频播放、定位、暂停恢复及底栏续播复查；其 QA 包与本次候选的 51 个代码/数据区段一致。较早优化构建与新发布构建未达到跨构建按位一致，未复用这一判据冒充新包验收。

已通过项目安装脚本替换 `/Applications/WMusic.app`，118 个文件与候选一致，严格签名和沙盒通过。“关于”确认版本，正常退出重启恢复原曲目、2:41 和暂停状态；两次正式启动均记录跳过启动扫描。安装后比较全部 49 张表，48 张完全一致，settings 仅备份时间发生语义变化；队列和界面状态语义一致。保留真实曲库 2,767 首、7 个播放列表、1,293 项队列和 457 条历史。窗口框架自动保存值更新，其他偏好保持；唯一回滚为上一正式版 1.0.6 (10) 与精确的安装前数据库。原有不可解析来源书签告警仍有记录，未扰动真实 NAS 或播放真实媒体。源码、历史与发布附件另经隐私检查；发布构建、安装、远端读回证据保留在 `.build-logs/release-1.0.7-20261020/`。下载要求及验证边界见 [1.0.7 发布说明](docs/releases/v1.0.7.md)。

此前正式安装（1.0.6）：**2026-10-18** 已将下述候选通过项目安装脚本安装到 `/Applications/WMusic.app`。118 个文件与已验收候选完全一致，签名和沙盒通过；正式界面、关于窗口、队列显示、正常退出与重启恢复均已验收，应用当前暂停。真实曲库 2,767 首、7 个播放列表、1,403 项队列和 393 条历史保留；唯一回滚已轮换为安装前正式版及曲库快照。部分已有来源书签和 CUE 引用不可解析的边界，以及数据库正常元数据变化，见 [正式版安装验收](player/docs/audits/2026-10-18-formal-install-acceptance.md)。

此前候选复查：见 [2026-10-18 异步与异常路径审计](player/docs/audits/2026-10-18-async-exception-review.md)。修复超时、取消竞争、恢复进度、共享缓存、服务启停和子进程清理等 8 类问题，保留 Opus 的退出期限、vacuum 和图标优化；合入其 XcodeGen 稳定标识修复。相关自动验证共 **1,090 项通过**，最终 Release 与隔离真实界面通过重启、首次播放前拖动、直接续播及退出保存验收。候选主程序 SHA-256 为 `3ff8380dcbb41e5e5ba8a1ee5a72bda98fc766aba84d1e93b9cddb9bae6f4626`；候选审计阶段未安装，随后依用户授权完成上述正式安装，尚未发布。严格 SwiftLint 仍有 36 项既有告警，另保留一次未复现的渲染测试失败记录，详见审计报告。

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

## 本机 Release 应用（2026-09-29）

- 执行 `./script/build_local_app.sh` 后，得到约 150 MB 的 `dist/WMusic.app`。它是 arm64 Release 构建，bundle ID 仍为 `com.willhsu.wmusic.local`，最低系统版本设为 macOS 15.0。
- 成品的主程序不再引用 `WMusic.debug.dylib`。包内有 16 个 `Contents/Frameworks` 动态库，以及 `Contents/Resources` 中的 `fpcalc` 和音频分析库；每个 Mach-O 的依赖与运行路径都已检查，没有指向 Homebrew 或本机开发目录的绝对路径。
- `codesign --verify --deep --strict` 和逐个二进制签名检查通过。最终签名为 ad-hoc、无 Team ID；`codesign` 读回沙盒、用户选取文件读写、书签和网络权限，且不含开发调试用的 `get-task-allow`。原始 Apache-2.0 `LICENSE` 与 `NOTICES.md` 均已装入成品。
- 先从 `dist/WMusic.app` 启动，再复制到 `~/Applications/WMusic.app` 并从安装位置启动。安装版进程持续运行；`lsof` 读回的 TagLib、FFmpeg 等已加载库均来自该安装包，未见 Homebrew 路径。安装版使用原有 `com.willhsu.wmusic.local` 沙盒数据库与单实例锁；安装版主程序与 `dist` 成品 SHA-256 一致。
- 解锁后目视复核 `~/Applications/WMusic.app` 的 Songs 窗口：深色布局、侧栏、歌曲列表和底部播放区均正常显示，原有测试曲库中可见 APE、MP3、FLAC 三首曲目。APE 行的曲名和标签与 SHA-256 为 `9b8e89b81a87001648d58dc9ef440a5b9b8c214a4df07bd22776da1ff6e32004` 的 `sh3.ape` 样本一致；双击后播放栏显示 APE、754 kbps、44.1 kHz、16-bit、Stereo，按钮变为暂停，进度从 0:00 前进到 0:05。随后 FLAC 测试曲在安装版播放栏显示 44.1 kHz、16-bit，进度前进，播放结束后按钮恢复为播放。验收证明安装版的界面与播放器状态；未测量扬声器声学输出。

## 五项使用问题修复与安装版验收（2026-09-29）

- 歌曲信息编辑面板固定为 720 × 600 点。安装版逐页查看 Details、Lyrics、File Info、Sorting、Advanced，截屏尺寸均为 1440 × 1200 像素；Artwork 与 Deep Dive 也已目视确认。首次候选版在快速切回 Details 并读取完整辅助功能树时触发 SwiftUI 可访问性递归崩溃；重建标签页滚动内容并清理旧焦点后，安装版重复相同切换序列未再崩溃。
- 设置页将备份和诊断的耗时读取移出页面切换主路径，并将 1,287 个曲库来源收进可搜索的 Manage Sources 列表。安装版实测切到 Library 的点击动作约 30 毫秒，随后完整辅助功能读取约 557 毫秒；该数值包含自动化读取，不等同于纯渲染耗时。列表搜索测试来源成功。
- 旧版只读文件书签导致批量修改 13 个真实 FLAC 文件时报文件夹不可写。新导入的文件夹使用读写书签，编辑事务选取最具体的授权根目录。安装版仅对独立合成 FLAC 进行端到端验收：通过 Add Folder 授权测试目录，修改 Album 后，`ffprobe` 读回 `Synthetic After`，曲库数据库也读回相同专辑名，原有标题与艺术家保留，数据库 `quick_check` 为 `ok`。未修改或重试那 13 个真实文件；对已逐文件导入的曲目，须由用户在 Settings → Library → Add Folder 选取其所在文件夹后再编辑。
- 底部传输控制栏红框图标是“播放当前曲后停止”；它已从主播放栏、迷你播放器及沉浸视图移除，Playback 菜单中的功能仍可使用。安装版辅助功能树中已无该按钮。
- 点击左下角封面打开大封面、歌曲信息、播放控制和实时 Up Next 队列。安装版在真实专辑播放期间目视检查该面板及 100 首待播曲目，点击没有跳转到专辑页。最终安装版还从此队列的右键菜单打开了 Get Info，确认先关闭大封面再呈现歌曲编辑器；未保存对真实曲目的更改。电台状态下的上一台／下一台已改为调用电台导航路径，源码编译通过，但本轮未连接真实电台流做运行验收。
- 完整构建脚本重新产出并安装 ad-hoc 签名 Release 包。`dist/WMusic.app` 与 `~/Applications/WMusic.app` 的主程序 SHA-256 相同，安装版签名与嵌入依赖验证通过，进程从安装位置运行。替换前已保存应用及曲库数据库备份于忽略版本控制的 `.build-logs/install-backups/2026-09-29-five-fixes/`。

## 全窗口 Now Playing（2026-09-29）

- 点击底部封面后，Now Playing 作为主窗口内的覆盖视图展开，从窗口顶端到底部遮住原歌曲表、侧栏和底部播放栏；不再出现固定尺寸的 sheet。原浏览位置保持挂载，关闭后可返回。宽窗口采用放大的封面／信息／控制与队列双栏；约 900 × 600 点的小窗口改为上方封面与控制、下方队列；最大化时限制内容的最大宽高，避免队列过度拉伸。单曲队列的空状态置于队列中央。
- 本机安装版以合成 FLAC `Tone 660` 实际打开并目视检查常规、小窗口和最大化布局：歌曲信息、进度、音量、队列和关闭按钮都可见，底层曲库没有穿透到覆盖层。Esc 能关闭；⌘F 会先收起播放页，再选中原搜索框。队列右键的 Get Info 能打开编辑器，Go to Album 能打开对应专辑；未保存真实曲目的标签编辑。
- `swift build --package-path player/Modules/UI` 通过，相关输入监控定点测试 20 项通过；Release 构建脚本再次完成依赖嵌入、ad-hoc 签名和逐个 Mach-O 检查。安装版 `codesign --verify --deep --strict` 通过，主程序与 `dist` 的 SHA-256 同为 `61c8ea8df604c26c9a0287fb2d5a251941d42a75637a49bb18b2907a077046ac`。安装前保存了旧应用与 SQLite 在线备份在 `.build-logs/install-backups/2026-09-29-five-fixes/`；备份数据库 `quick_check` 为 `ok`。

## Now Playing 与切歌动画优化（2026-09-29）

- 全窗口入场移除了整页缩放和根视图动画，只对覆盖层做 0.16 秒透明度过渡；队列在入场结束后装载，展开视图不再订阅整个曲库模型。底栏切歌仅在固定宽度的封面／信息区域做 12 点、0.18 秒短位移动画；缩小了 900 点宽窗口下的控制区留白，修复了两端控件裁切。元数据解析任务会在切歌时取消旧任务，并在歌手、专辑和封面都准备好后一次提交。
- UI 模块增量构建与 `NowPlayingViewModelTests` 24 项通过；Release 构建、依赖嵌入、ad-hoc 签名和逐个 Mach-O 检查通过。安装版 `codesign --verify --deep --strict` 通过，主程序与 `dist` 的 SHA-256 同为 `30163571491ac3f4090352b6439b266b8762eea6594207af5b85e7a9375d6a04`。
- 安装版用合成 `Tone 440`/`Tone 660` 连续三次执行上一首→下一首，底栏每次都显示正确曲名和歌手；全窗口播放页连续三次展开／关闭后，队列和原浏览界面都能恢复。900 点宽窗口与放大窗口的实际截图检查通过，窄窗口底栏的封面和最右侧 DSP 按钮均完整显示；播放页覆盖整个窄窗口。测试后暂停播放并将窗口恢复为放大尺寸。仅使用合成歌曲，未编辑真实音频标签。
- 替换应用前的版本及数据库在线备份位于 `.build-logs/install-backups/2026-09-29-animation-fixes/`，备份库 `quick_check` 为 `ok`。本轮没有取得可用的帧时间追踪，因此不把自动化界面响应或目视检查表述为定量 FPS 保证。

## 窗口缩放崩溃修复（2026-09-29）

- 用户提供的崩溃报告位于 `~/Library/Logs/DiagnosticReports/WMusic-2026-09-29-111252.ips`。崩溃版本 UUID 与当时安装版一致；主线程在窗口实时缩放中拆除 SwiftUI `List` 的底层 `NSOutlineView` 时触发 `ViewListTree.visitItem` 断言。堆栈不能唯一指明具体列表，最可疑路径是全窗口播放页跨 920 点宽／620 点高时在两套布局间替换队列。
- 全窗口播放页现在通过 `AnyLayout` 调整横竖排列，队列保持一个稳定的子视图位置；展开队列加载或变空时，`List` 也持续挂载，状态提示改为覆盖层。普通队列的空态和行操作保留原行为。
- UI 模块构建、`QueueReorderGripTests` 2 项、`git diff --check` 通过。`./script/build_local_app.sh` 完成 Release 构建、依赖嵌入、ad-hoc 签名与逐个 Mach-O 检查；`dist/WMusic.app` 的 bundle ID 为 `com.willhsu.wmusic.local`，沙盒权限保留。替换前旧应用和数据库已备份至 `.build-logs/install-backups/2026-09-29-resize-crash/`，备份库 `quick_check` 为 `ok`。
- 当时安装版的窗口实时缩放、播放页展开／收起及新增崩溃报告检查仍待解锁；后续安装版的跨布局阈值与展开／收起检查见下文。连续拖动窗框仍未取得可靠的自动化验收证据。

## 封面、榜单和声明修复（2026-09-29）

- 切歌或列表点播原先会用不带动画的 diffable 快照重新配置全表，让可见封面短暂清空。现在只刷新变化的单元格；播放高亮只刷新文字列。封面单元格对相同路径保留现有图片与加载任务，并为可见缩略图加小型同步缓存。Subsonic 表格也对相同封面资源避免重复清空。
- Most Played 保留数据库按播放次数返回的排行，首次进入前加载艺术家、专辑和封面映射；查询期间显示加载状态，切换目的地后丢弃过期结果。该页将 Plays 列放在 Title 后，ID 列默认隐藏；ID 是 SQLite 曲目主键，并非可靠的导入次序。筛选后仍保持排行的定点测试通过。
- 移除了智能文件夹进入时的重复取数；toast 动画限定在 toast 自身，不再让整个浏览器参与动画事务。About 改用 WMusic 名称与上游归属说明；本地构建不再显示不可用的更新按钮。重新生成的声明与本次嵌入库匹配，包内另存 21 份原生库许可证。
- UI 相关定点测试 21 项及新增智能文件夹回归测试 1 项通过；`git diff --check`、Release 构建、依赖重定位、ad-hoc 签名、沙盒权限与 `codesign --verify --deep --strict` 通过。`dist/WMusic.app` 与 `~/Applications/WMusic.app` 主程序 SHA-256 均为 `a640d21fa69b59bba6b4cc0514340a377d359aac00193fa89c3dde129d30bf60`。安装前的应用及 SQLite 在线备份位于 `.build-logs/install-backups/2026-09-29-artwork-notices/`，备份库 `quick_check` 为 `ok`。
- “添加服务器”当前接受 NAS 上的 Subsonic/OpenSubsonic 兼容服务，例如 Navidrome；SMB/NFS 共享需先在 Finder 挂载，再通过 Add Music Folder 纳入本地曲库。本轮没有可用 NAS 端点，因此不把真实 NAS 连接写成已验收。后续解锁后的安装版播放页与跨尺寸复测见下文；切歌瞬态没有可靠的逐帧记录。

## Claude Code 首轮审查后的过渡修复（2026-09-29，已由下文方案替代）

- 读取 Claude Code 会话 `cse_011BUimaEr31EESG6mjhfQ6F` 中 Opus 5.5 的只读审查。它指出覆盖层淡入与窗口工具栏重排处于同一更新阶段，以及固定 210 毫秒延时后才用加载指示器替换队列；这些是源码推断，审查本身没有构建或运行证据。
- 当时的全窗口播放页分阶段隐藏浏览器辅助功能树、淡入覆盖层、调整工具栏并装载队列；退出时先恢复工具栏，再淡出覆盖层并恢复浏览器焦点。移除队列固定延时与加载指示器切换，队列先注册变更流，再从 `PlaybackQueue` 一次读取歌曲和播放位置；并发刷新用序号丢弃过期结果，拖拽索引加边界校验。未加入跨两个布局树的封面匹配动画，以免切歌及窗口缩放时重新引入封面解码和视图身份变化。
- `swift build --package-path player/Modules/UI`、`QueueReorderGripTests` 2 项和 `PlaybackQueue` 相关 41 项测试通过。`./script/build_local_app.sh` 完成 Release 构建、依赖嵌入和 ad-hoc 签名；安装版 `codesign --verify --deep --strict` 通过，主程序与 `dist` 的 SHA-256 同为 `04be6ff5466c5a36cc697fab85dd79644ca2bf9f57b77201785476ed0a7bc142`。替换前应用及 SQLite 在线备份位于 `.build-logs/install-backups/2026-09-29-opus-transition/`，备份和运行库的 `quick_check` 均为 `ok`。
- 实际安装版以既有曲库打开播放页，连续三次展开／关闭后都显示正确的当前曲、待播队列和原歌曲列表；⌘F 能关闭播放页并把焦点交给搜索框。在内置屏幕约 900×600 点的紧凑窗口，封面、元数据、控制和队列均可见。播放页保持打开时，利用系统窗口菜单跨越 920 点宽／620 点高阈值，队列仍可见，进程持续运行；崩溃报告目录未增加新的 WMusic 报告。未修改真实音频标签。
- Instruments 的 Animation Hitches 录制在 20 秒时间限额后仍长时间处理大量系统显示事件，未取得可归因于 WMusic 此过渡的前后对比，因此不宣称定量帧率改善。电脑操作工具的拖边动作未改变窗口尺寸；上述跨阈值验收使用系统窗口菜单，并不等同于连续拖边压力测试。

## Claude Code 实机复核后的播放页过渡（2026-09-29）

- 同一 Claude Code 会话 `cse_011BUimaEr31EESG6mjhfQ6F` 的后续复核在实机画面中看到：首轮分阶段方案打开时，工具栏曾覆盖播放页标题和关闭按钮；关闭时，底层侧栏与列表先出现在工具栏隐藏的位置，再跳回原位。复核据此建议始终保留原生工具栏，让播放页只做透明度变化。
- 本轮取消播放页开关中的工具栏显隐和延迟队列装载。播放页与待播列表在曲库目的地恢复后预先挂载，鼠标悬停封面也会预热；开关只对覆盖层做 0.28 秒淡入淡出。覆盖层从工具栏下方的内容安全区开始，背景可延伸到窗口边缘；关闭按钮移入内容区，Esc 与隐藏状态的键盘焦点分别受控。快速连续开关用代数令牌丢弃过期关闭回调。
- 第一次安装后，用户在实际收起时继续看到侧栏和列表回跳。曾尝试把浏览器无障碍状态的恢复提前到淡出开始并取消普通关闭的强制根视图聚焦；用户复测仍看到了跳动。因此最终改成把播放器作为 `windowContent` 的叠层，浏览器视图本身在开关过程中不再切换命中测试或无障碍修饰符。独立透明遮挡层阻断淡出期间的指针输入；播放页的模态辅助功能标记使展开时侧栏和歌表退出辅助功能树，关闭后自动恢复。搜索和导航键盘监视保持暂停直到淡出完成。
- `swift build --package-path player/Modules/UI` 和 `git diff --check` 通过；`./script/build_local_app.sh` 完成 Release 构建、内嵌依赖与 ad-hoc 签名。最终安装版通过 `codesign --verify --deep --strict`，bundle ID 为 `com.willhsu.wmusic.local`，主程序与 `dist` 的 SHA-256 均为 `c6508241cb4c8b7126ab7a0a90757969b1c8429c486b28fdb2e82f49680d0ec8`。每次替换前应用与 SQLite 在线备份位于 `.build-logs/install-backups/2026-09-29-toolbar-stable/`，备份库 `quick_check` 为 `ok`。
- 最终安装版实机画面显示播放页在原生工具栏下方覆盖内容区，封面、曲目信息、控制和待播列表可见；连续三次展开与关闭后，侧栏、歌曲列表和工具栏恢复。展开时辅助功能树只暴露播放页，关闭后侧栏与歌表重新可见；Esc 可关闭，⌘F 可关闭并聚焦搜索框。用户在此版实际复测确认收起时已不再跳位。工具未提供可靠的逐帧录像，端点检查与主观确认都不等于定量帧率结论。

## 主窗口重复扫描修复（2026-09-29）

- 根因：`WindowGroup` 重新挂载主窗口时会重跑 `BocanRootView.task`；该任务原先无条件调用 `triggerScan()`。`isScanning` 只阻止同时扫描，无法阻止一次扫描完成后的再次开窗，因此每次都遍历曲库并弹出「1,292 unchanged」总结。
- 共享的 `LibraryViewModel` 现在只允许每个 App 进程触发一次启动快速扫描。这样仍可补查 App 退出期间的磁盘变化：现有 FSEvents 监听从 `SinceNow` 开始，不能回放退出期间的事件。新建来源和文件菜单手动重扫不经过此门禁。启动扫描若完全无变化且无错误，不再显示完成横幅；有变化或错误仍提示。
- `StartupScanGateTests` 使用内存数据库、临时目录和真实 `LibraryScanner` 验证首次启动、维护请求清除、扫描完成后再次开窗不重扫，以及手动重扫仍可执行；定点测试 1 项通过。UI 模块构建、`git diff --check`、Release 构建、依赖嵌入和 ad-hoc 签名检查通过。
- 已安装到 `~/Applications/WMusic.app`，主程序与 `dist/WMusic.app` SHA-256 均为 `da485d654a1c269ada7a80f7e8f395ef5a11d34775a5eecb2b469ea458d77c62`。安装版进程 `99060` 的实时日志在首次启动记录 1 次 `scan.trigger [mode=quick]`；关闭并重新打开主窗口后仍为 1 次，歌曲列表可见，未出现扫描完成横幅。原曲库仍为 1,291 首，`quick_check=ok`。替换前应用和 SQLite 在线备份位于 `.build-logs/install-backups/2026-09-29-startup-scan/`。
- 真正退出 App 再启动仍会做一次快速扫描，这是补查离线变更所需的行为；本次修复的是同一进程内每次开窗重复扫描。首次启动的进度提示在扫描进行中仍可能短暂出现。

## 曲末循环停止修复（2026-09-29）

- 安装版播放条显示 `Repeat: all` 时，统一日志在 17:02:48、17:16:10 记录 `pump.read.failed`，错误为 AVFoundation `OSStatus -39`，随后记录 `engine.playback.failed`。macOS SDK `AudioToolbox/AudioFile.h` 将 -39 定义为 `kAudioFileEndOfFileError`。旧解码器只识别错误码 0 为 EOF，导致曲末进入失败事件，绕过队列的循环推进。
- `AVFoundationDecoder` 现在将错误码 0，以及 `NSOSStatusErrorDomain` 中的 `kAudioFileEndOfFileError`，转换为正常零帧 EOF；其他错误仍作为解码失败。打开时探测读取使用同一判断。新增短 FLAC 读尽后再次返回零帧、以及 EOF／非 EOF 错误码分类测试。AudioEngine 定点测试 16/16、全套测试 331/331 和 `git diff --check` 通过。
- Release 构建、依赖嵌入、ad-hoc 签名及 `codesign --verify --deep --strict` 通过。将候选应用复制为独立 bundle ID `com.willhsu.wmusic.repeatqa.20260929`，以全新 `BOCAN_E2E_RUN` 启动；测试数据库位于该克隆沙盒的 `tmp/wmusic-e2e/`，与真实曲库隔离。用 12 秒合成 FLAC 的单首队列验收：`Repeat: one` 和 `Repeat: all` 均跨过多次自然曲末，播放按钮保持暂停且进度回到开头；`Repeat: off` 则在曲末显示播放按钮。测试库该曲留下 7 条播放历史。短样本本机只稳定触发错误码 0，实际 -39 由注入回归测试覆盖。
- 新版已安装到 `~/Applications/WMusic.app` 并从该路径启动，进程持续运行，播放条和曲库界面正常。安装版与 `dist/WMusic.app` 主程序 SHA-256 均为 `f04a68bd692ff0d17acaccc3ef540d2b00d2e6086df7082af718e3d8500dac8d`，签名为 ad-hoc。安装前旧 App 和 SQLite 在线备份位于 `.build-logs/install-backups/2026-09-29-repeat-eof/`；安装后真实曲库为 1,294 首且 `quick_check=ok`。未用真实曲目重放末尾，以免改写用户播放历史。

## Claude Code 切歌显示快照续接与安装验收（2026-09-30）

- 点名会话 `cse_011BUimaEr31EESG6mjhfQ6F` 的最新修改尚未编译、测试或安装。本轮保留其 `NowPlayingDisplay` 方案：本地切歌等待元数据与 decoder facts 一起提交，350 ms 兜底；底栏固定字幕／徽章占位，只有封面变化时做封面过渡，展开页、沉浸和迷你播放器读取同一快照。
- 复查补修两类 `.ready` 竞态：异步 facts 读取跨越下一首／同曲重载／清空／切换流时，用 generation 丢弃过期结果；已经缓冲的旧 ready 则通过实际 decoder 的源 URL、codec 与 details 原子快照校验。新增真实 decoder 用例先复现 5 个失败断言，修复后通过；清空后拒绝旧 facts。另修复搜索框获得焦点后打开播放页时 Esc 被抢走，展开时释放搜索焦点。bookmark 已移动、数据库路径尚未同步时，安全降级为 scanned columns，不显示未确认的 live codec。
- 最终定向 UI 测试 **79 项／11 组**、decoder 与 gapless 定向 **51 项／7 组**通过，`git diff --check` 通过。完整截图套件的旧失败没有重录或视为通过。Release 脚本完成构建、依赖重定位、逐个 Mach-O 检查、ad-hoc 签名及沙盒核对。
- 使用独立 QA bundle ID 和 E2E 数据库，用自建 FLAC／MP3 实测长短标题、相同／不同专辑封面、底栏／展开／沉浸／紧凑及方形迷你播放器切歌；播放页常规与放大窗口、实时队列和 Get Info 打开后取消均有实际界面证据。搜索后展开与 Esc 关闭连续三轮通过，最终 source snapshot 包又复核一次；最终包 FLAC → 长标题 FLAC → MP3 的标题和编码信息读回一致。没有逐帧录像、FPS 或连续拖边量化保证。
- 已替换并启动 `~/Applications/WMusic.app`，安装版进程 `25307` 的路径、实际加载动态库和原沙盒数据库均已读回。安装版与 `dist/WMusic.app` 主程序 SHA-256 同为 `09fbcaae943f08458f8b63072cd89d0e47b62bd680c3906d19ac2440b3d8448f`；`codesign --verify --deep --strict` 通过，无 `get-task-allow` 或 Homebrew 动态库加载。原浏览页和展开队列实际渲染正常，应用保持未播放状态；未用真实曲目重放作验收。重启后 UI 进度为 0:00，播放位置恢复未通过实际播放核对。
- 验收中自建的 3 个音频曾因真实来源监控 `.build-logs` 而被自动导入。素材已移到 QA 沙盒；完整数据库备份后，只清理本轮自建 track `1295–1297` 及自建关联记录。原有 tracks、artists、albums、play_history、library_roots、playlists 记录在清理前后、安装后均一致，曲目 **1,294**、播放历史 **63**，SQLite `quick_check=ok`、外键检查为空。本次操作时段没有新增 WMusic 崩溃报告。旧应用与清理后的数据库备份位于 `.build-logs/install-backups/2026-09-30-claude-display/`；完整证据索引为 `.build-logs/claude-continuation-20260930/acceptance.md`。

## 随机开关队列修复与 1.0.1 安装验收（2026-09-30）

- 关闭随机现在恢复完整原始顺序，并以当前 QueueItem UUID 找回当前位置；再次开启从完整来源重新随机并保留当前歌。播放入口不再预先随机两次，`playAt` 不再覆盖原顺序。队列拖动与 Songs 排序复用原有身份，重复曲目按实例定位；随机排除项在顺序播放时恢复。
- 持久化新增可选 `sourceItems`，与当前随机顺序、游标和开关一起保存。恢复直接读取已有顺序，不再次随机。旧 blob 的原顺序保持未知，界面只有在完整、唯一的本地 Songs 集合精确匹配时才恢复，避免猜测播放列表来源。
- 切换开关会等待并取消旧下一首预取，保留当前 pump 和播放时间；已经进入混音或 handover 的曲目按实际 incoming UUID 更新游标。最终 `make test-playback` **239 项／35 组**、UI 定向 **83 项／9 组**全部通过；`git diff --check` 通过。完整历史截图套件未重新验收。
- 独立 QA bundle ID 沿用 `com.willhsu.wmusic.displayqa.20260930`，数据与真实曲库隔离。实际 Playing Queue 验证从中间 FLAC 开始、关随机后的顺序后缀、再次开随机的完整来源、Songs 排序后关随机、自然推进及当前歌不变。最终包播放进度在开关过程中从 0:10 → 0:22 → 0:36 连续前进；退出／启动后的 queue JSON（含 UUID、游标、原序、随机种子）完全相同。重启后暂停状态的 UI 仍先显示 0:00，恢复播放合成曲后显示已有 0:10；本轮没有改暂停状态进度同步。
- 已安装并启动 `/Users/willhsu/Applications/WMusic.app`，实际 About 显示 **Version 1.0.1 (2)**。安装版及 `dist/WMusic.app` 主程序 SHA-256 同为 `f25e35c8da4b5f629c7e0fc1cee0ad4b1f663f0815ba99e57b1cbb95ba96ff3e`；严格深度签名、沙盒、进程路径、真实数据库和动态库加载读回通过，无 Homebrew 依赖加载。
- 更新前正常退出时曲库为 1,294 首、历史 72 条。启动扫描补入 Downloads 的真实 FLAC `1295` 并刷新来源 `1289` 的 bookmark；原有 1,294 条曲目及历史均无变化，未删除新文件／记录。旧已关闭随机的 1,293 项队列经过原库快照的完整 Songs 默认排序逐项比对，确认完全一致后，退出 App、备份数据库，只补存 `sourceItems`。未把新导入歌曲插入旧播放来源。重启后真实队列 on → off 仍为当前 UUID `6AF6E182-A430-44FC-9DE1-EDBED9BE4B9B`、原索引 305，Playing Queue 显示「倒流时间 → 再见 → 北京北京 → HELL」。未播放真实曲目作验收。
- 队列迁移与最终实机开关前后，tracks、artists、albums、library_roots、playlists、play_history 六表逐行摘要完全相同；最终 1,295 首、72 条历史，SQLite `quick_check=ok`、外键检查为空。旧 App、原始数据库和迁移前数据库在 `.build-logs/install-backups/2026-09-30-shuffle-1.0.1/`；日志和截图索引在 `.build-logs/shuffle-1.0.1-20260930/acceptance.md`。

## W 音符图标替换（2026-10-01）

- 使用用户批准的完整 W 音符图稿，保留透明留白，导出 16–1024 px 的标准 macOS AppIcon 资源。旧 Composer 包留作源文件参考并从资源构建排除，避免覆盖新图。原稿存于 `player/assets/icon/wmusic-w-note-source.png`；本轮未改播放逻辑，版本保持 **1.0.1 (2)**。
- Release 构建、依赖嵌入、逐个 Mach-O 检查、ad-hoc 签名、沙盒和严格深度签名检查通过；编译后的 Assets.car 含 10 个 AppIcon 槽位。实际查看 16／32／128 px 及包内 ICNS，图形与批准稿一致。安装包全部文件的摘要与 `dist/WMusic.app` 相同，主程序 SHA-256 为 `2ef47bdebad78745ad9c081c76779e31a006c1b4a9fe3248b65d963c3af3026d`。
- 已替换并从 `/Users/willhsu/Applications/WMusic.app` 启动。首次关于页仍显示系统缓存的旧图；正常退出后，仅对该应用执行 LaunchServices 强制注册并更新包目录修改时间，再启动。实际关于页已显示新的 W 音符和 Version 1.0.1 (2)。未重启 Finder／Dock 或全局清空缓存；Finder／Dock 的单独画面未验收。
- 更新前后 tracks、artists、albums、playlists、play_history 五表逐行摘要相同：**1,295 首、103 条历史**。持久队列 JSON 全字段语义一致，保留 1,294 项、当前位置与随机种子；SQLite `quick_check=ok`，外键检查为空。启动时外接音乐盘 `WILLEXTEND` 未挂载，1,286 个来源仅更新 `is_inaccessible`，没有删除来源、歌曲、历史或书签。音频加载因文件不存在而失败，第二次启动底栏显示 Not playing；队列保留，本轮未用真实曲目重放验收。
- 旧应用与数据库在线备份位于 `.build-logs/install-backups/2026-10-01-w-note-icon/`。完整资源摘要、构建与签名记录、数据比对及实际关于页截图见 `.build-logs/icon-replacement-20261001/`。

## 正式目录、Dock 刷新和单一回滚整理（2026-10-01）

- 用户明确要求正式版固定放在 `/Applications/WMusic.app`，备份只保留一个回滚版本。实际核对该包为新 W 音符 **1.0.1 (2)**，与原 `~/Applications/WMusic.app` 的全部文件摘要相同，正式包严格深度签名检查通过。
- Dock 原有唯一 WMusic 入口已经是 `file:///Applications/WMusic.app/`。对正式路径强制更新 LaunchServices 登记和包目录修改时间，重启 Dock 后，从正式路径启动，实际进程路径与关于页新图标、版本读回通过。当前界面工具无法直接读取 Dock 画面，已请用户核对刷新后的显示；不能用关于页截图替代 Dock 画面验收。
- 保留上一正式版（主程序 `f25e35c8…`）和配套数据库，统一移至 `.build-logs/install-backups/current-rollback/`。该应用的签名和数据库 `quick_check` 通过。已按用户授权清理其余 10 个旧安装备份目录、`dist/previous/` 的历史成品，以及与正式包完全相同的 `~/Applications/WMusic.app` 副本；共清理 58 份历史应用拷贝。现在安装备份仅剩一个目录，约 167 MB。此前记录中的旧备份路径为历史记录，已由此唯一回滚位置取代。
- 清理与正式版启动后，曲目、艺术家、专辑、播放列表和播放历史摘要与整理前相同，持久队列摘要也相同；仍为 1,295 首、103 条历史，SQLite `quick_check=ok`，外键检查为空。完整清理清单、路径与签名／数据读回和正式版关于页截图位于 `.build-logs/dock-release-policy-20261001/`。
- 固定路径与保留约定已写入项目 `AGENTS.md` 和 `player/CLAUDE.md`；构建和安装流程的说明见 `README.md`。构建脚本只保留一个候选，安装脚本固定正式路径，完整校验通过后才轮换唯一回滚。已为现有回滚补齐正式／回滚应用的完整文件清单与安装元数据；其数据库转为独立 DELETE 快照时，所有表摘要完全相同。
- 新安装脚本的隔离 fixture 覆盖相同候选保留旧回滚、连续升级、已提交 WAL 的快照与源库字节不变、失败恢复，以及四个重命名边界的 SIGINT 恢复。签名、复制和进程命令在这些 fixture 中使用桩；哈希、SQLite、文件重命名和信号是真实临时执行，不能当作新脚本的正式安装验收。另以实际正式进程验证运行保护：脚本返回 1，明确指出 `/Applications` 中应用仍运行，没有替换或轮换备份。两脚本语法、嵌入 Python 编译和 `git diff --check` 通过；证据为 `install-script-fixture-validation.json` 和 `running-app-guard.log`。

## 尚未验收与私下交付前工作

- 上游 `make test-ui` 的完整 UI 测试存在 33 项截图基线等失败。Nocturne 改色会改变截图；尚未逐张复核或重录，因此不能把完整截图套件视为通过。
- APE 已在安装版曲库中显示并完成界面播放进度验收；本轮未从空曲库重跑导入操作，也未用真实输出设备逐项听测 APE、无缝播放、均衡器、格式切换，或连接 Subsonic、播客服务、Last.fm 与 Bòcan 手机客户端。
- Debug 产物仍引用 `/opt/homebrew/opt/` 下的 FFmpeg 与 TagLib，不能作为可复制的应用使用。Release 成品已完成本机依赖重定位与运行验收，但朋友的 Mac 上的系统兼容性和首次打开流程还未测试。本机 Homebrew FFmpeg 构建标记为 GPL-3.0-or-later，部分动态库针对 macOS 27 构建；私下交付前仍需核查目标系统及附带库声明。

开发入口和依赖见 [README](README.md)，源码来源与本地改动约定见 [UPSTREAM](player/UPSTREAM.md)。

## 2026-10-01：NAS Sources 功能候选

Sources 新增 NAS Folders，使用 macOS 的 SMB 连接与安全文件夹授权；NAS 来源可在侧栏单独浏览、搜索及重扫，断线保留已索引歌曲。完整 Library 441 项与 UI 定点 50 项通过，Release 候选签名和独立 QA 实际窗口检查通过。最终全量 UI 1274 项中仍有 46 个快照差异，未更新基线。本轮按用户“先做功能”交付候选，未连接用户群晖、未安装正式版；原应用及真实曲库条目数保持一致。详细口径、限制与日志见 [.build-logs/nas-sources-20261001/acceptance.md](.build-logs/nas-sources-20261001/acceptance.md)。

## 2026-10-01：NAS Sources 正式版安装

用户后续授权验证后替换正式版。候选相关功能测试、构建签名和实际 QA 页面已通过；另只读抽查 3 组快照差异，未发现阻碍 NAS 页面功能的界面缺陷，完整快照套件仍未通过且未重写基线。正常退出旧正式进程后，执行 `script/install_local_app.sh` 安装到 `/Applications/WMusic.app`，完整包摘要、身份、沙盒、签名及唯一回滚应用/曲库快照读回通过。新正式进程打开真实容器曲库，已实际查看并保留 Sources → NAS Folders 页面供用户验收。

安装前正常退出、安装后未启动时及回滚曲库的 48 表内容摘要与完整队列一致。启动后除 settings 的正常备份时间戳和 JSON 序列化顺序外无内容变化；队列及 UI 状态解码后相同。歌曲 1,295、历史 103、来源 1,289、播放列表 7，队列与 sourceItems 均 1,294 项；quick_check 通过、外键检查为空。没有连接用户群晖或播放真实歌曲，实际 NAS 登录、导入、播放与断线重连仍待用户验收。详细安装、进程与数据证据位于上述 acceptance.md 与同目录 install-*.json / install-formal.log。

## 2026-10-01：内网/Tailscale 服务器根地址修正与安装

用户输入服务器根地址 被强制共享目录校验拦住。Connect 已改为接受服务器根、裸内网/Tailscale IP、MagicDNS 名称及可选共享路径；已挂载来源的严格 share 校验保持。占位和提示不再引用 nas.local，README、中英文文案及伪语言已同步。13 项地址测试（88 场景）、33 项 UI 定点测试与 Release 构建通过；独立 QA 实际点击服务器连接后，Finder 明确显示连接同一服务器，不再出现应用内校验错误。本次系统连接随后取消，未登录或导入，因此不宣称用户 NAS 已连接成功。

按既有授权正常退出旧正式版，使用固定安装脚本更新 `/Applications/WMusic.app`，完整文件、签名、沙盒及唯一回滚应用/曲库读回通过。新进程与候选主程序摘要 `bef223c0…` 一致，Sources 页已打开并恢复用户地址。曲库、播放列表、历史、来源与队列内容保留，quick_check 和外键检查通过。启动扫描显示 1,286 项错误，原曲库及来源摘要未变；本次不据此宣称原文件全部可访问。详细证据见 [.build-logs/nas-server-address-20261001/acceptance.md](.build-logs/nas-server-address-20261001/acceptance.md)。

## 展开播放器：队列／歌词切换（2026-10-09，候选）

- 在展开播放器右侧加入 Queue / Lyrics 分段切换，记住展示选项。新增大字号左对齐歌词、当前句突出、上下渐隐和逐句自动定位；手动滚动暂停跟随，Follow Lyrics 恢复定位。支持普通全文歌词、间奏空行和原有无歌词／获取中提示，复用已有 LyricsService 和根视图的播放驱动。视觉和逐句展示参考 [Apple Music 官方说明](https://support.apple.com/en-us/108960)；没有接入 Apple Music 歌词服务。
- 点击歌词通过统一的时间换算计入文档偏移、已保存及待保存的调整。实际 QA 发现原有 `NowPlayingViewModel.scrub` 在暂停时不刷新位置；现于 seek 后读取引擎实际位置，立即刷新进度和高亮，且保持暂停。歌词异步加载完成时也会重新对齐当前进度。
- 定点验证：`PKG_CONFIG_PATH=/opt/homebrew/opt/ffmpeg/lib/pkgconfig swift test --package-path player/Modules/UI --filter 'Lyrics|ImmersiveWiring|NowPlayingViewModelTests'`，59 项测试、10 个 suite 全部通过。包含偏移换算、暂停跳转读回及已有播放／歌词观察回归。`git diff --check` 通过。
- `script/build_local_app.sh` 构建 Release 候选成功；依赖嵌入、ad-hoc 签名、沙盒与深度签名验证通过。候选固定为 `dist/WMusic.app`，版本仍为 1.0.1；主程序 SHA-256 为 `8e18ea55b3c4e88fa39f9109b0a0ae77c13b5e53b29712af73f4aeeaec99246a`。
- 原生界面 QA 使用独立 bundle ID `com.willhsu.wmusic.lyricsqa.20261009` 和 `BOCAN_E2E_RUN=expanded-lyrics-20261009`，仅播放两段 60 秒合成 WAV 与原创测试歌词。验证了队列／歌词往返、自然播放逐句滚动、暂停点击跳到 0:12 并保持暂停、手动滚动及恢复跟随、重启保留歌词选项、普通歌词、无歌词、浅色／深色及约 900×603 pt 紧凑窗口。最终 QA 与候选的 Mach-O UUID 一致，独立签名导致文件摘要不同。
- 证据位于 `.build-logs/expanded-lyrics-20261009/`：`tests-final.log`、`build-final.log`、`manifest.json`、`final-light.png`、`final-dark.png`、`final-compact.png` 及 AX 状态。临时 QA 应用验收后已移除，合成测试库保留供问题复现。LRClib 网络获取保持关闭，本轮未验证在线歌词匹配结果。
- 本轮交付源码与已验证候选；未替换 `/Applications/WMusic.app`，原正式进程持续运行。没有在真实曲库中写入测试歌词、导入测试音频或执行播放验收，也未轮换正式版回滚目录。

## GitHub 1.0.1 发布检查（2026-10-09）

- 首次发布目标为私有仓库 `williamhsu218/wmusic`，版本和构建号保持 1.0.1 (2)，纳入同日已完成的队列／歌词切换功能。发布准备期间检测到并行源码变更，待歌词任务完成后重新构建，并逐文件核对构建前后的源码摘要。
- AudioEngine 331、Metadata 96、Library 445、Persistence 359、Playback 239 和 UI 功能回归 238 项，共 1,708 项通过。两个新增歌词文案的 en-XA 长度原未达标准，使用 `make pseudolocale` 重新生成后，最终 UI 测试通过。源码凭据模式检查、空 API 配置读回、脚本语法和 `git diff --check` 通过。
- 发布准备阶段另一次 UI 定点运行中有 5 个既有截图基线差异，未重录。此处的功能测试通过不代表完整截图套件已通过；歌词实际渲染与交互证据沿用上节的最终 QA 记录。
- 最终包由 `script/build_local_app.sh` 生成，保留 ad-hoc 签名、沙盒和第三方许可。所有附带 Mach-O 均为 arm64，音频库最低系统版本为 27.0，因此预编译包发布为 Apple Silicon、macOS 27+，未公证。
- 安装包、SHA-256 校验文件和构建信息位于 `dist/`；本次 GitHub 发布不替换正式应用，不操作真实曲库，也不轮换正式版回滚。发布说明见 [docs/releases/v1.0.1.md](docs/releases/v1.0.1.md)，本次构建和测试日志位于 `.build-logs/github-release-1.0.1/`。

## 歌词区域隐藏滚动条与内容拖动（2026-10-09，候选）

- 同步／普通歌词改用 `.scrollIndicators(.never)`，支持原生上下滚动及按住内容拖动；8 pt 拖动阈值避免误触歌词跳转，普通歌词关闭文字选择避免高亮冲突。手动浏览和自动跟随统一使用 ScrollPosition，修复实际连续播放检查发现的居中偏移。
- 59 项相关回归、最终 Release 构建、签名、沙盒与 `git diff --check` 通过。独立合成曲 QA 验证了文字／空白区域双向滚动、双向拖动、暂停进度不变、点击跳到 0:12、恢复跟随及连续播放到 0:18／0:28 的当前句居中；同步与普通歌词均没有可见滚动条。
- 候选主程序 SHA-256 为 `7453458d909887232ef0e3bc4728e9029ce8b1b4c18bbe0be28dec23896f4b36`，与最终 QA 的 Mach-O UUID 一致。未在本任务执行正式安装或真实曲库操作。QA 已正常退出并移除，证据及限制见 [.build-logs/lyrics-scroll-20261009/acceptance.md](.build-logs/lyrics-scroll-20261009/acceptance.md)，最终截图以 `accepted-` 开头。

## 1.0.2 正式安装与发布验收（2026-10-09）

- 为已发布的 1.0.1 之后的歌词滚动修复新增版本 **1.0.2 (3)**。歌词代码与上节已通过 59 项回归和独立合成曲 QA 的源码摘要完全相同；新构建的 Mach-O UUID 仍为 `BA65A957-DE98-36DA-92B9-84C5B127410B`。构建仅更新版本、构建号和对应第三方声明的版本信息。
- `script/build_local_app.sh` 完成 Release 构建、依赖嵌入、逐个 Mach-O 签名与路径核对。候选固定身份、ad-hoc 签名、沙盒及无调试权限检查通过；主程序 SHA-256 为 `ad05d918220e518365d4ac8fa4778ce31e8f14cdf7f75291e51321b3bd96ae24`。
- 正式应用退出后，通过 `script/install_local_app.sh` 安装到 `/Applications/WMusic.app`。全部 153 个文件／目录／符号链接和权限条目与候选一致。唯一回滚 `current-rollback` 中的应用与安装前正式版完全一致，数据库快照通过完整性检查并与安装前 49 张表的逻辑摘要一致；安装本身没有更改真实数据库。
- 实际启动路径、About 的 **1.0.2 (3)**、全窗口歌词的隐藏滚动条、直接滚动及恢复跟随已读回；未点击真实歌曲播放。启动时应用的例行扫描更新了部分歌曲的不可用标记，其他歌曲字段、曲目集合、播放列表、队列内容及播放历史保持一致。运行库 `quick_check=ok`，没有加载 Homebrew 动态库。
- 发布说明位于 [docs/releases/v1.0.2.md](docs/releases/v1.0.2.md)。安装和实际窗口证据位于 `.build-logs/github-release-1.0.2/`；完整截图基线、其他 Mac 兼容性和真实 NAS 播放仍沿用已有验收限制。

## 1.0.3 歌词渠道修复与发布（2026-10-10）

- 版本 **1.0.3 (4)**，源码提交 `d9f8d5d`。原来仅向 LRClib 做精确查询，404、网络失败和解析失败都被当成没有歌词。现在精确查询无结果时按歌名搜索，核对歌手与时长，拒绝翻唱、不同版本和时长明显不符的结果；新增可单独开启的网易云音乐备用渠道，不使用账号或 Cookie。不同失败原因分别提示，切歌时取消旧请求；保存实际来源，不覆盖手动编辑、旁置 LRC 和内嵌同步歌词。
- Library 34 项与 UI／本地化 53 项测试通过，共 87 项，其中两项是实际网络请求测试。早期一次直接要求 LRClib 在线的测试遇到 503，记录保留，不据此认定该服务长期稳定。
- 原生 QA 使用独立身份 `com.willhsu.wmusic.lyricschannelsqa.20261010`、独立 E2E 库和静音合成 WAV，没有播放真实音频。界面显示 NetEase Cloud Music / Synced，主渠道故障时显示明确的连接失败提示；QA 与候选的 Mach-O UUID 相同。
- 正常退出旧版后通过 `script/install_local_app.sh` 安装，候选与正式版全部文件一致，安装本身保持 48 张表一致，唯一回滚为 1.0.2 (3)。About 显示 **1.0.3 (4)**；在正式设置中开启网易云备用渠道并读回。启动后除 settings 的例行备份时间外 47 张表完全相同，队列与页面状态语义相同，`quick_check=ok`；未播放真实曲目。
- 发布前 `script/check_publish_privacy.py --history` 通过。ZIP 本地解压、CRC 与严格签名检查通过，三个 GitHub 附件的服务端 SHA-256 与本地一致；完整下载回验因 TLS 握手错误和超时未完成，未记为通过。Release：<https://github.com/williamhsu218/wmusic/releases/tag/v1.0.3>。证据见 [.build-logs/lyrics-channels-20261010/acceptance.md](.build-logs/lyrics-channels-20261010/acceptance.md)。

## 1.0.4 常见歌曲歌词搜索优化（2026-10-10）

- 版本 **1.0.4 (5)**，源码提交 `0e8decf`。用户反馈张靓颖《画心》《如果爱下去》搜索不到歌词；实测原因是网易云搜索只读取前 20 条，两首原版分别位于第 77、46 条。候选扩大到 100 条，加入备用搜索接口、标题单独查询、繁简体与歌手别名。LRClib 搜索规范化主题曲、重制版等附注，现场、翻唱、混音等版本仍校验身份，时长最多容差 12 秒。新增独立开启的酷狗歌词专用源，依次尝试 LRClib、网易云、酷狗并保存实际来源；缺少曲目歌手时尝试专辑歌手。
- Library 42 项与 UI／本地化 53 项测试通过，共 95 项。8 首常见歌曲在网易云与酷狗均取得同步歌词，两首反馈曲还验证了完整获取链；这是实测样本，不代表所有歌曲都能取得。
- 原生 QA 使用独立身份 `com.willhsu.wmusic.lyricssearchqa.20261010` 和静音合成 WAV：两首均显示 NetEase Cloud Music / Synced，关闭网易云后刷新显示 Kugou / Synced；新增开关、展开歌词的滚动与跟随正常。
- 安装后全部文件与候选一致，安装本身保持 48 张表一致，唯一回滚为 1.0.3 (4)。About 显示 **1.0.4 (5)**，正式界面显示 NetEase Cloud Music / Synced。启动后 46 张表完全相同，lyrics 多一条自动获取的缓存，settings 中队列与页面状态语义相同，`quick_check=ok`；曲目、播放列表与历史未变。首次重启时曾短暂出现 “audio stream could not be reached” 提示，之后消失；本轮不作为 NAS 播放验收。
- 隐私检查、ZIP 校验及三个附件的服务端 SHA-256／大小核对通过；完整下载回验超过 45 秒未完成，未记为通过。Release：<https://github.com/williamhsu218/wmusic/releases/tag/v1.0.4>。证据见 [.build-logs/lyrics-search-20261010/acceptance.md](.build-logs/lyrics-search-20261010/acceptance.md)。

## 1.0.5 (6) 展开播放界面与发布（2026-10-10）

- 源码提交 `80e67a4`。展开播放页时隐藏曲库导航、标题和搜索工具栏，收起后恢复，并保留导航、选择与搜索状态。歌词／队列与整页共用背景，移除右侧圆角底板、渐变和分隔线；Queue / Lyrics 移到顶部独立控制行，顶部空白区域可拖动窗口。
- Release 构建与 62 项相关 UI／歌词／窗口测试通过。扩大到 116 项时有 4 项失败（旧 LyricsPlaybackDriver 字符串约定与 3 个 NowPlayingStrip 快照），在改动前源码上同样复现，基线另有 1 项 NowPlayingDisplay 时序失败；快照未重录，扩大检查未计为通过。
- 原生 QA 使用独立身份 `com.willhsu.wmusic.playeruxqa.20261010`、合成音频和原创测试歌词，覆盖浅色／深色、紧凑／宽屏、Queue / Lyrics 切换、歌词滚动与拖动、Follow Lyrics、顶部拖动、Esc 收起和 ⌘F 返回搜索。
- 安装后 About 显示 **1.0.5 (6)**，唯一回滚为 1.0.4。安装时 49 张表完全一致，启动后仅 settings 的例行备份时间更新，`quick_check=ok`；保持暂停，未播放真实曲目。
- 隐私检查通过，三个附件的服务端 SHA-256 与大小一致；ZIP 为 54,858,063 字节，SHA-256 `dd2437e49bfa823a52f1df24067ace0abd789d017b98e43b1260ed2d912badf6`。完整下载回验在下载 10,485,760 字节、50.71 秒时超时，未记为通过。Release：<https://github.com/williamhsu218/wmusic/releases/tag/v1.0.5>，发布于 2026-10-10T03:03:11Z。证据见 [.build-logs/player-ux-20261010/acceptance.md](.build-logs/player-ux-20261010/acceptance.md)。

## 1.0.5 (8) 图标统一（2026-10-12，本机，部分未通过）

- 以 `player/Resources/WMusicIcon.icon` 作为唯一图标来源，原 W 音符图不变；统一 CFBundleIconFile、CFBundleIconName 与 Xcode 图标设置，并移除另一套资源。安装脚本改为同时比较图标名称、ICNS 与 Assets.car 摘要，图标变化时刷新系统登记。
- 构建、严格签名和安装脚本的身份与沙盒校验通过；候选与正式版全部 118 个文件一致，About 与 NSWorkspace 小尺寸浅色／深色图标一致。唯一回滚为 1.0.5 (6)。真实曲库 `quick_check=ok`，曲目、播放列表、队列与历史未变；启动时例行更新了 library_roots 状态与备份时间。
- 未通过：系统设置 → 存储 → 应用程序中的正式应用仍显示白色外框，判断为系统按应用标识缓存的旧图标；清除系统图标缓存需要管理员权限，未执行，也未重启 Mac。Dock 实际截图未取得。本版本未发布到 GitHub。证据见 [.build-logs/small-icon-consistency-20261012/acceptance.md](.build-logs/small-icon-consistency-20261012/acceptance.md)。

## 1.0.5 (9) 会话延迟恢复（2026-10-15，本机）

- 启动时只从数据库恢复队列、选中项与续播位置，不打开音频文件，避免休眠的 NAS 或移动磁盘导致恢复失败；点击播放时按需加载，并可重试此前失败的加载，暂停时保存位置。退出准备改为异步执行，保存期间 AppKit 主循环保持响应。3 秒退出期限当时尚未加入，见 1.0.6。
- Playback 241 项、UI 定点 58 项、AudioEngine 播放控制 16 项与异步退出 1 项测试通过。
- 独立 QA 使用 1,293 项合成队列：先复现旧故障，再验证同曲重试、重启后直接播放、续播位置（15.64 秒）、队列顺序与选中项保留，以及连续开关切换。另以已安装包的隔离副本验证播放／暂停、退出重启与同曲续播，两次退出准备约 87 ms 和 128 ms。
- 正式安装后 About、正常退出与重启读回通过；真实续播位置 180.72 秒，除 settings 外 48 张表未变，曲库、播放列表与历史保留，`quick_check=ok`。唯一回滚为 1.0.5 (8)。启动扫描显示 0 首新增、1,295 首未变、1 项错误，未修改媒体文件；未用真实曲库播放。
- 限制：未做真实 NAS 重新挂载测试；扩大的 NowPlaying 过滤选中了快照套件，其中 3 个基线不同，未计为通过。本版本未发布到 GitHub。证据见 `.build-logs/transport-20261015/` 的 `acceptance.json` 与 `installed-acceptance.json`。

## 1.0.6 (10) 退出期限与本机安装（2026-10-18）

- 1.0.6 收录 2026-10-17 的三项提交：移除遗留 foobar2000 材料并整理文档、单一 Icon Composer 图标（即 1.0.5 (8) 的图标工作），以及会话延迟恢复与退出期限。与已安装的 1.0.5 (9) 逐一比对 118 个文件，差异仅为版本号、Xcode 27.0 → 27.1 的构建信息、主程序、Assets.car 的渲染项名称（WMusicIcon.icns 完全相同）、NOTICES 版本行和签名。唯一新增行为在退出：保存卡住时最多 3 秒后仍回复退出，并在保存队列后执行按阈值触发的增量 vacuum；`app.termination.timedOut` 与 `app.termination.vacuumFailed` 两个日志键不在 1.0.5 (9) 的主程序中。
- 候选由 `script/build_local_app.sh` 从提交 `f4b9ff3` 构建：ad-hoc 签名、固定身份、沙盒、无调试权限，不链接 Debug dylib。主程序目标为 macOS 15.0，附带的 33 个库与工具要求 macOS 27.0，全部为 arm64。构建时工作区只有 xcodegen 写入的随机 TEMP_ 标识变化，内容等价，已丢弃。
- 异步退出 3 项测试以独立 SwiftPM 包对当前源码全部通过，包括保存卡住时按期限只回复一次，以及先保存队列再 vacuum。10 月 15 日的同类测试包通过符号链接引用源码，当时只包含并运行了 1 项。
- 隔离 QA 使用身份 `com.willhsu.wmusic.quitqa.20261018` 和 `BOCAN_E2E_RUN` 合成音频。播放中退出时保存 28.68 秒位置与队列，vacuum 未达阈值未执行，退出准备 171.65 ms，未超时，进程正常结束；重启后恢复到 E2E Tone One 的 0:28，继续播放正常；第二次退出准备 124.04 ms。
- 安装前正式版已退出。真实曲库只读快照：`quick_check=ok`，48 张表（不含 sqlite_ 内部表），2,767 首、7 个播放列表、388 条历史。`script/install_local_app.sh` 安装 **1.0.6 (10)**，正式版与候选全部 118 个文件一致、签名有效；唯一回滚为 1.0.5 (9) 及安装前曲库快照（DELETE 日志模式，`quick_check=ok`）。
- 正式启动后恢复当前曲目并暂停在 1:53，播放列表可见；About 显示 **Version 1.0.6 (10)**；Dock 只有一个 WMusic 入口，显示 W 音符图标。1.0.5 (8) 遗留的系统设置存储列表白框问题本次未复核。正常退出时保存 113.4 秒位置与队列，执行增量 vacuum，退出准备 121.67 ms。之后各表行数不变，`quick_check=ok`，settings 仅 `backup.local.lastDate`、`playback.queue.v2`、`ui.state.v2` 变化；未播放真实曲目。
- `script/check_publish_privacy.py --history` 无违规。记录时尚未推送分支，也未发布 GitHub Release。限制：保存卡住时的退出期限只由单元测试覆盖，未使用真实休眠的 NAS；未运行完整截图套件。证据见 `.build-logs/release-1.0.6-20261018/`。
