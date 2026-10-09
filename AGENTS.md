# WMusic 本机发布约定

- 正式应用固定安装到 `/Applications/WMusic.app`。构建候选为 `dist/WMusic.app`，候选完成验收后通过 `script/install_local_app.sh` 安装。
- 唯一回滚目录为 `.build-logs/install-backups/current-rollback/`，包含上一正式版 `WMusic.app` 和安装前的 `library.sqlite`。成功安装后才轮换回滚；构建阶段不累积历史成品。此约定由用户于 2026-10-01 明确要求。
- 更新时先核对正式应用与运行进程，正常退出后安装；安装前验证候选签名、身份与沙盒，安装后核对完整文件摘要和实际界面。图标更新还需检查 Dock 的实际显示。
- 保留真实曲库、播放列表、队列和播放历史。真实数据库位于 `~/Library/Containers/com.willhsu.wmusic.local/Data/Library/Application Support/WMusic/library.sqlite`；播放行为验收使用独立 QA 沙盒和合成音频。
- 发布到 GitHub 前，源码、历史提交、版本标签和 Release 附件都需检查 NAS 地址。文档及界面只使用设备名占位示例；地址解析测试使用专用文档测试网段，不得写入真实内网、Tailscale 或个人服务器地址。执行 `python3 script/check_publish_privacy.py --history` 检查。
