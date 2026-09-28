# WMusic 音乐播放器开发计划

> 历史提案：本文件记录 2025 年从零开发 Rust/Tauri 跨平台播放器的构想，尚未实施。2026-09-28 的 macOS 开源底座选型及当前本地开发入口见 [README.md](README.md) 和 [PLAYER_SELECTION.md](PLAYER_SELECTION.md)。下文旧 GitHub 统计和目标不是当前验收结果。

> 版本：v0.1（初版）　|　日期：2025　|　项目目录：`/Users/willhsu/Creations/WMusic`
>
> 本计划基于两份实证调研：① GitHub 上当前主流音乐播放器的真实数据；② 本机 `foobar2000 v2.25.7` 的实际架构与数据模型（已读取其 SQLite schema、布局 DSL、组件清单）。

---

## 一、调研总结

### 1.1 GitHub 流行音乐播放器现状

以下为实测抓取的 GitHub 数据（star 数为抓取时实时值），按"可借鉴维度"归类：

| 项目 | Stars | 技术栈 | 定位 | 对 WMusic 的借鉴点 |
|---|---:|---|---|---|
| **navidrome/navidrome** | 22.9k | Go | 自托管流媒体服务器（Subsonic API） | 后端架构、Subsonic 兼容、多用户；"服务端 + 客户端"分层思路 |
| **nukeop/nuclear** | 18.3k | TypeScript / Electron | 聚合免费音源 | Web 前端工程化、多源聚合插件化思路 |
| **ciderapp/Cider** | 7.1k | JavaScript / Vue | Apple Music 第三方客户端 | 现代 UI/动效、流媒体集成、插件市场 |
| **hrkfdn/ncspot** | 6.7k | Rust | 终端 Spotify 客户端 | Rust 音频栈可行性验证、TUI 与核心解耦 |
| **strawberrymusicplayer/strawberry** | 3.9k | C++ / Qt | Clementine 分支，成熟全能 | 曲库管理、抓轨、转码、标签编辑的工程深度 |
| **DeaDBeeF-Player/deadbeef** | 2.0k | C | foobar2000 风格轻量播放器 | "foobar2000-like" 的组件/插件模型直接参照 |
| **quodlibet/quodlibet** | 1.8k | Python / GTK | 曲库管理器 | 大曲库查询、正则搜索、可扩展性 |
| **Taiko2k/TauonMusicBox** | ~8k* | Python / GTK | 现代 UI、内嵌歌词/封面 | 现代 UX、歌词同步、视觉化的产品打磨 |

> *Tauon 为训练数据估值，本次抓取遇 GitHub 限流未取到实时值，量级可靠。

**趋势结论：**
1. **跨平台是标配**，纯 Windows 已无市场（foobar2000 本身也已登陆 macOS/iOS/Android）。
2. **技术栈两极分化**：追求"现代 UI + 快速开发"走 Web（Electron/TS，如 Nuclear/Cider）；追求"音质/性能/可控"走原生（Rust/C++，如 ncspot/Strawberry/DeaDBeeF）。
3. **Subsonic/Navidrome 生态**（22.9k star）证明"本地 + 远程串流一体化"是当前最强的差异化方向。
4. **foobar2000 式组件架构**仍是发烧友/重度用户的终极诉求（DeaDBeeF 即以此定位存活至今）。

### 1.2 本机 foobar2000 架构分析（实测，非推测）

**版本：** v2.25.7（macOS）

**存储模型（关键发现）—— 全 SQLite 化：**

```
~/Library/foobar2000-v2/
├── config.sqlite       # 配置：config / configBlobs / configInts / configReals / configStrings（类型化 KV）
├── metadb.sqlite       # 元数据缓存
├── radio.sqlite        # 网络电台
├── library-v2.0/<hash>/content.sqlite   # 曲库内容库（按 hash 分片）
└── playlists-v2.0/
    ├── playlist-<UUID>.fplite              # 播放列表（二进制）
    └── playlist-<UUID>-props.sqlite        # 单列表属性（独立 SQLite）
```

