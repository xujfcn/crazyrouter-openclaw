#!/usr/bin/env bash
# ============================================================
# Crazyrouter OpenClaw — 一键部署脚本
# ============================================================
# 在 Linux (Ubuntu/Debian/CentOS/RHEL) 和 macOS 上一键安装
# OpenClaw，使用 Crazyrouter 作为 AI API 后端。
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
#   # 或
#   bash install.sh
#
# 要求:
#   - Linux (x64/arm64) 或 macOS (x64/arm64)
#   - 可访问互联网
#   - Crazyrouter API Key (在 https://crazyrouter.com 获取)
# ============================================================
set -euo pipefail

# --- 管道安全引导 (macOS bash 3.2 逐行读取 stdin) ---
# 通过 `curl ... | bash` 管道执行时，保存到临时文件并重新执行。
# 将 stdin 重定向到 /dev/tty 以便子进程可以进行交互式读取。
if [ ! -t 0 ] && [ -z "${_CRAZYROUTER_REEXEC:-}" ]; then
  _tmp=$(mktemp "${TMPDIR:-/tmp}/crazyrouter-install.XXXXXX")
  cat > "$_tmp"
  export _CRAZYROUTER_REEXEC=1
  bash "$_tmp" "$@" < /dev/tty
  _rc=$?
  rm -f "$_tmp"
  exit $_rc
fi

# --- 常量 ---
OPENCLAW_VERSION="latest"
API_BASE_URL="https://crazyrouter.com/v1"
API_NATIVE_URL="https://crazyrouter.com"
DEFAULT_MODEL="claude-sonnet-4-6"
GATEWAY_PORT=18789
MIN_NODE_MAJOR=22
TOTAL_STEPS=10

CRASH_GUARD_URL="https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/crash-guard.cjs"

# IM 插件包
PLUGIN_DINGTALK="@adongguo/dingtalk"
PLUGIN_WECOM="@marshulll/openclaw-wecom"
PLUGIN_QQBOT="@sliverp/qqbot"

# --- 颜色与样式 ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
error() { echo -e "  ${RED}✗${NC} $*" >&2; }
fatal() { error "$*"; exit 1; }

# --- 加载动画 ---
SPINNER_PID=""
spin() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local msg="$1"; local i=0
  while true; do
    printf "\r  ${CYAN}${frames[$i]}${NC} ${DIM}%s${NC}" "$msg"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.08
  done
}
spin_start() { spin "$1" & SPINNER_PID=$!; }
spin_stop()  {
  if [ -n "$SPINNER_PID" ]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  printf "\r\033[K"
}
trap 'spin_stop' EXIT

# --- 步骤进度条 ---
CURRENT_STEP=0
step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
  local filled=$(( pct / 5 ))
  local empty=$(( 20 - filled ))
  local bar="${GREEN}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  bar+="${DIM}"
  for ((i=0; i<empty; i++)); do bar+="░"; done
  bar+="${NC}"
  echo ""
  echo -e "  ${BOLD}[$CURRENT_STEP/$TOTAL_STEPS]${NC} $1  ${bar} ${DIM}${pct}%${NC}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..48})${NC}"
}

# --- ASCII Art Banner ---
show_banner() {
  echo ""
  echo -e "${CYAN}"
  cat << 'BANNER'
    ╔═╗╦═╗╔═╗╔═╗╦ ╦╦═╗╔═╗╦ ╦╔╦╗╔═╗╦═╗
    ║  ╠╦╝╠═╣╔═╝╚╦╝╠╦╝║ ║║ ║ ║ ║╣ ╠╦╝
    ╚═╝╩╚═╩ ╩╚═╝ ╩ ╩╚═╚═╝╚═╝ ╩ ╚═╝╩╚═
BANNER
  echo -e "${NC}"
  echo -e "    ${BOLD}OpenClaw${NC} ${DIM}— 自托管 AI 网关${NC}"
  echo -e "    ${DIM}$(printf '%.0s─' {1..40})${NC}"
  echo ""
}

# ============================================================
# 步骤 1: 环境检测
# ============================================================
show_banner
step "检测运行环境"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  OS_TYPE="linux" ;;
  Darwin) OS_TYPE="macos" ;;
  *)      fatal "不支持的操作系统: $OS (仅支持 Linux 和 macOS)" ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_TYPE="x64" ;;
  aarch64|arm64) ARCH_TYPE="arm64" ;;
  *)             fatal "不支持的架构: $ARCH" ;;
esac

info "系统: ${BOLD}$OS_TYPE/$ARCH_TYPE${NC}"

# 端口冲突检测
if command -v lsof &>/dev/null; then
  if lsof -i ":$GATEWAY_PORT" &>/dev/null; then
    warn "端口 $GATEWAY_PORT 已被占用 — OpenClaw 可能无法启动"
  fi
elif command -v ss &>/dev/null; then
  if ss -tlnp | grep -q ":$GATEWAY_PORT " 2>/dev/null; then
    warn "端口 $GATEWAY_PORT 已被占用 — OpenClaw 可能无法启动"
  fi
fi

# ============================================================
# 步骤 2: 安装 Node.js (如需要)
# ============================================================
step "检查 Node.js"

install_node_linux() {
  if command -v apt-get &>/dev/null; then
    spin_start "通过 NodeSource (apt) 安装 Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y nodejs >/dev/null 2>&1
    spin_stop
  elif command -v dnf &>/dev/null; then
    spin_start "通过 NodeSource (dnf) 安装 Node.js 22..."
    curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo dnf install -y nodejs >/dev/null 2>&1
    spin_stop
  elif command -v yum &>/dev/null; then
    spin_start "通过 NodeSource (yum) 安装 Node.js 22..."
    curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo yum install -y nodejs >/dev/null 2>&1
    spin_stop
  else
    fatal "未找到支持的包管理器 (apt/dnf/yum)。请手动安装 Node.js 22+。"
  fi
}

