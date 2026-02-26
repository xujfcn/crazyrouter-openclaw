# Crazyrouter OpenClaw 一键部署 / One-Click Deploy

[中文](#中文) | [English](#english)

---

## 中文

在 Linux 或 macOS 上一条命令部署 OpenClaw AI 网关，使用 **Crazyrouter** 作为 AI API 后端，支持 300+ 模型。

### 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
```

或者下载后运行：

```bash
wget https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh
bash install.sh
```

### 需要准备

1. **Crazyrouter API Key** — 在 [crazyrouter.com](https://crazyrouter.com) 注册并获取
2. **Telegram Bot Token**（可选）— 在 Telegram 找 @BotFather 创建 Bot 后获取

### 安装内容

脚本会自动完成以下步骤：

1. 检测系统环境（Linux/macOS, x64/arm64）
2. 安装 Node.js 22+（如未安装）
3. 安装 OpenClaw npm 包
4. 收集 API Key 并生成配置
5. 预配置 15+ 热门 AI 模型
6. 应用稳定性补丁
7. 安装 IM 插件（钉钉、企业微信、QQ Bot）
8. 配置系统服务（systemd/launchd）自动启动
9. 启动 OpenClaw 网关
10. 交互式 Telegram Bot 设置与自动配对

### 预配置模型

| Provider | 模型 |
|----------|------|
| Claude | Opus 4.6, Sonnet 4.6 |
| GPT | 5.2, 5.3 Codex, 5 Mini, 4.1, 4.1 Mini, 4o Mini |
| Gemini | 3.1 Pro, 3 Flash |
| DeepSeek | R1, V3.2 |
| 其他 | Kimi K2.5, GLM-5, Grok 4.1, MiniMax M2.1 |

### 环境变量（可选）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CRAZYROUTER_API_KEY` | 预设 API Key，跳过交互输入 | — |
| `GATEWAY_PORT` | 网关端口 | `18789` |
| `INSTALLER_LANG` | 安装语言 (`zh`/`en`) | 交互选择 |

非交互安装示例：

```bash
CRAZYROUTER_API_KEY=sk-xxx curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
```

### 安装后管理

#### Linux (systemd)

```bash
systemctl --user status openclaw    # 查看状态
journalctl --user -u openclaw -f    # 查看日志
systemctl --user restart openclaw   # 重启
systemctl --user stop openclaw      # 停止
```

#### macOS (launchd)

```bash
tail -f ~/.openclaw/openclaw.log                                                    # 查看日志
launchctl stop com.crazyrouter.openclaw && launchctl start com.crazyrouter.openclaw  # 重启
launchctl stop com.crazyrouter.openclaw                                              # 停止
```

### 支持的 IM 平台

- Telegram（安装时交互式设置）
- Discord
- Slack
- 飞书
- 钉钉
- 企业微信
- QQ Bot

### 系统要求

- Linux (x64/arm64) 或 macOS (x64/arm64)
- 1-2 GB 内存
- 可访问互联网
- Crazyrouter API Key

---

## English

Deploy an OpenClaw AI gateway on Linux or macOS with a single command, powered by **Crazyrouter** as the AI API backend with 300+ models.

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
```

Or download and run:

```bash
wget https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh
bash install.sh
```

The installer supports both Chinese and English — you'll be prompted to choose a language at startup.

### Prerequisites

1. **Crazyrouter API Key** — Sign up at [crazyrouter.com](https://crazyrouter.com)
2. **Telegram Bot Token** (optional) — Create a bot via @BotFather on Telegram

### What Gets Installed

The script automatically handles:

1. System detection (Linux/macOS, x64/arm64)
2. Node.js 22+ installation (if not present)
3. OpenClaw npm package installation
4. API key collection and config generation
5. Pre-configuration of 15+ popular AI models
6. Stability patches (TLS crash guard)
7. IM plugin installation (DingTalk, WeCom, QQ Bot)
8. System service setup (systemd/launchd) for auto-start
9. OpenClaw gateway startup
10. Interactive Telegram Bot setup with auto-pairing

### Pre-configured Models

| Provider | Models |
|----------|--------|
| Claude | Opus 4.6, Sonnet 4.6 |
| GPT | 5.2, 5.3 Codex, 5 Mini, 4.1, 4.1 Mini, 4o Mini |
| Gemini | 3.1 Pro, 3 Flash |
| DeepSeek | R1, V3.2 |
| Others | Kimi K2.5, GLM-5, Grok 4.1, MiniMax M2.1 |

### Environment Variables (Optional)

| Variable | Description | Default |
|----------|-------------|---------|
| `CRAZYROUTER_API_KEY` | Pre-set API key, skips interactive prompt | — |
| `GATEWAY_PORT` | Gateway port | `18789` |
| `INSTALLER_LANG` | Installer language (`zh`/`en`) | Interactive |

Non-interactive install example:

```bash
CRAZYROUTER_API_KEY=sk-xxx INSTALLER_LANG=en curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
```

### Post-Install Management

#### Linux (systemd)

```bash
systemctl --user status openclaw    # Check status
journalctl --user -u openclaw -f    # View logs
systemctl --user restart openclaw   # Restart
systemctl --user stop openclaw      # Stop
```

#### macOS (launchd)

```bash
tail -f ~/.openclaw/openclaw.log                                                    # View logs
launchctl stop com.crazyrouter.openclaw && launchctl start com.crazyrouter.openclaw  # Restart
launchctl stop com.crazyrouter.openclaw                                              # Stop
```

### Supported IM Platforms

- Telegram (interactive setup during install)
- Discord
- Slack
- Lark (Feishu)
- DingTalk
- WeCom (WeChat Work)
- QQ Bot

### Files

| File | Description |
|------|-------------|
| `install.sh` | One-click install script |
| `crash-guard.cjs` | TLS crash guard patch |
| `README.md` | This document |

### System Requirements

- Linux (x64/arm64) or macOS (x64/arm64)
- 1-2 GB RAM
- Internet access
- Crazyrouter API Key

---

Powered by [Crazyrouter](https://crazyrouter.com)