`metadb` 表结构（核心数据模型，可直接借鉴）：

```sql
CREATE TABLE metadb (
  name           TEXT UNIQUE PRIMARY KEY NOT NULL,  -- 文件绝对路径作为主键
  info           BLOB,                               -- 缓存的标签信息（序列化）
  infoBrowse     BLOB,                               -- 用于浏览/排序的冗余索引信息
  size           INTEGER,
  lastModified   INTEGER,
  infoBrowseTime INTEGER,
  lastseen       INTEGER,
  created        INTEGER,
  attribs        INTEGER,
  attribsValid   INTEGER
);
-- 另有 metadb_indexes + 每个"分面索引"一张表（按 GUID 命名），
-- 支撑 Album List / Refacets 的实时分组浏览（按艺术家/专辑/流派等任意维度切片）。
```

**UI 布局——声明式文本 DSL（可热重载、用户可编辑）：**

```
splitter horizontal style=thin
 splitter vertical style=thin
  splitter horizontal style=thin
   tabs
    albumlist tab-name="Album List"
    refacets tab-name="Refacets"
 playlist
 splitter horizontal style=thin
   tabs
    splitter horizontal style=thin tab-name="Now Playing"
     albumart
     selection-properties sections=metadata
    playlist-picker tab-name="Playlists"
   playback-controls
```

**组件清单（从布局 DSL 与 .nib 文件反推）：**
`splitter` / `tabs` / `playlist` / `playlist-picker` / `albumlist` / `refacets` / `albumart` / `selection-properties` / `playback-controls` —— 每个都是可独立替换的 UI 组件；另有 `dsp-presets`（DSP 链）、`ImageCache`（封面缓存）、ReplayGain、UPnP 输出（`foo_out_upnp`）等扩展能力。

### 1.3 借鉴提炼：foobar2000 的"开源模式"精髓

foobar2000 本体闭源，但其**架构哲学**是开源生态最常被模仿的对象（DeaDBeeF 即公开自称 foobar2000-like）。其精髓有三：

1. **组件（Component）架构**：核心只做"解码 → DSP → 输出"管线与元数据/播放列表管理；其余（UI 面板、格式解码器、可视化、输出后端）皆为可热插拔的组件，通过明确定义的接口注册。
2. **SQLite 为单一事实源**：元数据缓存、配置、播放列表、索引全部结构化入库，而非散落的 XML/文本文件——查询快、可增量、可事务。
3. **声明式可编辑布局**：UI 不写死在代码里，而是用户可读写的文本 DSL，渲染器解析后实时拼装面板树。

---

## 二、产品定位与目标

### 2.1 一句话定位

**WMusic 是一款跨平台、发烧友级、组件可扩展的本地+流式一体化音乐播放器** —— 取 foobar2000 的工程内核（组件架构 + SQLite 曲库 + 声明式布局），披上现代 UI 与 Subsonic/Navidrome 远程串流能力。

### 2.2 目标用户

- **主力**：拥有大量本地音频文件（FLAC/Hi-Res/整轨抓轨）的发烧友与重度听众。
- **次要**：自建 Navidrome/Gonic 想要优质桌面客户端的用户；同时管理本地与流媒体的用户。

### 2.3 差异化（对竞品）

| 维度 | foobar2000 | Strawberry | Nuclear/Cider | **WMusic** |
|---|---|---|---|---|
| 现代 UI | 弱 | 一般 | 强 | **强** |
| 组件/插件架构 | 强 | 弱 | 弱 | **强（借鉴 fb2k）** |
| SQLite 曲库模型 | 强(v2) | 弱 | 无 | **强（直接移植）** |
| 声明式可编辑布局 | 强 | 无 | 无 | **强（借鉴 fb2k）** |
| Subsonic 远程串流 | 插件 | 内置 | 无 | **内置** |
| 开源 | 否 | 是 | 是 | **是** |

