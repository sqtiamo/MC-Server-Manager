# MC Server Manager ｜ MC 服务器管理器

> **English** | [中文](#中文说明)

A single-file Windows app to deploy, start, and manage Minecraft servers (Fabric / Forge / NeoForge / Vanilla) with frp tunneling, so players can join via your cloud server IP — no programming required.

一个 Windows 单文件应用：一键部署、启动、管理 Minecraft 服务器（Fabric / Forge / NeoForge / 原版），并通过 frp 内网穿透让玩家用云服务器 IP 进服，全程图形界面、无需写代码。

---

## English

### Features

- **One-click deploy**: import a server pack `.zip`, auto-extract, accept EULA, generate default config, copy authlib-injector, and generate frp tunnel config
- **Start / Stop / Restart**: auto-match the right Java version (8 / 17 / 21), run in background, follow logs in the built-in console
- **Quick config**: edit `server.properties` from a GUI (difficulty, gamemode, port, PvP, whitelist, online-mode, and more)
- **Player management**: add/remove whitelist and OP (via RCON or direct file editing)
- **Mod management**: view and enable/disable mods
- **Multiple server profiles**: save settings per server and switch instantly
- **Auth modes**: official (online) / third-party login via authlib-injector (Redstone Skin Station, LittleSkin, or custom Yggdrasil API), plus offline mode; generate `run.bat` accordingly
- **frp tunneling**: manage frpc, forward game TCP + voice UDP ports; one-click frps install script for your cloud server
- **SSH upload**: send and execute scripts on your cloud server (e.g., `install-frps.sh`) with configurable frp auth token

### Quick start

Option A — download the prebuilt `MCServerManager.exe` from the `outputs/` folder in this repo, double-click to run (no install needed).

Option B — build it yourself:

```powershell
powershell -ExecutionPolicy Bypass -File build-exe.ps1
```

Option C — run from source:

```powershell
powershell -ExecutionPolicy Bypass -File mc-server-manager.ps1
```

### Typical flow

1. In **Deploy from Scratch** tab: pick the server pack zip, enter MC version, cloud server IP / frp token / ports, click deploy
2. In **Overview** tab: pick the server profile, check Java, choose auth mode, start the server
3. Start frpc in the **frp** tab (or it starts automatically during deploy)
4. Players join at `YOUR_CLOUD_IP:PORT`

> On the cloud server, install frps via `install-frps.sh` and open the frp / game / voice ports in ufw and the cloud firewall.

### Files

| File | Description |
| --- | --- |
| `mc-server-manager.ps1` | Main app (PowerShell + WinForms) |
| `MCServerManagerWrapper.cs` | C# launcher (executes the embedded script in-process) |
| `build-exe.ps1` | Builds the single-file exe with csc.exe |
| `install-frps.sh` | One-click frps installer for Ubuntu/Debian cloud servers |
| `setup-local.ps1` / `setup-spark.ps1` | Earlier deploy scripts (example packs) |
| `deploy-train-werewolf.sh` | Cloud-side deploy script example |
| `rcon.py` | RCON command-line debug tool |

### Tech notes

- Pure PowerShell 5.1 + WinForms, no third-party dependencies
- The exe embeds a gzip+base64 compressed copy of the script and runs it in-process with the PowerShell engine (no temp scripts, less antivirus noise)
- RCON protocol is implemented from scratch; offline whitelist/OP file writes supported
- Auto-detects Fabric / Forge / NeoForge / Vanilla servers and picks the right Java

### Disclaimer

For personal server management and learning. All mods / modpacks belong to their respective authors.

---

<a name="中文说明"></a>

## 中文说明

### 功能

- **一键部署**：导入整合包 zip，自动解压、同意 EULA、生成默认配置、复制皮肤登录文件、生成 frpc 穿透配置
- **启动 / 停止 / 重启**：自动匹配对应 Java（8 / 17 / 21），后台运行，内置控制台看日志
- **快速配置**：图形化修改 server.properties（难度、游戏模式、端口、PvP、白名单、在线模式等）
- **玩家管理**：白名单 / OP 添加与移除（支持 RCON 与离线文件写入）
- **模组管理**：查看 / 启用 / 禁用模组
- **多服务器档案**：每台服务器的设置独立保存，下拉框秒切
- **登录方式**：官方正版 / 第三方 authlib-injector（红石皮肤站、LittleSkin、自定义 Yggdrasil 地址）/ 离线模式，并可一键生成对应 run.bat
- **内网穿透**：管理 frpc，转发游戏 TCP + 语音 UDP 端口；提供云服务器一键装 frps 的脚本
- **SSH 上传**：把脚本传到云服务器并执行（如 install-frps.sh），可自定义 frp 认证密码
- **运行状态查询**：一键查看当前运行的 MC 服务器和 frpc 分别属于哪个服务器档案

### 快速开始

方式一：从本仓库 `outputs/` 文件夹下载 `MCServerManager.exe`，直接双击运行（免安装）。

方式二：自己打包 exe：

```powershell
powershell -ExecutionPolicy Bypass -File build-exe.ps1
```

方式三：从源码运行：

```powershell
powershell -ExecutionPolicy Bypass -File mc-server-manager.ps1
```

### 典型开服流程

1. 「从零部署」页：选整合包 zip、填 Minecraft 版本、云服务器 IP / frp 密码 / 端口，点一键部署
2. 「总览 / 启动」页：选服务器档案、确认 Java、选登录方式，点启动服务器
3. 「内网穿透」页启动 frpc（部署时也可自动启动）
4. 玩家连接地址 = 云服务器IP:游戏端口

> 云服务器需先运行 `install-frps.sh` 安装 frps，并在 ufw 和云防火墙放行 frp、游戏、语音端口。

### 文件说明

| 文件 | 说明 |
| --- | --- |
| `mc-server-manager.ps1` | 应用主程序（PowerShell + WinForms） |
| `MCServerManagerWrapper.cs` | C# 启动器（进程内执行内嵌脚本） |
| `build-exe.ps1` | exe 打包脚本（csc.exe） |
| `install-frps.sh` | 云服务器一键安装 frps 脚本 |
| `setup-local.ps1` / `setup-spark.ps1` | 早期部署脚本（示例整合包） |
| `deploy-train-werewolf.sh` | 云服务端部署脚本示例 |
| `rcon.py` | RCON 命令行调试工具 |

### 技术要点

- 纯 PowerShell 5.1 + WinForms，无第三方依赖
- exe 内嵌 gzip+base64 压缩脚本，运行时用 PowerShell 引擎进程内执行，不生成临时脚本、较少被杀毒误报
- RCON 协议自实现；支持离线直接写白名单 / OP 文件
- 自动识别 Fabric / Forge / NeoForge / 原版服务端并匹配 Java 版本

### 免责声明

本项目仅用于个人服务器管理与学习。模组、整合包版权归各自作者所有。

---

## License

MIT