install_node_macos() {
  if command -v brew &>/dev/null; then
    spin_start "通过 Homebrew 安装 Node.js 22..."
    brew install node@22 >/dev/null 2>&1
    brew link --overwrite node@22 2>/dev/null || true
    spin_stop
  else
    fatal "未找到 Homebrew。请手动安装 Node.js 22+: https://nodejs.org"
  fi
}

NEED_NODE=false
if command -v node &>/dev/null; then
  NODE_VER=$(node -v | sed 's/^v//' | cut -d. -f1)
  if [ "$NODE_VER" -lt "$MIN_NODE_MAJOR" ]; then
    warn "检测到 Node.js v$(node -v)，但需要 v22+"
    NEED_NODE=true
  else
    info "Node.js $(node -v) 已就绪"
  fi
else
  warn "未检测到 Node.js"
  NEED_NODE=true
fi

if [ "$NEED_NODE" = true ]; then
  case "$OS_TYPE" in
    linux) install_node_linux ;;
    macos) install_node_macos ;;
  esac
  command -v node &>/dev/null || fatal "Node.js 安装失败"
  info "Node.js $(node -v) 安装完成"
fi

# ============================================================
# 步骤 3: 安装 OpenClaw
# ============================================================
step "安装 OpenClaw"

# 如已安装且为最新版则跳过
SKIP_OPENCLAW=false
if command -v openclaw &>/dev/null; then
  EXISTING_VER=$(openclaw --version 2>/dev/null || echo "")
  if [ -n "$EXISTING_VER" ]; then
    info "OpenClaw ${BOLD}$EXISTING_VER${NC} 已安装 — 跳过"
    SKIP_OPENCLAW=true
  fi
fi

if [ "$SKIP_OPENCLAW" = false ]; then
  spin_start "npm install -g openclaw@${OPENCLAW_VERSION}..."
  npm install -g "openclaw@${OPENCLAW_VERSION}" >/dev/null 2>&1
  spin_stop

  if ! command -v openclaw &>/dev/null; then
    NPM_BIN=$(npm bin -g 2>/dev/null || echo "")
    if [ -n "$NPM_BIN" ] && [ -x "$NPM_BIN/openclaw" ]; then
      export PATH="$NPM_BIN:$PATH"
    fi
  fi
  command -v openclaw &>/dev/null || fatal "OpenClaw 安装失败，请检查 npm 权限。"
  OPENCLAW_VER=$(openclaw --version 2>/dev/null || echo "unknown")
  info "OpenClaw ${BOLD}$OPENCLAW_VER${NC} 安装完成"
fi

# 查找 OpenClaw 安装目录
OPENCLAW_ROOT=$(node -e "console.log(require.resolve('openclaw/package.json').replace('/package.json',''))" 2>/dev/null || echo "")
if [ -z "$OPENCLAW_ROOT" ]; then
  OPENCLAW_ROOT=$(npm root -g)/openclaw
fi
info "安装路径: ${DIM}$OPENCLAW_ROOT${NC}"

# ============================================================
# 步骤 4: 用户配置
# ============================================================
step "配置信息"

# API Key
if [ -n "${CRAZYROUTER_API_KEY:-}" ]; then
  API_KEY="$CRAZYROUTER_API_KEY"
  info "使用环境变量中的 API Key"
elif [ -f "$HOME/.openclaw/openclaw.json" ]; then
  EXISTING_KEY=$(node -e "const c=JSON.parse(require('fs').readFileSync('$HOME/.openclaw/openclaw.json','utf8'));console.log(c.models?.providers?.crazyrouter?.apiKey||c.models?.providers?.['crazyrouter-claude']?.apiKey||c.env?.vars?.OPENAI_API_KEY||'')" 2>/dev/null || echo "")
  if [ -n "$EXISTING_KEY" ]; then
    API_KEY="$EXISTING_KEY"
    info "使用已有配置中的 API Key: ${DIM}${API_KEY:0:10}...${API_KEY: -4}${NC}"
  fi
fi

if [ -z "${API_KEY:-}" ]; then
  if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
    fatal "无法获取用户输入。请先设置环境变量:\n  ${BOLD}CRAZYROUTER_API_KEY=sk-xxx curl -fsSL ... | bash${NC}"
  fi
  echo ""
  echo -e "  请输入你的 Crazyrouter API Key ${DIM}(在 ${BOLD}https://crazyrouter.com${NC}${DIM} 获取)${NC}"
  echo -ne "  ${CYAN}▸${NC} API Key (sk-xxx): "
  read -r API_KEY < /dev/tty || fatal "读取输入失败。请改用环境变量 CRAZYROUTER_API_KEY。"
  [ -z "$API_KEY" ] && fatal "API Key 不能为空"
fi

# 验证 API Key 格式
[[ "$API_KEY" == sk-* ]] || warn "API Key 不以 'sk-' 开头 — 请确认是否正确"

# 生成网关 Token
GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")

echo ""
info "API Key: ${DIM}${API_KEY:0:10}...${API_KEY: -4}${NC}"
info "默认模型: ${BOLD}$DEFAULT_MODEL${NC}"
info "网关端口: ${BOLD}$GATEWAY_PORT${NC}"

# ============================================================
# 步骤 5: 生成配置文件
# ============================================================
step "生成配置文件"

CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
mkdir -p "$CONFIG_DIR"