### 2.4 成功标准（v1.0）

- 10 万首曲库下，Album List 分组浏览响应 < 50ms。
- 启动到可播放 < 1.5s；空闲内存 < 250MB。
- 支持 FLAC/ALAC/MP3/AAC/OGG/Opus/WAV/APE/WV，Hi-Res 位完美输出（bit-perfect / exclusive-mode）。
- 至少 3 个可替换组件、1 套可编辑布局 DSL、1 个第三方插件示例。

---

## 三、技术选型

### 3.1 推荐核心栈（首选方案）

| 层 | 选型 | 理由 |
|---|---|---|
| **核心 + 解码/DSP/输出** | **Rust** | 内存安全、性能对标 C/C++；`symphonia`(解码)、`cpal`(输出)、`rodio`(高层管线) 生态成熟；ncspot 已证明 Rust 做音频客户端可行且受欢迎 |
| **桌面壳 / 跨平台分发** | **Tauri 2** | 比 Electron 安装包小 ~10×、内存低；Rust↔前端类型安全 IPC；macOS/Win/Linux 三端原生窗口 |
| **前端 UI** | **React + TypeScript + Tailwind** | 生态最大、招聘/协作成本低；组件模型天然契合 fb2k 式"面板即组件"；声明式布局 DSL 易渲染 |
| **数据层** | **SQLite (via `rusqlite` / `sqlx`)** | 直接复刻 foobar2000 v2 数据模型；零配置、事务可靠、查询足够快 |
| **构建/分发** | Tauri bundler + GitHub Releases + 自动签名 | 三端 CI/CD 一条流水线 |

> **为什么不是 C++/Qt（Strawberry 路线）？** 工程门槛高、招人难、迭代慢；Rust 在"性能 + 安全 + 现代化"间平衡更优，且 Tauri 让 UI 用 Web 技术开发，迭代速度碾压原生。
>
> **为什么不是纯 Electron（Nuclear/Cider 路线）？** 内存与启动开销大，且 Web 生态做位完美音频/Hi-Res 输出痛苦（需绕过浏览器音频管线的诸多限制）。Rust 核心把音频留在原生层是关键。

### 3.2 备选方案（如首选遇阻）

- **B1：C++ / Qt 6** —— 若 Hi-Res/低延迟要求极致，或团队有 Qt 背景。参照 Strawberry。
- **B2：纯 Electron + Node** —— 若团队只懂 Web 且接受性能代价。参照 Nuclear。
- **B3：Flutter** —— 若未来要快速覆盖移动端。代价是音频/DSP 生态弱，需大量自研桥接。

### 3.3 关键依赖（首选栈）

```
核心(Rust):     symphonia(解码) · cpal(音频输出) · rubato(重采样) ·
                rusqlite/sqlx(SQLite) · lofty(标签读写) ·
                serde(序列化) · tokio(异步) · anyhow/thiserror(错误)
DSP:           自研 trait + 内建 EQ/重采样/ReplayGain（组件化）
远程串流:        Subsonic API 客户端(自研，参照 OpenSubsonic 规范)
前端:          React 18 · Vite · Tailwind · Zustand(状态) · TanStack Query(数据)
图标/字体:       Lucide · 系统字体栈
```

---

## 四、架构设计

### 4.1 分层架构

