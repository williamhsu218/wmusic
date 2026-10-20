# 正式版安装与实际运行验收

日期：2026-10-18。用户明确授权将异步与异常路径审计候选安装到 `/Applications/WMusic.app`。本轮通过 `script/install_local_app.sh` 安装原有候选，没有重新构建或改动 Opus 与本轮审计修复的源码。

## 安装身份与唯一回滚

- 正式版仍为 **1.0.6 (10)**，bundle ID 为 `com.willhsu.wmusic.local`。主程序 SHA-256：`3ff8380dcbb41e5e5ba8a1ee5a72bda98fc766aba84d1e93b9cddb9bae6f4626`。
- 安装前正式应用未运行。候选与之前验收的 118 个文件摘要完全一致；安装后再次比较整个包的文件、目录、权限及符号链接，全部一致。严格签名、沙盒及无 `get-task-allow` 检查通过。
- 唯一回滚为 `.build-logs/install-backups/current-rollback/`。其中应用是安装前正式版，版本也为 1.0.6 (10)，主程序摘要为 `cd2d6ee3f9cd2fd960b7e8711ce43cc3823a7f0fd2a3d8ef66a686b263cb39ac`；因此不能仅凭版本号区分新旧。
- 回滚应用完整清单与安装前一致，`library.sqlite` 使用 SQLite 在线备份保存安装前已提交数据，49 张表逻辑摘要与安装前一致，`quick_check=ok`。成功安装后才轮换旧回滚；目录内没有残留临时安装、待轮换或第二个回滚版本。

## 实际运行

1. 从正式安装位置启动，进程路径和已加载文件确认来自 `/Applications/WMusic.app`，使用原有正式沙盒数据库，没有加载 Homebrew 路径的库。
2. 实际主窗口恢复原曲目、**0:21** 和暂停状态；7 个播放列表可见。关于窗口实际显示 WMusic 1.0.6 (10) 与既有图标。展开播放页后队列正常显示，随后恢复原来的歌词面板偏好及主窗口。
3. 通过 ⌘Q 正常退出，进程消失；日志 `app.termination.prepared` 为 **247.6 ms**，没有触发退出期限。该数字是准备阶段耗时，不是完整退出性能基准。
4. 再从正式安装位置启动，仍恢复同一队列项、0:21 和暂停状态。偏好中的精确位置仍为 **21.223038548752836 秒**，当前应用保持运行并暂停。
5. 两次启动扫描均完成，汇总为 `inserted=0 removed=0 updated=0 skipped=1411 errors=0`；未产生新的 WMusic 崩溃报告。实际界面截图与辅助功能读回均已留存。

## 真实数据保留

安装器没有改动实时曲库。完成启动、退出和重启后，49 张表中 46 张逐行摘要完全一致，包含 **2,767 首曲目、7 个播放列表、393 条播放历史**和来源配置。

其余三张表的变化已逐项解释：`settings` 更新日常备份时间及保存时间，队列和界面状态 JSON 的键顺序变化；解码后内容与安装前完全相同，**1,403 项队列**及顺序、选择、随机和循环状态均保留。启动 CUE 扫描按原实现重建部分 `track_markers`，代理 ID 及 `sqlite_sequence` 递增，但全部 **94 个标记**的曲目、位置、标题和表演者内容完全相同。所有偏好逐键摘要、恢复项 ID 和精确进度均保持不变，数据库 `quick_check=ok`。

日志并非零告警：部分已有来源书签/路径不可访问，部分 CUE 引用找不到对应音频，分别记录为 `fsevents.bookmark_resolve_failed`、`library.root.inaccessible` 和 `cue.markers.audioMissing`。这些来源配置和曲目均已保留，未执行重新挂载或重新授权；扫描汇总的 `errors=0` 不代表全部来源都可用。

本次正式环境验证启动、界面、队列显示、正常退出和恢复，没有播放或编辑真实媒体。播放、拖动及异常路径依据同一候选此前的隔离合成音频验收，见 [异步与异常路径审计](2026-10-18-async-exception-review.md)。本轮未发布 GitHub Release。

证据目录：项目根目录 `.build-logs/async-install-20261018/`。主要文件为 `acceptance.json`、`package-verification.json`、`before.json`、`after-quit.json`、`after-relaunch.json`、`formal-live.ndjson.gz` 及 `formal-*.png`；原始运行日志压缩后已解压校验 SHA-256 一致。其中包含本机曲库信息，仅作本地验收证据，不纳入发布内容。
