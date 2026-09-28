# 上游来源与本地开发约定

本目录从 [bocan/bocan-music](https://github.com/bocan/bocan-music) 的提交 `fdce12728354e2ca7d4352d83f0bfde946e28d34`（2026-09-28）复制，保留 [LICENSE](LICENSE) 和 [NOTICES.md](NOTICES.md)。源码采用 Apache-2.0；第三方音频库各有独立许可，见 `NOTICES.md`。

本地 WMusic 改动集中在应用标识与数据隔离、Nocturne 配色和开发入口。`Bocan` Xcode scheme 与 Swift module 名暂作源码内部标识，便于从上游合并；用户可见的候选应用名为 WMusic。本机候选不覆盖已安装的 Bòcan 或 foobar2000。

若后续同步上游，先比较新的上游提交与上述固定提交，保留 WMusic 的标识、密钥服务和主题变更，重新跑构建与界面验收。不要把 Bòcan 的更新源、签名或用户数据库直接接入 WMusic。