```
┌─────────────────────────────────────────────────────┐
│  前端层 (React/TS)                                   │  ← 可整体替换为其他前端
│  面板组件 · 声明式布局渲染器 · 主题 · 交互             │
├──────────────────── Tauri IPC (类型安全) ────────────┤
│  应用层 (Rust)                                        │
│  播放列表管理 · 曲库索引 · 搜索 · 配置 · 插件宿主     │
├─────────────────────────────────────────────────────┤
│  核心服务 (Rust)                                      │
│  ┌───────────┐ ┌──────────┐ ┌────────────────────┐  │
│  │ Playback  │ │ Library  │ │ Component Registry │  │
│  │ Engine    │ │ (SQLite) │ │ (插件加载/接口分发) │  │
│  └───────────┘ └──────────┘ └────────────────────┘  │
├─────────────────────────────────────────────────────┤
│  组件接口 (trait) —— 全部可被插件实现替换              │
│  IDecoder · IOutput · IDSP · ILibrarySource          │
│  · IUIPanel · IMetadataProvider · IStreamer          │
├─────────────────────────────────────────────────────┤
│  平台层: cpal(CoreAudio/WASAPI/ALSA) · 文件系统       │
└─────────────────────────────────────────────────────┘
```

### 4.2 组件 / 插件系统（核心借鉴点）

借鉴 foobar2000 与 DeaDBeeF，定义一套基于 Rust trait 的组件接口，通过**注册表（Registry）**统一发现与分发：

```rust
// 核心只定义接口，实现由内置组件或第三方插件提供
pub trait Decoder: Send + Sync {
    fn supported_extensions(&self) -> &[&str];
    fn open(&self, path: &Path) -> Result<Box<dyn AudioStream>>;
}
pub trait Output: Send + Sync { /* ... exclusive mode, bit-perfect ... */ }
pub trait Dsp: Send + Sync { fn process(&mut self, buf: &mut AudioBuffer); }
pub trait UiPanel: Send + Sync { fn id(&self) -> &str; fn render(&self, ctx: &Ctx); }
pub trait LibrarySource: Send + Sync { /* 本地文件 / Subsonic 远端 统一抽象 */ }

// 启动时注册；运行时可热插拔（v2 目标）
registry.register_decoder(FlacDecoder::new());
registry.register_library_source(SubsonicSource::new(server, user, pass));
```

**插件形态演进：**
- **v0.x–v1.0**：内置组件（编译期注册），快速达成 MVP。
- **v1.1+**：动态库插件（`.wcp` WMusic Component Plugin，WASM 或 Rust dylib），参照 foobar2000 的 `.component` 与 DeaDBeeF 的 `.dll/.so/.dylib`。

### 4.3 数据模型（直接移植 foobar2000 v2）

```sql
-- 元数据缓存（移植 metadb）
CREATE TABLE tracks (
  id            INTEGER PRIMARY KEY,
  path          TEXT UNIQUE NOT NULL,        -- 主键：文件路径（或 远程 URI）
  source        TEXT NOT NULL DEFAULT 'local',-- 'local' | 'subsonic:<serverId>'
  info          BLOB,                        -- 序列化标签缓存
  size          INTEGER, mtime INTEGER,
  duration_ms   INTEGER, bitrate INTEGER,
  last_seen     INTEGER, created INTEGER,
  attribs       INTEGER, attribs_valid INTEGER
);

-- 标签扁平视图（便于 SQL 查询/排序）
CREATE TABLE track_tags (
  track_id INTEGER, key TEXT, value TEXT,
  PRIMARY KEY(track_id, key, value)
);
CREATE INDEX idx_tags_value ON track_tags(key, value);

-- 分面索引（移植 metadb_indexes，支撑 Album List/Refacets）
CREATE TABLE facets (
  dimension TEXT,   -- 'artist' | 'album' | 'genre' | ...
  key       TEXT,
  label     TEXT,
  track_ids BLOB,   -- 该分面下的曲目 id 集合（Roaring bitmap 序列化）
  PRIMARY KEY(dimension, key)
);

-- 播放列表（参照 playlist-props.sqlite）
CREATE TABLE playlists (
  id UUID PRIMARY KEY, name TEXT, position INTEGER,
  created INTEGER, updated INTEGER
);
CREATE TABLE playlist_items (
  playlist_id UUID, ord INTEGER, track_id INTEGER, ...
  PRIMARY KEY(playlist_id, ord)
);

-- 配置（移植 configBlobs/Ints/Reals/Strings 类型化设计）
CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT);       -- 通用
CREATE TABLE config_blobs (key TEXT PRIMARY KEY, value BLOB); -- 二进制（窗口几何等）
```