# 如已存在配置则询问是否覆盖
SKIP_CONFIG=false
if [ -f "$CONFIG_FILE" ]; then
  echo -ne "  配置文件已存在，是否覆盖？ ${DIM}[y/N]${NC} "
  read -r OVERWRITE_CFG < /dev/tty || OVERWRITE_CFG="n"
  OVERWRITE_CFG="${OVERWRITE_CFG:-n}"
  if [[ "$OVERWRITE_CFG" =~ ^[Yy]$ ]]; then
    BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    warn "已备份到 ${DIM}$BACKUP_FILE${NC}"
  else
    info "保留现有配置 — 跳过"
    SKIP_CONFIG=true
    GATEWAY_TOKEN=$(node -e "const c=JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));console.log(c.gateway?.auth?.token||'unknown')" 2>/dev/null || echo "unknown")
  fi
fi

if [ "$SKIP_CONFIG" = false ]; then

# 确定模型 provider 前缀
case "$DEFAULT_MODEL" in
  claude-*)  MODEL_PROVIDER="crazyrouter-claude" ;;
  minimax-*) MODEL_PROVIDER="crazyrouter-minimax" ;;
  *)         MODEL_PROVIDER="crazyrouter" ;;
esac

spin_start "写入 openclaw.json..."

cat > "$CONFIG_FILE" << JSONEOF
{
  "models": {
    "mode": "replace",
    "providers": {
      "crazyrouter-minimax": {
        "baseUrl": "${API_NATIVE_URL}",
        "apiKey": "${API_KEY}",
        "api": "anthropic-messages",
        "models": [
          {
            "id": "minimax-m2.1", "name": "MiniMax M2.1", "reasoning": true,
            "input": ["text"], "contextWindow": 200000, "maxTokens": 8192,
            "cost": { "input": 15, "output": 60, "cacheRead": 2, "cacheWrite": 10 }
          }
        ]
      },
      "crazyrouter-claude": {
        "baseUrl": "${API_NATIVE_URL}",
        "apiKey": "${API_KEY}",
        "api": "anthropic-messages",
        "models": [
          {
            "id": "claude-opus-4-6", "name": "Claude Opus 4.6", "reasoning": true,
            "input": ["text", "image"], "contextWindow": 200000, "maxTokens": 32000,
            "cost": { "input": 15, "output": 75, "cacheRead": 1.5, "cacheWrite": 18.75 }
          },
          {
            "id": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6", "reasoning": true,
            "input": ["text", "image"], "contextWindow": 200000, "maxTokens": 64000,
            "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 3.75 }
          }
        ]
      },
      "crazyrouter": {
        "baseUrl": "${API_BASE_URL}",
        "apiKey": "${API_KEY}",
        "api": "openai-completions",
        "models": [
          { "id": "gpt-5.2", "name": "GPT-5.2", "reasoning": true, "input": ["text", "image"], "contextWindow": 256000, "maxTokens": 32000, "cost": { "input": 2.5, "output": 10, "cacheRead": 0.5, "cacheWrite": 2.5 } },
          { "id": "gpt-5.3-codex", "name": "GPT-5.3 Codex", "reasoning": true, "input": ["text", "image"], "contextWindow": 256000, "maxTokens": 32000, "cost": { "input": 2.5, "output": 10, "cacheRead": 0.5, "cacheWrite": 2.5 } },
          { "id": "gpt-5-mini", "name": "GPT-5 Mini", "reasoning": false, "input": ["text", "image"], "contextWindow": 128000, "maxTokens": 16384, "cost": { "input": 0.15, "output": 0.6, "cacheRead": 0.015, "cacheWrite": 0.15 } },
          { "id": "gpt-4.1", "name": "GPT-4.1", "reasoning": false, "input": ["text", "image"], "contextWindow": 1047576, "maxTokens": 32768, "cost": { "input": 2, "output": 8, "cacheRead": 0.5, "cacheWrite": 2 } },
          { "id": "gpt-4.1-mini", "name": "GPT-4.1 Mini", "reasoning": false, "input": ["text", "image"], "contextWindow": 1047576, "maxTokens": 32768, "cost": { "input": 0.4, "output": 1.6, "cacheRead": 0.1, "cacheWrite": 0.4 } },
          { "id": "gpt-4o-mini", "name": "GPT-4o Mini", "reasoning": false, "input": ["text", "image"], "contextWindow": 128000, "maxTokens": 16384, "cost": { "input": 0.15, "output": 0.6, "cacheRead": 0.075, "cacheWrite": 0.15 } },
          { "id": "gemini-3.1-pro-preview", "name": "Gemini 3.1 Pro", "reasoning": true, "input": ["text", "image"], "contextWindow": 1048576, "maxTokens": 65536, "cost": { "input": 2, "output": 12, "cacheRead": 0.2, "cacheWrite": 2 } },
          { "id": "gemini-3-flash-preview", "name": "Gemini 3 Flash", "reasoning": false, "input": ["text", "image"], "contextWindow": 1048576, "maxTokens": 65536, "cost": { "input": 0.15, "output": 0.6, "cacheRead": 0.0375, "cacheWrite": 0.15 } },
          { "id": "deepseek-r1", "name": "DeepSeek R1", "reasoning": true, "input": ["text"], "contextWindow": 128000, "maxTokens": 8192, "cost": { "input": 0.55, "output": 2.19, "cacheRead": 0.14, "cacheWrite": 0.55 } },
          { "id": "deepseek-v3-2", "name": "DeepSeek V3.2", "reasoning": false, "input": ["text"], "contextWindow": 128000, "maxTokens": 8192, "cost": { "input": 0.27, "output": 1.1, "cacheRead": 0.07, "cacheWrite": 0.27 } },
          { "id": "kimi-k2.5", "name": "Kimi K2.5", "reasoning": false, "input": ["text"], "contextWindow": 256000, "maxTokens": 8192, "cost": { "input": 0.6, "output": 3, "cacheRead": 0.1, "cacheWrite": 0.6 } },
          { "id": "glm-5", "name": "GLM-5", "reasoning": true, "input": ["text"], "contextWindow": 200000, "maxTokens": 128000, "cost": { "input": 1, "output": 3.2 } },
          { "id": "grok-4.1", "name": "Grok 4.1", "reasoning": true, "input": ["text", "image"], "contextWindow": 256000, "maxTokens": 16384, "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 3 } }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "${MODEL_PROVIDER}/${DEFAULT_MODEL}" },
      "imageModel": {
        "primary": "crazyrouter/gemini-3-flash-preview",
        "fallbacks": ["crazyrouter/gpt-4o-mini"]
      },
      "memorySearch": {
        "remote": { "baseUrl": "${API_BASE_URL}", "apiKey": "${API_KEY}" }
      }
    }
  },
  "session": {
    "reset": { "mode": "idle", "idleMinutes": 10080 },
    "resetByType": {
      "direct": { "mode": "idle", "idleMinutes": 10080 },
      "group": { "mode": "idle", "idleMinutes": 4320 }
    }
  },
  "gateway": {
    "mode": "local",
    "port": ${GATEWAY_PORT},
    "bind": "lan",
    "auth": { "mode": "token", "token": "${GATEWAY_TOKEN}" },
    "controlUi": { "allowInsecureAuth": true, "dangerouslyDisableDeviceAuth": true, "dangerouslyAllowHostHeaderOriginFallback": true }
  },
  "env": {
    "vars": {
      "OPENAI_API_KEY": "${API_KEY}",
      "OPENAI_TTS_BASE_URL": "${API_BASE_URL}"
    }
  },
  "skills": { "entries": { "openai-image-gen": { "enabled": false } } },
  "plugins": {
    "entries": {
      "telegram": { "enabled": true },
      "dingtalk": { "enabled": true },
      "openclaw-wecom": { "enabled": true },
      "qqbot": { "enabled": true },
      "discord": { "enabled": true },
      "slack": { "enabled": true },
      "feishu": { "enabled": true },
      "msteams": { "enabled": false },
      "whatsapp": { "enabled": false },
      "signal": { "enabled": false },
      "matrix": { "enabled": false },
      "line": { "enabled": false },
      "googlechat": { "enabled": false },
      "mattermost": { "enabled": false },
      "irc": { "enabled": false },
      "imessage": { "enabled": false },
      "bluebubbles": { "enabled": false },
      "nostr": { "enabled": false },
      "nextcloud-talk": { "enabled": false },
      "synology-chat": { "enabled": false },
      "twitch": { "enabled": false },
      "tlon": { "enabled": false },
      "zalo": { "enabled": false },
      "zalouser": { "enabled": false }
    }
  },
  "commands": { "native": "auto", "nativeSkills": "auto", "restart": true },
  "tools": {
    "media": {
      "audio": { "enabled": true, "models": [
        { "provider": "openai", "model": "whisper-large-v3", "baseUrl": "${API_BASE_URL}" },
        { "provider": "openai", "model": "whisper-1", "baseUrl": "${API_BASE_URL}" }
      ]},
      "image": { "enabled": true, "models": [
        { "provider": "openai", "model": "gemini-3-flash-preview", "baseUrl": "${API_BASE_URL}" },
        { "provider": "openai", "model": "gpt-4o-mini", "baseUrl": "${API_BASE_URL}" }
      ]}
    }
  }
}
JSONEOF

spin_stop
info "配置文件已生成: ${DIM}$CONFIG_FILE${NC}"

fi # end SKIP_CONFIG

# 创建必要目录
mkdir -p "$CONFIG_DIR/agents/main/sessions"

# ============================================================
# 步骤 6: 应用补丁
# ============================================================
step "应用补丁"

# 补丁: 禁用 Opus 4.6 的 adaptive thinking
# Adaptive thinking 会导致 Opus 将整个回复放在 thinking block 中，
# 导致文本输出为空。基于 budget 的 thinking 可以正常工作。
ANTHROPIC_JS=$(find "$OPENCLAW_ROOT" -path "*/pi-ai/dist/providers/anthropic.js" 2>/dev/null | head -1)
if [ -n "$ANTHROPIC_JS" ]; then
  if grep -q 'opus-4-6\|opus-4\.6' "$ANTHROPIC_JS" 2>/dev/null; then
    cp "$ANTHROPIC_JS" "${ANTHROPIC_JS}.bak"
    if [[ "$OS_TYPE" == "macos" ]]; then
      sed -i '' 's/return modelId.includes("opus-4-6") || modelId.includes("opus-4.6");/return false;/' "$ANTHROPIC_JS"
      sed -i '' 's/return modelId.includes("opus-4-6");/return false;/' "$ANTHROPIC_JS"
    else
      sed -i 's/return modelId.includes("opus-4-6") || modelId.includes("opus-4.6");/return false;/' "$ANTHROPIC_JS"
      sed -i 's/return modelId.includes("opus-4-6");/return false;/' "$ANTHROPIC_JS"
    fi
    if grep -q 'return false;' "$ANTHROPIC_JS"; then
      info "Opus 4.6 adaptive thinking 补丁已应用"
    else
      warn "补丁可能未生效 — 恢复备份"
      cp "${ANTHROPIC_JS}.bak" "$ANTHROPIC_JS"
    fi
    rm -f "${ANTHROPIC_JS}.bak"
  else
    info "Adaptive thinking 已修补或不存在"
  fi
else
  warn "未找到 pi-ai anthropic.js — 跳过 adaptive thinking 补丁"
fi

# 下载 crash-guard.cjs
CRASH_GUARD_FILE="$CONFIG_DIR/crash-guard.cjs"
spin_start "下载 crash-guard.cjs..."
if curl -fsSL "$CRASH_GUARD_URL" -o "$CRASH_GUARD_FILE" 2>/dev/null; then
  spin_stop
  info "crash-guard.cjs 已下载"
else
  spin_stop
  warn "下载 crash-guard.cjs 失败 — 创建最小版本"
  cat > "$CRASH_GUARD_FILE" << 'CGEOF'
'use strict';
const tls = require('tls');
const orig = tls.TLSSocket.prototype.setSession;
if (orig) tls.TLSSocket.prototype.setSession = function(s) { if (!s || !this._handle) return; return orig.call(this, s); };
const oc = tls.connect; tls.connect = function(...a) { if (a[0]?.session) delete a[0].session; return oc.apply(tls, a); };
process.on('uncaughtException', e => { if ((e?.message||'').includes("'setSession'") && (e?.stack||'').includes('undici')) return; throw e; });
CGEOF
fi

# ============================================================
# 步骤 7: 安装 IM 插件
# ============================================================
step "安装 IM 插件"

EXTENSIONS_DIR="$OPENCLAW_ROOT/extensions"
if [ ! -d "$EXTENSIONS_DIR" ]; then
  EXTENSIONS_DIR="$CONFIG_DIR/extensions"
fi

# 如插件已安装则跳过
if [ -d "$EXTENSIONS_DIR/dingtalk" ] && [ -d "$EXTENSIONS_DIR/wecom" ] && [ -d "$EXTENSIONS_DIR/qqbot" ]; then
  info "IM 插件已安装 — 跳过"
else
  mkdir -p "$EXTENSIONS_DIR"

install_plugin() {
  local pkg="$1"
  local dir="$2"
  local keep_nm="${3:-no}"

  spin_start "安装 $dir..."
  mkdir -p "$EXTENSIONS_DIR/$dir"
  local tgz
  tgz=$(cd /tmp && npm pack "$pkg" --pack-destination /tmp 2>/dev/null | tail -1)
  if [ -z "$tgz" ] || [ ! -f "/tmp/$tgz" ]; then
    spin_stop
    warn "$dir 安装失败 (npm pack)"
    return 1
  fi
  tar xzf "/tmp/$tgz" -C "$EXTENSIONS_DIR/$dir" --strip-components=1 2>/dev/null
  rm -f "/tmp/$tgz"

  # 修复 manifest 命名
  if [ -f "$EXTENSIONS_DIR/$dir/clawdbot.plugin.json" ] && [ ! -f "$EXTENSIONS_DIR/$dir/openclaw.plugin.json" ]; then
    cp "$EXTENSIONS_DIR/$dir/clawdbot.plugin.json" "$EXTENSIONS_DIR/$dir/openclaw.plugin.json"
  fi
  if [ ! -f "$EXTENSIONS_DIR/$dir/openclaw.plugin.json" ]; then
    echo "{\"id\":\"$dir\",\"channels\":[\"$dir\"],\"configSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{}}}" \
      > "$EXTENSIONS_DIR/$dir/openclaw.plugin.json"
  fi

  if [ "$keep_nm" != "yes" ]; then
    rm -rf "$EXTENSIONS_DIR/$dir/node_modules"
  fi
  spin_stop
  info "$dir 已安装"
}

install_plugin "$PLUGIN_DINGTALK" "dingtalk" "no"
# dingtalk 需要 dingtalk-stream 依赖
spin_start "安装 dingtalk-stream 依赖..."
(cd "$EXTENSIONS_DIR/dingtalk" && npm install --omit=dev --no-package-lock --ignore-scripts dingtalk-stream >/dev/null 2>&1) || warn "dingtalk-stream 安装失败"
spin_stop

install_plugin "$PLUGIN_WECOM" "wecom" "yes"
install_plugin "$PLUGIN_QQBOT" "qqbot" "no"
info "所有 IM 插件就绪"
fi # end plugins skip

# --- 创建自动配对脚本 ---
# 自动批准每个渠道的第一个配对请求（第一个用户 = 所有者）。
AUTO_PAIR_SCRIPT="$CONFIG_DIR/auto-pair.cjs"
cat > "$AUTO_PAIR_SCRIPT" << 'APEOF'
'use strict';
const fs = require('fs');
const path = require('path');
const CRED_DIR = path.join(process.env.HOME, '.openclaw', 'credentials');
const CHANNELS = ['telegram','discord','slack','feishu','dingtalk',
  'openclaw-wecom','whatsapp','signal','line','googlechat',
  'mattermost','irc','msteams','twitch'];

function tryApprove(channel) {
  const sentinel = path.join(CRED_DIR, `.${channel}-owner-paired`);
  if (fs.existsSync(sentinel)) return true;
  const pairingFile = path.join(CRED_DIR, `${channel}-pairing.json`);
  const allowFile = path.join(CRED_DIR, `${channel}-allowFrom.json`);
  try {
    if (!fs.existsSync(pairingFile)) return false;
    const store = JSON.parse(fs.readFileSync(pairingFile, 'utf8'));
    const reqs = store.requests || [];
    if (reqs.length === 0) return false;
    const req = reqs[0];
    const id = String(req.id);
    let allow = { version: 1, allowFrom: [] };
    try { allow = JSON.parse(fs.readFileSync(allowFile, 'utf8')); } catch {}
    if (!Array.isArray(allow.allowFrom)) allow.allowFrom = [];
    if (!allow.allowFrom.includes(id)) {
      allow.allowFrom.push(id);
      fs.writeFileSync(allowFile, JSON.stringify(allow, null, 2));
    }
    store.requests = reqs.filter(r => r.id !== req.id);
    fs.writeFileSync(pairingFile, JSON.stringify(store, null, 2));
    fs.mkdirSync(CRED_DIR, { recursive: true });
    fs.writeFileSync(sentinel, JSON.stringify({
      pairedAt: new Date().toISOString(), userId: id, channel, meta: req.meta || {}
    }, null, 2));
    console.log(`自动配对 ${channel} 所有者: ${id}`);
    return true;
  } catch { return false; }
}

function checkAll() {
  return CHANNELS.every(ch => {
    const s = path.join(CRED_DIR, `.${ch}-owner-paired`);
    return fs.existsSync(s) || tryApprove(ch);
  });
}

if (checkAll()) process.exit(0);
fs.mkdirSync(CRED_DIR, { recursive: true });
let debounce = null;
const watcher = fs.watch(CRED_DIR, () => {
  if (debounce) return;
  debounce = setTimeout(() => {
    debounce = null;
    if (checkAll()) { watcher.close(); process.exit(0); }
  }, 500);
});
setInterval(() => {
  if (checkAll()) { watcher.close(); process.exit(0); }
}, 60000);
APEOF
info "自动配对脚本已创建"

# ============================================================
# 步骤 8: 配置系统服务
# ============================================================
step "配置系统服务"

OPENCLAW_CMD=$(command -v openclaw)
NODE_CMD=$(command -v node)

# 创建启动脚本（启动 auto-pair + gateway）
LAUNCHER="$CONFIG_DIR/start-gateway.sh"
cat > "$LAUNCHER" << LAUNCHEOF
#!/bin/bash
set -euo pipefail

# 通过 nvm（如可用）或 PATH 解析 Node
if [ -s "\$HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="\$HOME/.nvm"
  . "\$NVM_DIR/nvm.sh"
fi

NODE_CMD=\$(command -v node 2>/dev/null || echo "")
if [ -z "\$NODE_CMD" ]; then
  echo "[launcher] 错误: 未找到 node" >&2; exit 1
fi
echo "[launcher] Node: \$NODE_CMD (\$(\$NODE_CMD -v))"

# 解析 OpenClaw 根目录
OPENCLAW_ROOT=\$("\$NODE_CMD" -e "console.log(require.resolve('openclaw/package.json').replace('/package.json',''))" 2>/dev/null || echo "")
if [ -z "\$OPENCLAW_ROOT" ] || [ ! -f "\$OPENCLAW_ROOT/dist/index.js" ]; then
  NPM_GLOBAL=\$(npm root -g 2>/dev/null || echo "")
  if [ -n "\$NPM_GLOBAL" ] && [ -f "\$NPM_GLOBAL/openclaw/dist/index.js" ]; then
    OPENCLAW_ROOT="\$NPM_GLOBAL/openclaw"
  fi
fi
if [ -z "\$OPENCLAW_ROOT" ] || [ ! -f "\$OPENCLAW_ROOT/dist/index.js" ]; then
  echo "[launcher] 错误: 未找到 openclaw" >&2; exit 1
fi
echo "[launcher] OpenClaw: \$OPENCLAW_ROOT"

CONFIG_DIR="\$HOME/.openclaw"
CRASH_GUARD="\$CONFIG_DIR/crash-guard.cjs"

# 后台启动自动配对
if [ -f "\$CONFIG_DIR/auto-pair.cjs" ]; then
  "\$NODE_CMD" "\$CONFIG_DIR/auto-pair.cjs" &
fi

# 启动网关
REQUIRE_ARGS=()
if [ -f "\$CRASH_GUARD" ]; then
  REQUIRE_ARGS=(--require "\$CRASH_GUARD")
fi
echo "[launcher] 启动网关..."
exec "\$NODE_CMD" --max-old-space-size=1536 "\${REQUIRE_ARGS[@]}" "\$OPENCLAW_ROOT/dist/index.js" gateway --allow-unconfigured --bind lan
LAUNCHEOF
chmod +x "$LAUNCHER"
info "启动脚本已创建"

setup_systemd() {
  local SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SERVICE_DIR"

  # 清理旧服务名
  if [ -f "$SERVICE_DIR/openclaw-gateway.service" ]; then
    systemctl --user disable --now openclaw-gateway.service 2>/dev/null || true
    rm -f "$SERVICE_DIR/openclaw-gateway.service"
    warn "已移除旧的 openclaw-gateway.service"
  fi

  cat > "$SERVICE_DIR/openclaw.service" << SVCEOF
[Unit]
Description=OpenClaw AI Gateway (Crazyrouter)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash ${CONFIG_DIR}/start-gateway.sh
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=HOME=${HOME}
WorkingDirectory=${HOME}

[Install]
WantedBy=default.target
SVCEOF

  systemctl --user daemon-reload
  systemctl --user enable openclaw.service
  if command -v loginctl &>/dev/null; then
    sudo loginctl enable-linger "$(whoami)" 2>/dev/null || warn "loginctl enable-linger 失败（退出登录后服务可能停止）"
  fi
  info "systemd 用户服务已创建"
}

setup_launchd() {
  local PLIST_DIR="$HOME/Library/LaunchAgents"
  local PLIST_FILE="$PLIST_DIR/com.crazyrouter.openclaw.plist"
  mkdir -p "$PLIST_DIR"

  # 清理旧 plist
  local OLD_PLIST="$PLIST_DIR/ai.openclaw.gateway.plist"
  if [ -f "$OLD_PLIST" ]; then
    launchctl bootout "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
    rm -f "$OLD_PLIST"
    info "已移除旧的 ai.openclaw.gateway plist"
  fi

  cat > "$PLIST_FILE" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.crazyrouter.openclaw</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${CONFIG_DIR}/start-gateway.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>NODE_ENV</key>
    <string>production</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>StandardOutPath</key>
  <string>${HOME}/.openclaw/openclaw.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.openclaw/openclaw.err</string>
</dict>
</plist>
PLISTEOF

  info "launchd plist 已创建"
}

case "$OS_TYPE" in
  linux) setup_systemd ;;
  macos) setup_launchd ;;
esac

# ============================================================
# 步骤 9: 启动服务
# ============================================================
step "启动 OpenClaw"

case "$OS_TYPE" in
  linux)
    if systemctl --user is-active openclaw.service &>/dev/null; then
      info "OpenClaw 正在${GREEN}运行${NC} — 重启中"
      systemctl --user restart openclaw.service
    else
      systemctl --user start openclaw.service
    fi
    spin_start "等待服务启动..."
    sleep 3
    spin_stop
    if systemctl --user is-active openclaw.service &>/dev/null; then
      info "OpenClaw 已${GREEN}启动${NC}"
    else
      warn "服务可能未启动。检查: journalctl --user -u openclaw -f"
    fi
    ;;
  macos)
    launchctl bootout "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
    launchctl stop com.crazyrouter.openclaw 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.crazyrouter.openclaw.plist" 2>/dev/null || true
    pkill -f 'openclaw.*gateway' 2>/dev/null || true
    sleep 2
    launchctl load "$HOME/Library/LaunchAgents/com.crazyrouter.openclaw.plist" 2>/dev/null
    launchctl start com.crazyrouter.openclaw 2>/dev/null
    spin_start "等待服务启动..."
    sleep 3
    spin_stop
    if launchctl list com.crazyrouter.openclaw &>/dev/null; then
      info "OpenClaw 已${GREEN}启动${NC}"
    else
      warn "服务可能未启动。检查: cat ~/.openclaw/openclaw.err"
    fi
    ;;
