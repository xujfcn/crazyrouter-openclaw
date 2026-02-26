# Crazyrouter OpenClaw 一键部署

在 Linux 或 macOS 上一条命令部署 OpenClaw AI 网关，使用 **Crazyrouter** 作为 AI API 后端，支持 300+ 模型。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
```

或者下载后运行：

```bash
wget https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh
bash install.sh
```

## 需要准备

1. **Crazyrouter API Key** — 在 [crazyrouter.com](https://crazyrouter.com) 注册并获取
2. **Telegram Bot Token**（可选）— 在 Telegram 找 @BotFather 创建 Bot 后获取

## 安装内容

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

## 预配置模型

| Provider | 模型 |
|----------|------|
| Claude | Opus 4.6, Sonnet 4.6 |
| GPT | 5.2, 5.3 Codex, 5 Mini, 4.1, 4.1 Mini, 4o Mini |
| Gemini | 3.1 Pro, 3 Flash |
| DeepSeek | R1, V3.2 |
| 其他 | Kimi K2.5, GLM-5, Grok 4.1, MiniMax M2.1 |

## 环境变量（可选）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CRAZYROUTER_API_KEY` | 预设 API Key，跳过交互输入 | — |
| `GATEWAY_PORT` | 网关端口 | `18789` |

非交互安装示例：

```bash
CRAZYROUTER_API_KEY=sk-xxx curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
```

## 安装后管理

### Linux (systemd)

```bash
systemctl --user status openclaw    # 查看状态
journalctl --user -u openclaw -f    # 查看日志
systemctl --user restart openclaw   # 重启
systemctl --user stop openclaw      # 停止
```

### macOS (launchd)

```bash
tail -f ~/.openclaw/openclaw.log                                                    # 查看日志
launchctl stop com.crazyrouter.openclaw && launchctl start com.crazyrouter.openclaw  # 重启
launchctl stop com.crazyrouter.openclaw                                              # 停止
```

## 支持的 IM 平台

- Telegram（安装时交互式设置）
- Discord
- Slack
- 飞书
- 钉钉
- 企业微信
- QQ Bot

## 文件说明

| 文件 | 说明 |
|------|------|
| `install.sh` | 一键安装脚本 |
| `crash-guard.cjs` | TLS 崩溃防护补丁 |
| `README.md` | 本文档 |

## 系统要求

- Linux (x64/arm64) 或 macOS (x64/arm64)
- 1-2 GB 内存
- 可访问互联网
- Crazyrouter API Key

---

Powered by [Crazyrouter](https://crazyrouter.com)