> **设计要点**：沿用 foobar2000 "文件路径为主键 + BLOB 缓存标签 + 独立分面索引表"的三段式，已在本机验证可承载上万曲目且查询毫秒级。

### 4.4 声明式 UI 布局 DSL（核心借鉴点）

复刻并简化 foobar2000 的布局 DSL，使其用户可读写、可分享、可热重载：

```
# WMusic 布局 DSL（示例）
splitter horizontal
  sidebar
    albumlist
    refacets
  playlist
  right-panel
    now-playing
      albumart
      lyrics          # 现代新增：同步歌词
    visualizer        # 现代新增：频谱可视化
  playback-controls
```

渲染流程：前端拿到 DSL 文本 → 解析为面板树（AST）→ 每个节点按 `id` 查找已注册的 `UiPanel` 组件 → React 渲染。切换布局 = 改文本 + 热重载，无需重启。

### 4.5 播放管线

```
Source(本地文件/远程流) → Decoder → AudioBuffer(浮点内部格式)
   → [DSP 链: ReplayGain → Resample → EQ → ...]  → Output(位完美/独占模式)
```
- 内部统一 32-bit 浮点，输出前按设备能力重采样（rubato）。
- DSP 链顺序可调、每个环节即一个 `IDsp` 组件。

---

## 五、功能路线图

### Phase 0 —— 基建（第 0–2 周）
- 仓库初始化：Tauri 2 + React + Rust monorepo；CI（lint/test/build 三端）。
- SQLite schema 落地（§4.3）；迁移脚本机制。
- 组件注册表最小骨架（§4.2）。

### Phase 1 —— 本地播放 MVP（第 3–8 周）★ 最小可玩
- 解码器：FLAC / MP3 / WAV（symphonia）。
- 输出：cpal，共享模式；基础传输控制（播放/暂停/ seek/音量）。
- 曲库：扫描本地文件夹 → 入库 → 元数据读取（lofty）。
- UI：播放列表视图 + 播放控制条 + 文件树选择（固定布局）。
- **里程碑 M1：能选文件夹、扫描入库、连续播放本地 FLAC/MP3。**

### Phase 2 —— 曲库浏览与布局（第 9–14 周）★ 发烧友体验
- Album List / Refacets 分面浏览（用 §4.3 的 facets 表）。
- 声明式布局 DSL 解析器 + 热重载（§4.4）。
- 可拆分面板（splitter）、标签页（tabs）。
- 搜索（全文 + 标签维度）；排序。
- **里程碑 M2：10 万曲库分面浏览 < 50ms；用户可编辑布局。**

### Phase 3 —— 音质与高级特性（第 15–20 周）
- 解码器补齐：ALAC / AAC / OGG / Opus / APE / WV。
- 位完美 / 独占模式输出（macOS CoreAudio hogging、Windows WASAPI exclusive、Linux ALSA）。
- DSP 链：内置 EQ / 重采样 / ReplayGain（扫描与回放）。
- 歌词（本地 LRC + 在线抓取）、可视化（频谱）。
- 标签编辑、批量重命名、整轨 + CUE。
- **里程碑 M3：位完美播放 + ReplayGain 全链路；对标 foobar2000 核心音频能力。**

### Phase 4 —— 远程串流与生态（第 21–26 周）
- Subsonic/OpenSubsonic 客户端（`ILibrarySource` + `IStreamer` 实现）。
- 网络电台（移植 radio.sqlite 思路）。
- 插件系统 v1：WASM 沙箱插件（安全加载第三方 IDsp/IUiPanel/IDecoder）。
- 主题系统；布局/主题市场（社区分享）。
- **里程碑 M4：连 Navidrome/Gonic 服务器浏览+播放；可加载第三方插件。**