esac

# 运行 doctor --fix 应用自动检测的更改
spin_start "运行 doctor --fix..."
openclaw doctor --fix >/dev/null 2>&1 || true
spin_stop
info "Doctor 修复已应用"

# ============================================================
# 步骤 10: 输出摘要
# ============================================================
step "安装完成"

# 检测访问 IP
LAN_IP=""
if [ "$OS_TYPE" = "macos" ]; then
  LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "")
  PUBLIC_IP="127.0.0.1"
else
  LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
  PUBLIC_IP=$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "<你的服务器IP>")
fi

echo ""
echo -e "${GREEN}"
cat << 'DONE'
    ╔═══════════════════════════════════════════╗
    ║                                           ║
    ║   ✓  安装完成！                           ║
    ║                                           ║
    ╚═══════════════════════════════════════════╝
DONE
echo -e "${NC}"

echo -e "  ${BOLD}WebUI${NC}         http://${PUBLIC_IP}:${GATEWAY_PORT}"
if [ -n "$LAN_IP" ]; then
  echo -e "  ${BOLD}局域网${NC}        http://${LAN_IP}:${GATEWAY_PORT}"
fi
echo -e "  ${BOLD}自动登录${NC}      http://${PUBLIC_IP}:${GATEWAY_PORT}?token=${GATEWAY_TOKEN}"
echo -e "  ${BOLD}默认模型${NC}      ${DEFAULT_MODEL}"
echo -e "  ${BOLD}配置文件${NC}      ${CONFIG_FILE}"
echo ""
echo -e "  ${DIM}┌─ Gateway Token（请保存！）────────────────┐${NC}"
echo -e "  ${DIM}│${NC} ${YELLOW}${GATEWAY_TOKEN}${NC} ${DIM}│${NC}"
echo -e "  ${DIM}└───────────────────────────────────────────┘${NC}"
echo ""

