# VPNTrafficBar

一个轻量级原生 macOS 菜单栏应用，用于定时抓取多个 VPN/机场订阅链接的 `Subscription-Userinfo` 响应头，在本地 SQLite 中记录流量快照，并在菜单栏弹窗中直观展示**剩余流量、24 小时消耗、今日消耗与 7 天每日消耗趋势图**。

## 核心特性

- **原生菜单栏常驻**：纯 `AppKit` + `WebKit` 构建（无需 Electron / Python 运行时），菜单栏仅保留自适应深浅色的小图标，不占空间。
- **多机场聚合**：同时监控多个订阅源，支持逐个配置「是否通过本地代理（默认 `127.0.0.1:7899`）抓取」，也支持从 macOS 钥匙串读取订阅链接。
- **24 小时 & 7 天趋势推算**：本地 SQLite 持久化每次抓取的累计流量快照，即使机场后台不提供历史报表，也能自动计算过去 24 小时用量、当日用量与近 7 天每日柱状图（自动兼容月度重置清零）。
- **灵活的抓取频率**：支持 **手动 / 5 分钟 / 1 小时 / 8 小时（默认）/ 24 小时**，避免高频轮询触发服务端限流。
- **完全本地隐私**：所有订阅地址与历史数据均保存在本地 `~/Library/Application Support/VPNTrafficBar/`，不经过任何第三方服务器。

## 快速编译与运行

系统要求：macOS 14.0+，已安装 Xcode Command Line Tools（`clang`）。

```bash
chmod +x build.sh
./build.sh
open ~/Applications/VPNTrafficBar.app
```

首次打开后，点击菜单栏柱状图图标 → 右上角 **「设置」** → **「+ 添加机场」**，填入你的订阅链接即可开始监控。

## 数据存储位置

- 配置文件：`~/Library/Application Support/VPNTrafficBar/config.json`
- 快照数据库：`~/Library/Application Support/VPNTrafficBar/traffic.db`
- 应用包位置：`~/Applications/VPNTrafficBar.app`

## 许可证

[MIT](LICENSE)