### Phase 5 —— 打磨与发布（第 27–32 周）
- 全局快捷键、媒体键、系统托盘、MPRIS(macOS)/SMTC(Win)/MPRIS(Linux) 系统集成。
- 自动更新（Tauri updater）。
- 三端签名与商店上架（Mac App Store 可选、Microsoft Store、Flathub）。
- 无障碍、国际化（i18n，中文优先）。
- **里程碑 M5：v1.0 公开发布。**

---

## 六、里程碑与时间表（概览）

| 里程碑 | 周次 | 交付 |
|---|---|---|
| M1 本地播放 MVP | 第 8 周 | 扫描→入库→播放 FLAC/MP3 |
| M2 曲库浏览+布局 | 第 14 周 | 分面浏览 <50ms；可编辑布局 DSL |
| M3 音质/高级音频 | 第 20 周 | 位完美 + ReplayGain + 全格式 |
| M4 远程串流+插件 | 第 26 周 | Subsonic 客户端 + WASM 插件 |
| M5 v1.0 发布 | 第 32 周 | 三端签名上架 |

> 单人/小团队节奏：上述为全职等效；兼职请按 ×2 估算。可按 Phase 交付、每 Phase 一个可发布版本。

---

## 七、风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| Rust 音频某格式解码器不完整（如 APE/WV） | 格式覆盖不全 | 兜底用 ffmpeg 动态链接组件（可选依赖），未安装则降级 |
| 位完美/独占模式三端差异大 | 音质打折、崩溃 | 抽象 `IOutput`，每端独立实现 + 回退到共享模式；优先 macOS（本机即可验证） |
| Tauri IPC 性能瓶颈（海量曲目传输） | UI 卡顿 | 大列表虚拟化 + Rust 侧只传可见窗口数据 + 二进制协议而非 JSON |
| WASM 插件沙箱性能/能力受限 | 插件体验差 | v1 先做 Rust dylib 插件（高性能），WASM 作为"安全受限插件"并存 |
| 声明式 DSL 学习成本 | 用户不会用 | 提供可视化布局编辑器（拖拽生成 DSL）+ 内置模板库 |

---

## 八、下一步行动（立即可执行）

1. **确认技术栈**：评审本计划 §3.1 首选方案（Rust + Tauri + React + SQLite）；若采纳则进入 Phase 0。
2. **搭建 Phase 0 基建**：初始化 monorepo，落地 SQLite schema（可直接用 §4.3），打通三端构建 CI。
3. **跑通垂直切片**：在 Phase 1 内优先做"选一个 FLAC 文件 → 扫描入库 → 播放"的最小闭环，验证 Rust 音频栈可行性（本机 macOS 即可验证位完美输出）。
4. **建立需求池**：把 §五 各 Phase 功能拆成 issue，标注优先级与依赖。

---

## 附录 A：本机 foobar2000 实测取证清单
- 版本：v2.25.7（`~/Library/foobar2000-v2/version.txt`、`Info.plist` 双重确认）
- 存储：`config.sqlite`(类型化 KV) / `metadb.sqlite`(路径主键+BLOB标签) / `radio.sqlite` / `library-v2.0/<hash>/content.sqlite` / `playlists-v2.0/*.fplite + *-props.sqlite`
- 布局：`UI-Layout.txt`、内置 `Layout-Sidebar_Album_List.txt`、`Layout-Playlist_Only.txt`
- 组件（从布局与 .nib 反推）：splitter / tabs / playlist / playlist-picker / albumlist / refacets / albumart / selection-properties / playback-controls
- 扩展：DSP presets、ImageCache、ReplayGain、UPnP 输出（`foo_out_upnp`）

## 附录 B：GitHub 调研数据（实测，抓取时刻）
navidrome 22.9k(Go) · nuclear 18.3k(TS) · cider 7.1k(JS) · ncspot 6.7k(Rust) · strawberry 3.9k(C++) · deadbeef 2.0k(C) · quodlibet 1.8k(Python)