if [ "$OS_TYPE" = "linux" ]; then
  echo -e "  ${BOLD}管理命令${NC}"
  echo -e "  ${DIM}├${NC} 状态:   ${CYAN}systemctl --user status openclaw${NC}"
  echo -e "  ${DIM}├${NC} 日志:   ${CYAN}journalctl --user -u openclaw -f${NC}"
  echo -e "  ${DIM}├${NC} 重启:   ${CYAN}systemctl --user restart openclaw${NC}"
  echo -e "  ${DIM}└${NC} 停止:   ${CYAN}systemctl --user stop openclaw${NC}"
else
  echo -e "  ${BOLD}管理命令${NC}"
  echo -e "  ${DIM}├${NC} 日志:   ${CYAN}tail -f ~/.openclaw/openclaw.log${NC}"
  echo -e "  ${DIM}├${NC} 重启:   ${CYAN}launchctl stop com.crazyrouter.openclaw && launchctl start com.crazyrouter.openclaw${NC}"
  echo -e "  ${DIM}└${NC} 停止:   ${CYAN}launchctl stop com.crazyrouter.openclaw${NC}"
fi

echo ""
echo -e "  ${DIM}Powered by Crazyrouter · https://crazyrouter.com${NC}"
echo ""

# ============================================================
# 安装后: 交互式 Telegram 配对
# ============================================================
echo ""
echo -e "  ${DIM}$(printf '%.0s─' {1..48})${NC}"
echo -e "  ${BOLD}${MAGENTA}Telegram Bot 设置${NC}"
echo -e "  ${DIM}$(printf '%.0s─' {1..48})${NC}"
echo ""

echo -ne "  现在设置 Telegram Bot？ ${DIM}[Y/n]${NC} "
read -r SETUP_TG < /dev/tty || SETUP_TG="n"
SETUP_TG="${SETUP_TG:-Y}"

if [[ "$SETUP_TG" =~ ^[Yy]$ ]]; then

  # --- 步骤 A: 通过 BotFather 创建 Bot ---
  echo ""
  echo -e "  ${BOLD}第 1 步${NC} — 创建 Telegram Bot"
  echo ""
  echo -e "  ${DIM}┌──────────────────────────────────────────────┐${NC}"
  echo -e "  ${DIM}│${NC}  1. 打开 Telegram，搜索 ${BOLD}@BotFather${NC}          ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  2. 发送 ${CYAN}/newbot${NC}                              ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  3. 按提示为你的 Bot 命名                    ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  4. 复制 BotFather 给你的 ${YELLOW}Bot Token${NC}         ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}                                              ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  Token 格式: ${DIM}123456789:ABCdef...${NC}           ${DIM}│${NC}"
  echo -e "  ${DIM}└──────────────────────────────────────────────┘${NC}"
  echo ""

  echo -ne "  ${CYAN}▸${NC} 粘贴你的 Bot Token: "
  read -r TG_TOKEN < /dev/tty || TG_TOKEN=""

  if [ -z "$TG_TOKEN" ]; then
    warn "未提供 Token — 跳过 Telegram 设置"
    echo -e "  ${DIM}稍后可手动设置 — 在 ${BOLD}~/.openclaw/openclaw.json${NC}${DIM} 中添加:${NC}"
    echo -e "  ${CYAN}\"channels\": { \"telegram\": { \"botToken\": \"<token>\" } }${NC}"
    echo ""
    exit 0
  fi

  # --- 步骤 B: 注册渠道（直接写入配置）---
  echo ""
  spin_start "注册 Telegram Bot..."

  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    if (!cfg.channels) cfg.channels = {};
    cfg.channels.telegram = {
      enabled: true,
      botToken: '$TG_TOKEN',
      dmPolicy: 'pairing',
      groupPolicy: 'allowlist',
      streaming: 'off'
    };
    if (!cfg.plugins) cfg.plugins = {};
    if (!cfg.plugins.entries) cfg.plugins.entries = {};
    cfg.plugins.entries.telegram = { enabled: true };
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2));
  " 2>/dev/null

  spin_stop

  if node -e "const c=JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));process.exit(c.channels?.telegram?.botToken?0:1)" 2>/dev/null; then
    info "Telegram Bot Token 已写入配置"
  else
    error "写入 Telegram 配置失败"
    echo -e "  ${DIM}请手动添加到 $CONFIG_FILE:${NC}"
    echo -e "  ${CYAN}\"channels\": { \"telegram\": { \"botToken\": \"<token>\" } }${NC}"
    exit 1
  fi

  # 重启网关以加载新渠道
  spin_start "重启网关..."
  case "$OS_TYPE" in
    linux) systemctl --user restart openclaw.service 2>/dev/null ;;
    macos) launchctl stop com.crazyrouter.openclaw 2>/dev/null; launchctl start com.crazyrouter.openclaw 2>/dev/null ;;
  esac
  sleep 4
  spin_stop
  info "网关已重启，Telegram 渠道已加载"

  # --- 步骤 C: 通过 auto-pair.cjs 自动配对 ---
  echo ""
  echo -e "  ${BOLD}第 2 步${NC} — 与你的 Bot 配对"
  echo ""
  echo -e "  ${DIM}┌──────────────────────────────────────────────┐${NC}"
  echo -e "  ${DIM}│${NC}  打开 Telegram，向你的新 Bot 发送${BOLD}任意消息${NC}   ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  （例如 \"你好\"）                              ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}                                              ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  自动配对会将你设为所有者                    ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  （第一条消息 = 所有者）                     ${DIM}│${NC}"
  echo -e "  ${DIM}└──────────────────────────────────────────────┘${NC}"
  echo ""

  # 后台启动自动配对并等待
  if [ -f "$AUTO_PAIR_SCRIPT" ]; then
    node "$AUTO_PAIR_SCRIPT" &
    AUTO_PAIR_PID=$!
  fi

  echo -ne "  ${DIM}向 Bot 发送消息后按回车继续...${NC}"
  read -r < /dev/tty || true

  # 检查自动配对是否成功
  sleep 2
  if [ -f "$CONFIG_DIR/credentials/.telegram-owner-paired" ]; then
    echo ""
    echo -e "${GREEN}"
    cat << 'TGDONE'
    ╔═══════════════════════════════════════════╗
    ║                                           ║
    ║   ✓  Telegram Bot 配对成功！              ║
    ║                                           ║
    ╚═══════════════════════════════════════════╝
TGDONE
    echo -e "${NC}"
    echo -e "  向你的 Bot 发送消息 — 它会作为你的 AI 助手回复。"
    echo ""
  else
    warn "尚未检测到自动配对"
    echo -e "  ${DIM}如果你已发送消息，请稍等片刻并检查:${NC}"
    echo -e "  ${CYAN}ls ~/.openclaw/credentials/.telegram-owner-paired${NC}"
    echo -e "  ${DIM}或手动配对:${NC} ${CYAN}openclaw pairing list${NC} → ${CYAN}openclaw pairing approve <code>${NC}"
    echo ""
  fi

  # 清理自动配对后台进程
  kill "$AUTO_PAIR_PID" 2>/dev/null || true

else
  echo ""
  echo -e "  ${DIM}稍后设置 Telegram — 在 ${BOLD}~/.openclaw/openclaw.json${NC}${DIM} 中添加:${NC}"
  echo -e "  ${CYAN}\"channels\": { \"telegram\": { \"botToken\": \"<token>\" } }${NC}"
  echo -e "  ${DIM}然后重启网关并向 Bot 发送消息。${NC}"
  echo ""
fi
