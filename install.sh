#!/usr/bin/env bash
# ============================================================
# Crazyrouter OpenClaw — One-Click Deploy / 一键部署脚本
# ============================================================
# Install OpenClaw on Linux (Ubuntu/Debian/CentOS/RHEL) or
# macOS with Crazyrouter as the AI API backend.
# 在 Linux 和 macOS 上一键安装 OpenClaw，使用 Crazyrouter 作为
# AI API 后端。
#
# Usage / 用法:
#   curl -fsSL https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/install.sh | bash
#   # or / 或
#   bash install.sh
#
# Requirements / 要求:
#   - Linux (x64/arm64) or macOS (x64/arm64)
#   - Internet access / 可访问互联网
#   - Crazyrouter API Key (https://crazyrouter.com)
#
# Language / 语言:
#   Set INSTALLER_LANG=en or INSTALLER_LANG=zh to skip the
#   interactive language prompt.
# ============================================================
set -euo pipefail

# --- Pipe-safe bootstrap (macOS bash 3.2 reads stdin line-by-line) ---
# When piped via `curl ... | bash`, save to temp file and re-exec.
# Redirect stdin to /dev/tty so child processes can do interactive reads.
if [ ! -t 0 ] && [ -z "${_CRAZYROUTER_REEXEC:-}" ]; then
  _tmp=$(mktemp "${TMPDIR:-/tmp}/crazyrouter-install.XXXXXX")
  cat > "$_tmp"
  export _CRAZYROUTER_REEXEC=1
  bash "$_tmp" "$@" < /dev/tty
  _rc=$?
  rm -f "$_tmp"
  exit $_rc
fi

# ============================================================
# Language selection / 语言选择
# ============================================================
if [ -z "${INSTALLER_LANG:-}" ]; then
  echo ""
  echo "  Select language / 选择语言:"
  echo "    [1] 中文 (default)"
  echo "    [2] English"
  echo ""
  echo -n "  > "
  read -r _lang_choice < /dev/tty 2>/dev/null || _lang_choice=""
  case "$_lang_choice" in
    2|en|EN|En) INSTALLER_LANG="en" ;;
    *)          INSTALLER_LANG="zh" ;;
  esac
fi

# Normalise
case "${INSTALLER_LANG,,}" in
  en|english) INSTALLER_LANG="en" ;;
  *)          INSTALLER_LANG="zh" ;;
esac

# ============================================================
# i18n string loaders
# ============================================================
load_lang_zh() {
  L_BANNER_SUBTITLE="自托管 AI 网关"
  L_STEP1="检测运行环境"
  L_STEP2="检查 Node.js"
  L_STEP3="安装 OpenClaw"
  L_STEP4="配置信息"
  L_STEP5="生成配置文件"
  L_STEP6="应用补丁"
  L_STEP7="安装 IM 插件"
  L_STEP8="配置系统服务"
  L_STEP9="启动 OpenClaw"
  L_STEP10="安装完成"
  L_UNSUPPORTED_OS="不支持的操作系统: %s (仅支持 Linux 和 macOS)"
  L_UNSUPPORTED_ARCH="不支持的架构: %s"
  L_SYSTEM="系统:"
  L_PORT_IN_USE="端口 %s 已被占用 — OpenClaw 可能无法启动"
  L_INSTALLING_NODE_APT="通过 NodeSource (apt) 安装 Node.js 22..."
  L_INSTALLING_NODE_DNF="通过 NodeSource (dnf) 安装 Node.js 22..."
  L_INSTALLING_NODE_YUM="通过 NodeSource (yum) 安装 Node.js 22..."
  L_INSTALLING_NODE_BREW="通过 Homebrew 安装 Node.js 22..."
  L_NO_PKG_MANAGER="未找到支持的包管理器 (apt/dnf/yum)。请手动安装 Node.js 22+。"
  L_NO_HOMEBREW="未找到 Homebrew。请手动安装 Node.js 22+: https://nodejs.org"
  L_NODE_FOUND_OLD="检测到 Node.js v%s，但需要 v22+"
  L_NODE_READY="Node.js %s 已就绪"
  L_NODE_NOT_FOUND="未检测到 Node.js"
  L_NODE_INSTALL_FAILED="Node.js 安装失败"
  L_NODE_INSTALLED="Node.js %s 安装完成"
  L_OPENCLAW_ALREADY="OpenClaw %s 已安装 — 跳过"
  L_OPENCLAW_INSTALL_FAILED="OpenClaw 安装失败，请检查 npm 权限。"
  L_OPENCLAW_INSTALLED="OpenClaw %s 安装完成"
  L_INSTALL_PATH="安装路径:"
  L_USING_ENV_KEY="使用环境变量中的 API Key"
  L_USING_EXISTING_KEY="使用已有配置中的 API Key:"
  L_NO_TTY="无法获取用户输入。请先设置环境变量:\\n  ${BOLD}CRAZYROUTER_API_KEY=sk-xxx curl -fsSL ... | bash${NC}"
  L_ENTER_API_KEY="请输入你的 Crazyrouter API Key"
  L_API_KEY_PROMPT="API Key (sk-xxx): "
  L_READ_FAILED="读取输入失败。请改用环境变量 CRAZYROUTER_API_KEY。"
  L_API_KEY_EMPTY="API Key 不能为空"
  L_API_KEY_WARN="API Key 不以 'sk-' 开头 — 请确认是否正确"
  L_DEFAULT_MODEL="默认模型:"
  L_GATEWAY_PORT="网关端口:"
  L_CONFIG_EXISTS="配置文件已存在，是否覆盖？"
  L_BACKED_UP="已备份到"
  L_KEEP_CONFIG="保留现有配置 — 跳过"
  L_WRITING_CONFIG="写入 openclaw.json..."
  L_CONFIG_GENERATED="配置文件已生成:"
  L_PATCH_APPLIED="Opus 4.6 adaptive thinking 补丁已应用"
  L_PATCH_FAILED="补丁可能未生效 — 恢复备份"
  L_PATCH_ALREADY="Adaptive thinking 已修补或不存在"
  L_PATCH_NOT_FOUND="未找到 pi-ai anthropic.js — 跳过 adaptive thinking 补丁"
  L_DOWNLOADING_GUARD="下载 crash-guard.cjs..."
  L_GUARD_DOWNLOADED="crash-guard.cjs 已下载"
  L_GUARD_FAILED="下载 crash-guard.cjs 失败 — 创建最小版本"
  L_PLUGINS_ALREADY="IM 插件已安装 — 跳过"
  L_INSTALLING_PLUGIN="安装 %s..."
  L_PLUGIN_FAILED="%s 安装失败 (npm pack)"
  L_PLUGIN_INSTALLED="%s 已安装"
  L_INSTALLING_DEPS="安装 dingtalk-stream 依赖..."
  L_DEPS_FAILED="dingtalk-stream 安装失败"
  L_ALL_PLUGINS_READY="所有 IM 插件就绪"
  L_AUTO_PAIR_CREATED="自动配对脚本已创建"
  L_LAUNCHER_CREATED="启动脚本已创建"
  L_REMOVED_OLD_SERVICE="已移除旧的 openclaw-gateway.service"
  L_LINGER_FAILED="loginctl enable-linger 失败（退出登录后服务可能停止）"
  L_SYSTEMD_CREATED="systemd 用户服务已创建"
  L_REMOVED_OLD_PLIST="已移除旧的 ai.openclaw.gateway plist"
  L_LAUNCHD_CREATED="launchd plist 已创建"
  L_RUNNING_RESTART="OpenClaw 正在运行 — 重启中"
  L_WAITING_START="等待服务启动..."
  L_STARTED="OpenClaw 已启动"
  L_START_FAILED_LINUX="服务可能未启动。检查: journalctl --user -u openclaw -f"
  L_START_FAILED_MACOS="服务可能未启动。检查: cat ~/.openclaw/openclaw.err"
  L_DOCTOR_APPLIED="Doctor 修复已应用"
  L_LAN="局域网"
  L_AUTO_LOGIN="自动登录"
  L_CONFIG_FILE="配置文件"
  L_TOKEN_SAVE="Gateway Token（请保存！）"
  L_MANAGEMENT="管理命令"
  L_STATUS="状态:"
  L_LOGS="日志:"
  L_RESTART="重启:"
  L_STOP="停止:"
  L_TG_SETUP_TITLE="Telegram Bot 设置"
  L_TG_SETUP_NOW="现在设置 Telegram Bot？"
  L_TG_STEP1="第 1 步 — 创建 Telegram Bot"
  L_TG_PASTE_TOKEN="粘贴你的 Bot Token: "
  L_TG_NO_TOKEN="未提供 Token — 跳过 Telegram 设置"
  L_TG_LATER_HINT="稍后可手动设置 — 在 ${BOLD}~/.openclaw/openclaw.json${NC}${DIM} 中添加:"
  L_TG_REGISTERING="注册 Telegram Bot..."
  L_TG_TOKEN_WRITTEN="Telegram Bot Token 已写入配置"
  L_TG_WRITE_FAILED="写入 Telegram 配置失败"
  L_TG_RESTARTING="重启网关..."
  L_TG_RESTARTED="网关已重启，Telegram 渠道已加载"
  L_TG_STEP2="第 2 步 — 与你的 Bot 配对"
  L_TG_PRESS_ENTER="向 Bot 发送消息后按回车继续..."
  L_TG_PAIRED_MSG="向你的 Bot 发送消息 — 它会作为你的 AI 助手回复。"
  L_TG_NOT_PAIRED="尚未检测到自动配对"
  L_TG_CHECK_HINT="如果你已发送消息，请稍等片刻并检查:"
  L_TG_MANUAL_PAIR="或手动配对:"
  L_TG_LATER_SETUP="稍后设置 Telegram — 在 ${BOLD}~/.openclaw/openclaw.json${NC}${DIM} 中添加:"
  L_YOUR_SERVER_IP="<你的服务器IP>"
  L_POWERED_BY="Powered by Crazyrouter · https://crazyrouter.com"
  L_LAUNCHER_NODE_ERR="[launcher] 错误: 未找到 node"
  L_LAUNCHER_OC_ERR="[launcher] 错误: 未找到 openclaw"
  L_LAUNCHER_STARTING="[launcher] 启动网关..."
}

load_lang_en() {
  L_BANNER_SUBTITLE="Self-Hosted AI Gateway"
  L_STEP1="Detect environment"
  L_STEP2="Check Node.js"
  L_STEP3="Install OpenClaw"
  L_STEP4="Configuration"
  L_STEP5="Generate config file"
  L_STEP6="Apply patches"
  L_STEP7="Install IM plugins"
  L_STEP8="Configure system service"
  L_STEP9="Start OpenClaw"
  L_STEP10="Installation complete"
  L_UNSUPPORTED_OS="Unsupported OS: %s (only Linux and macOS are supported)"
  L_UNSUPPORTED_ARCH="Unsupported architecture: %s"
  L_SYSTEM="System:"
  L_PORT_IN_USE="Port %s is already in use — OpenClaw may fail to start"
  L_INSTALLING_NODE_APT="Installing Node.js 22 via NodeSource (apt)..."
  L_INSTALLING_NODE_DNF="Installing Node.js 22 via NodeSource (dnf)..."
  L_INSTALLING_NODE_YUM="Installing Node.js 22 via NodeSource (yum)..."
  L_INSTALLING_NODE_BREW="Installing Node.js 22 via Homebrew..."
  L_NO_PKG_MANAGER="No supported package manager found (apt/dnf/yum). Please install Node.js 22+ manually."
  L_NO_HOMEBREW="Homebrew not found. Please install Node.js 22+ manually: https://nodejs.org"
  L_NODE_FOUND_OLD="Found Node.js v%s, but v22+ is required"
  L_NODE_READY="Node.js %s ready"
  L_NODE_NOT_FOUND="Node.js not found"
  L_NODE_INSTALL_FAILED="Node.js installation failed"
  L_NODE_INSTALLED="Node.js %s installed"
  L_OPENCLAW_ALREADY="OpenClaw %s already installed — skipping"
  L_OPENCLAW_INSTALL_FAILED="OpenClaw installation failed. Check npm permissions."
  L_OPENCLAW_INSTALLED="OpenClaw %s installed"
  L_INSTALL_PATH="Install path:"
  L_USING_ENV_KEY="Using API Key from environment variable"
  L_USING_EXISTING_KEY="Using API Key from existing config:"
  L_NO_TTY="Cannot read user input. Set the environment variable first:\\n  ${BOLD}CRAZYROUTER_API_KEY=sk-xxx curl -fsSL ... | bash${NC}"
  L_ENTER_API_KEY="Enter your Crazyrouter API Key"
  L_API_KEY_PROMPT="API Key (sk-xxx): "
  L_READ_FAILED="Failed to read input. Use CRAZYROUTER_API_KEY environment variable instead."
  L_API_KEY_EMPTY="API Key cannot be empty"
  L_API_KEY_WARN="API Key does not start with 'sk-' — please verify"
  L_DEFAULT_MODEL="Default model:"
  L_GATEWAY_PORT="Gateway port:"
  L_CONFIG_EXISTS="Config file already exists. Overwrite?"
  L_BACKED_UP="Backed up to"
  L_KEEP_CONFIG="Keeping existing config — skipping"
  L_WRITING_CONFIG="Writing openclaw.json..."
  L_CONFIG_GENERATED="Config file generated:"
  L_PATCH_APPLIED="Opus 4.6 adaptive thinking patch applied"
  L_PATCH_FAILED="Patch may not have taken effect — restoring backup"
  L_PATCH_ALREADY="Adaptive thinking already patched or not present"
  L_PATCH_NOT_FOUND="pi-ai anthropic.js not found — skipping adaptive thinking patch"
  L_DOWNLOADING_GUARD="Downloading crash-guard.cjs..."
  L_GUARD_DOWNLOADED="crash-guard.cjs downloaded"
  L_GUARD_FAILED="Failed to download crash-guard.cjs — creating minimal version"
  L_PLUGINS_ALREADY="IM plugins already installed — skipping"
  L_INSTALLING_PLUGIN="Installing %s..."
  L_PLUGIN_FAILED="%s installation failed (npm pack)"
  L_PLUGIN_INSTALLED="%s installed"
  L_INSTALLING_DEPS="Installing dingtalk-stream dependency..."
  L_DEPS_FAILED="dingtalk-stream installation failed"
  L_ALL_PLUGINS_READY="All IM plugins ready"
  L_AUTO_PAIR_CREATED="Auto-pair script created"
  L_LAUNCHER_CREATED="Launcher script created"
  L_REMOVED_OLD_SERVICE="Removed old openclaw-gateway.service"
  L_LINGER_FAILED="loginctl enable-linger failed (service may stop after logout)"
  L_SYSTEMD_CREATED="systemd user service created"
  L_REMOVED_OLD_PLIST="Removed old ai.openclaw.gateway plist"
  L_LAUNCHD_CREATED="launchd plist created"
  L_RUNNING_RESTART="OpenClaw is running — restarting"
  L_WAITING_START="Waiting for service to start..."
  L_STARTED="OpenClaw started"
  L_START_FAILED_LINUX="Service may not have started. Check: journalctl --user -u openclaw -f"
  L_START_FAILED_MACOS="Service may not have started. Check: cat ~/.openclaw/openclaw.err"
  L_DOCTOR_APPLIED="Doctor fixes applied"
  L_LAN="LAN"
  L_AUTO_LOGIN="Auto-login"
  L_CONFIG_FILE="Config file"
  L_TOKEN_SAVE="Gateway Token (save this!)"
  L_MANAGEMENT="Management"
  L_STATUS="Status:"
  L_LOGS="Logs:"
  L_RESTART="Restart:"
  L_STOP="Stop:"
  L_TG_SETUP_TITLE="Telegram Bot Setup"
  L_TG_SETUP_NOW="Set up Telegram Bot now?"
  L_TG_STEP1="Step 1 — Create a Telegram Bot"
  L_TG_PASTE_TOKEN="Paste your Bot Token: "
  L_TG_NO_TOKEN="No token provided — skipping Telegram setup"
  L_TG_LATER_HINT="You can set it up later — add to ${BOLD}~/.openclaw/openclaw.json${NC}${DIM}:"
  L_TG_REGISTERING="Registering Telegram Bot..."
  L_TG_TOKEN_WRITTEN="Telegram Bot Token written to config"
  L_TG_WRITE_FAILED="Failed to write Telegram config"
  L_TG_RESTARTING="Restarting gateway..."
  L_TG_RESTARTED="Gateway restarted, Telegram channel loaded"
  L_TG_STEP2="Step 2 — Pair with your Bot"
  L_TG_PRESS_ENTER="Send a message to the Bot, then press Enter to continue..."
  L_TG_PAIRED_MSG="Send a message to your Bot — it will reply as your AI assistant."
  L_TG_NOT_PAIRED="Auto-pair not detected yet"
  L_TG_CHECK_HINT="If you already sent a message, wait a moment and check:"
  L_TG_MANUAL_PAIR="Or pair manually:"
  L_TG_LATER_SETUP="Set up Telegram later — add to ${BOLD}~/.openclaw/openclaw.json${NC}${DIM}:"
  L_YOUR_SERVER_IP="<your-server-ip>"
  L_POWERED_BY="Powered by Crazyrouter · https://crazyrouter.com"
  L_LAUNCHER_NODE_ERR="[launcher] Error: node not found"
  L_LAUNCHER_OC_ERR="[launcher] Error: openclaw not found"
  L_LAUNCHER_STARTING="[launcher] Starting gateway..."
}

# Load selected language
case "$INSTALLER_LANG" in
  en) load_lang_en ;;
  *)  load_lang_zh ;;
esac

# --- Constants ---
OPENCLAW_VERSION="latest"
API_BASE_URL="https://crazyrouter.com/v1"
API_NATIVE_URL="https://crazyrouter.com"
DEFAULT_MODEL="claude-sonnet-4-6"
GATEWAY_PORT=18789
MIN_NODE_MAJOR=22
TOTAL_STEPS=10

CRASH_GUARD_URL="https://raw.githubusercontent.com/xujfcn/crazyrouter-openclaw/main/crash-guard.cjs"

# IM plugin packages
PLUGIN_DINGTALK="@adongguo/dingtalk"
PLUGIN_WECOM="@marshulll/openclaw-wecom"
PLUGIN_QQBOT="@sliverp/qqbot"

# --- Colors & styles ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
error() { echo -e "  ${RED}✗${NC} $*" >&2; }
fatal() { error "$*"; exit 1; }

# --- Spinner ---
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

# --- Step progress bar ---
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
    ║  ╠╦╣╠═╣╔═╝╚╦╝╠╦╣║ ║║ ║ ║ ║╣ ╠╦╣
    ╚═╝╩╚═╩ ╩╚═╝ ╩ ╩╚═╚═╝╚═╝ ╩ ╚═╝╩╚═
BANNER
  echo -e "${NC}"
  echo -e "    ${BOLD}OpenClaw${NC} ${DIM}— ${L_BANNER_SUBTITLE}${NC}"
  echo -e "    ${DIM}$(printf '%.0s─' {1..40})${NC}"
  echo ""
}

# ============================================================
# Step 1: Detect environment
# ============================================================
show_banner
step "$L_STEP1"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  OS_TYPE="linux" ;;
  Darwin) OS_TYPE="macos" ;;
  *)      fatal "$(printf "$L_UNSUPPORTED_OS" "$OS")" ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_TYPE="x64" ;;
  aarch64|arm64) ARCH_TYPE="arm64" ;;
  *)             fatal "$(printf "$L_UNSUPPORTED_ARCH" "$ARCH")" ;;
esac

info "$L_SYSTEM ${BOLD}$OS_TYPE/$ARCH_TYPE${NC}"

# Port conflict detection
if command -v lsof &>/dev/null; then
  if lsof -i ":$GATEWAY_PORT" &>/dev/null; then
    warn "$(printf "$L_PORT_IN_USE" "$GATEWAY_PORT")"
  fi
elif command -v ss &>/dev/null; then
  if ss -tlnp | grep -q ":$GATEWAY_PORT " 2>/dev/null; then
    warn "$(printf "$L_PORT_IN_USE" "$GATEWAY_PORT")"
  fi
fi

# ============================================================
# Step 2: Check Node.js
# ============================================================
step "$L_STEP2"

install_node_linux() {
  if command -v apt-get &>/dev/null; then
    spin_start "$L_INSTALLING_NODE_APT"
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y nodejs >/dev/null 2>&1
    spin_stop
  elif command -v dnf &>/dev/null; then
    spin_start "$L_INSTALLING_NODE_DNF"
    curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo dnf install -y nodejs >/dev/null 2>&1
    spin_stop
  elif command -v yum &>/dev/null; then
    spin_start "$L_INSTALLING_NODE_YUM"
    curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo yum install -y nodejs >/dev/null 2>&1
    spin_stop
  else
    fatal "$L_NO_PKG_MANAGER"
  fi
}

install_node_macos() {
  if command -v brew &>/dev/null; then
    spin_start "$L_INSTALLING_NODE_BREW"
    brew install node@22 >/dev/null 2>&1
    brew link --overwrite node@22 2>/dev/null || true
    spin_stop
  else
    fatal "$L_NO_HOMEBREW"
  fi
}

NEED_NODE=false
if command -v node &>/dev/null; then
  NODE_VER=$(node -v | sed 's/^v//' | cut -d. -f1)
  if [ "$NODE_VER" -lt "$MIN_NODE_MAJOR" ]; then
    warn "$(printf "$L_NODE_FOUND_OLD" "$(node -v)")"
    NEED_NODE=true
  else
    info "$(printf "$L_NODE_READY" "$(node -v)")"
  fi
else
  warn "$L_NODE_NOT_FOUND"
  NEED_NODE=true
fi

if [ "$NEED_NODE" = true ]; then
  case "$OS_TYPE" in
    linux) install_node_linux ;;
    macos) install_node_macos ;;
  esac
  command -v node &>/dev/null || fatal "$L_NODE_INSTALL_FAILED"
  info "$(printf "$L_NODE_INSTALLED" "$(node -v)")"
fi

# ============================================================
# Step 3: Install OpenClaw
# ============================================================
step "$L_STEP3"

SKIP_OPENCLAW=false
if command -v openclaw &>/dev/null; then
  EXISTING_VER=$(openclaw --version 2>/dev/null || echo "")
  if [ -n "$EXISTING_VER" ]; then
    info "$(printf "$L_OPENCLAW_ALREADY" "${BOLD}$EXISTING_VER${NC}")"
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
  command -v openclaw &>/dev/null || fatal "$L_OPENCLAW_INSTALL_FAILED"
  OPENCLAW_VER=$(openclaw --version 2>/dev/null || echo "unknown")
  info "$(printf "$L_OPENCLAW_INSTALLED" "${BOLD}$OPENCLAW_VER${NC}")"
fi

# Find OpenClaw install directory
OPENCLAW_ROOT=$(node -e "console.log(require.resolve('openclaw/package.json').replace('/package.json',''))" 2>/dev/null || echo "")
if [ -z "$OPENCLAW_ROOT" ]; then
  OPENCLAW_ROOT=$(npm root -g)/openclaw
fi
info "$L_INSTALL_PATH ${DIM}$OPENCLAW_ROOT${NC}"

# ============================================================
# Step 4: User configuration
# ============================================================
step "$L_STEP4"

# API Key
if [ -n "${CRAZYROUTER_API_KEY:-}" ]; then
  API_KEY="$CRAZYROUTER_API_KEY"
  info "$L_USING_ENV_KEY"
elif [ -f "$HOME/.openclaw/openclaw.json" ]; then
  EXISTING_KEY=$(node -e "const c=JSON.parse(require('fs').readFileSync('$HOME/.openclaw/openclaw.json','utf8'));console.log(c.models?.providers?.crazyrouter?.apiKey||c.models?.providers?.['crazyrouter-claude']?.apiKey||c.env?.vars?.OPENAI_API_KEY||'')" 2>/dev/null || echo "")
  if [ -n "$EXISTING_KEY" ]; then
    API_KEY="$EXISTING_KEY"
    info "$L_USING_EXISTING_KEY ${DIM}${API_KEY:0:10}...${API_KEY: -4}${NC}"
  fi
fi

if [ -z "${API_KEY:-}" ]; then
  if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
    fatal "$L_NO_TTY"
  fi
  echo ""
  echo -e "  $L_ENTER_API_KEY ${DIM}(${BOLD}https://crazyrouter.com${NC}${DIM})${NC}"
  echo -ne "  ${CYAN}▸${NC} $L_API_KEY_PROMPT"
  read -r API_KEY < /dev/tty || fatal "$L_READ_FAILED"
  [ -z "$API_KEY" ] && fatal "$L_API_KEY_EMPTY"
fi

# Validate API Key format
[[ "$API_KEY" == sk-* ]] || warn "$L_API_KEY_WARN"

# Generate gateway token
GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")

echo ""
info "API Key: ${DIM}${API_KEY:0:10}...${API_KEY: -4}${NC}"
info "$L_DEFAULT_MODEL ${BOLD}$DEFAULT_MODEL${NC}"
info "$L_GATEWAY_PORT ${BOLD}$GATEWAY_PORT${NC}"

# ============================================================
# Step 5: Generate config file
# ============================================================
step "$L_STEP5"

CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
mkdir -p "$CONFIG_DIR"

# If config exists, ask whether to overwrite
SKIP_CONFIG=false
if [ -f "$CONFIG_FILE" ]; then
  echo -ne "  $L_CONFIG_EXISTS ${DIM}[y/N]${NC} "
  read -r OVERWRITE_CFG < /dev/tty || OVERWRITE_CFG="n"
  OVERWRITE_CFG="${OVERWRITE_CFG:-n}"
  if [[ "$OVERWRITE_CFG" =~ ^[Yy]$ ]]; then
    BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    warn "$L_BACKED_UP ${DIM}$BACKUP_FILE${NC}"
  else
    info "$L_KEEP_CONFIG"
    SKIP_CONFIG=true
    GATEWAY_TOKEN=$(node -e "const c=JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));console.log(c.gateway?.auth?.token||'unknown')" 2>/dev/null || echo "unknown")
  fi
fi

if [ "$SKIP_CONFIG" = false ]; then

# Determine model provider prefix
case "$DEFAULT_MODEL" in
  claude-*)  MODEL_PROVIDER="crazyrouter-claude" ;;
  minimax-*) MODEL_PROVIDER="crazyrouter-minimax" ;;
  *)         MODEL_PROVIDER="crazyrouter" ;;
esac

spin_start "$L_WRITING_CONFIG"

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
info "$L_CONFIG_GENERATED ${DIM}$CONFIG_FILE${NC}"

fi # end SKIP_CONFIG

# Create necessary directories
mkdir -p "$CONFIG_DIR/agents/main/sessions"

# ============================================================
# Step 6: Apply patches
# ============================================================
step "$L_STEP6"

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
      info "$L_PATCH_APPLIED"
    else
      warn "$L_PATCH_FAILED"
      cp "${ANTHROPIC_JS}.bak" "$ANTHROPIC_JS"
    fi
    rm -f "${ANTHROPIC_JS}.bak"
  else
    info "$L_PATCH_ALREADY"
  fi
else
  warn "$L_PATCH_NOT_FOUND"
fi

CRASH_GUARD_FILE="$CONFIG_DIR/crash-guard.cjs"
spin_start "$L_DOWNLOADING_GUARD"
if curl -fsSL "$CRASH_GUARD_URL" -o "$CRASH_GUARD_FILE" 2>/dev/null; then
  spin_stop
  info "$L_GUARD_DOWNLOADED"
else
  spin_stop
  warn "$L_GUARD_FAILED"
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
# Step 7: Install IM plugins
# ============================================================
step "$L_STEP7"

EXTENSIONS_DIR="$OPENCLAW_ROOT/extensions"
if [ ! -d "$EXTENSIONS_DIR" ]; then
  EXTENSIONS_DIR="$CONFIG_DIR/extensions"
fi

if [ -d "$EXTENSIONS_DIR/dingtalk" ] && [ -d "$EXTENSIONS_DIR/wecom" ] && [ -d "$EXTENSIONS_DIR/qqbot" ]; then
  info "$L_PLUGINS_ALREADY"
else
  mkdir -p "$EXTENSIONS_DIR"

install_plugin() {
  local pkg="$1"
  local dir="$2"
  local keep_nm="${3:-no}"
  spin_start "$(printf "$L_INSTALLING_PLUGIN" "$dir")"
  mkdir -p "$EXTENSIONS_DIR/$dir"
  local tgz
  tgz=$(cd /tmp && npm pack "$pkg" --pack-destination /tmp 2>/dev/null | tail -1)
  if [ -z "$tgz" ] || [ ! -f "/tmp/$tgz" ]; then
    spin_stop
    warn "$(printf "$L_PLUGIN_FAILED" "$dir")"
    return 1
  fi
  tar xzf "/tmp/$tgz" -C "$EXTENSIONS_DIR/$dir" --strip-components=1 2>/dev/null
  rm -f "/tmp/$tgz"
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
  info "$(printf "$L_PLUGIN_INSTALLED" "$dir")"
}

install_plugin "$PLUGIN_DINGTALK" "dingtalk" "no"
spin_start "$L_INSTALLING_DEPS"
(cd "$EXTENSIONS_DIR/dingtalk" && npm install --omit=dev --no-package-lock --ignore-scripts dingtalk-stream >/dev/null 2>&1) || warn "$L_DEPS_FAILED"
spin_stop

install_plugin "$PLUGIN_WECOM" "wecom" "yes"
install_plugin "$PLUGIN_QQBOT" "qqbot" "no"
info "$L_ALL_PLUGINS_READY"
fi # end plugins skip

# --- Auto-pair script ---
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
    const req = reqs[0]; const id = String(req.id);
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
    console.log(`Auto-paired ${channel} owner: ${id}`);
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
  debounce = setTimeout(() => { debounce = null; if (checkAll()) { watcher.close(); process.exit(0); } }, 500);
});
setInterval(() => { if (checkAll()) { watcher.close(); process.exit(0); } }, 60000);
APEOF
info "$L_AUTO_PAIR_CREATED"

# ============================================================
# Step 8: Configure system service
# ============================================================
step "$L_STEP8"

OPENCLAW_CMD=$(command -v openclaw)
NODE_CMD=$(command -v node)

LAUNCHER="$CONFIG_DIR/start-gateway.sh"
cat > "$LAUNCHER" << LAUNCHEOF
#!/bin/bash
set -euo pipefail
if [ -s "\$HOME/.nvm/nvm.sh" ]; then export NVM_DIR="\$HOME/.nvm"; . "\$NVM_DIR/nvm.sh"; fi
NODE_CMD=\$(command -v node 2>/dev/null || echo "")
if [ -z "\$NODE_CMD" ]; then echo "$L_LAUNCHER_NODE_ERR" >&2; exit 1; fi
echo "[launcher] Node: \$NODE_CMD (\$(\$NODE_CMD -v))"
OPENCLAW_ROOT=\$("\$NODE_CMD" -e "console.log(require.resolve('openclaw/package.json').replace('/package.json',''))" 2>/dev/null || echo "")
if [ -z "\$OPENCLAW_ROOT" ] || [ ! -f "\$OPENCLAW_ROOT/dist/index.js" ]; then
  NPM_GLOBAL=\$(npm root -g 2>/dev/null || echo "")
  if [ -n "\$NPM_GLOBAL" ] && [ -f "\$NPM_GLOBAL/openclaw/dist/index.js" ]; then OPENCLAW_ROOT="\$NPM_GLOBAL/openclaw"; fi
fi
if [ -z "\$OPENCLAW_ROOT" ] || [ ! -f "\$OPENCLAW_ROOT/dist/index.js" ]; then echo "$L_LAUNCHER_OC_ERR" >&2; exit 1; fi
echo "[launcher] OpenClaw: \$OPENCLAW_ROOT"
CONFIG_DIR="\$HOME/.openclaw"
CRASH_GUARD="\$CONFIG_DIR/crash-guard.cjs"
if [ -f "\$CONFIG_DIR/auto-pair.cjs" ]; then "\$NODE_CMD" "\$CONFIG_DIR/auto-pair.cjs" & fi
REQUIRE_ARGS=()
if [ -f "\$CRASH_GUARD" ]; then REQUIRE_ARGS=(--require "\$CRASH_GUARD"); fi
echo "$L_LAUNCHER_STARTING"
exec "\$NODE_CMD" --max-old-space-size=1536 "\${REQUIRE_ARGS[@]}" "\$OPENCLAW_ROOT/dist/index.js" gateway --allow-unconfigured --bind lan
LAUNCHEOF
chmod +x "$LAUNCHER"
info "$L_LAUNCHER_CREATED"

setup_systemd() {
  local SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SERVICE_DIR"
  if [ -f "$SERVICE_DIR/openclaw-gateway.service" ]; then
    systemctl --user disable --now openclaw-gateway.service 2>/dev/null || true
    rm -f "$SERVICE_DIR/openclaw-gateway.service"
    warn "$L_REMOVED_OLD_SERVICE"
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
    sudo loginctl enable-linger "$(whoami)" 2>/dev/null || warn "$L_LINGER_FAILED"
  fi
  info "$L_SYSTEMD_CREATED"
}

setup_launchd() {
  local PLIST_DIR="$HOME/Library/LaunchAgents"
  local PLIST_FILE="$PLIST_DIR/com.crazyrouter.openclaw.plist"
  mkdir -p "$PLIST_DIR"
  local OLD_PLIST="$PLIST_DIR/ai.openclaw.gateway.plist"
  if [ -f "$OLD_PLIST" ]; then
    launchctl bootout "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
    rm -f "$OLD_PLIST"
    info "$L_REMOVED_OLD_PLIST"
  fi
  cat > "$PLIST_FILE" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.crazyrouter.openclaw</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${CONFIG_DIR}/start-gateway.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>EnvironmentVariables</key><dict><key>NODE_ENV</key><string>production</string><key>HOME</key><string>${HOME}</string></dict>
  <key>WorkingDirectory</key><string>${HOME}</string>
  <key>StandardOutPath</key><string>${HOME}/.openclaw/openclaw.log</string>
  <key>StandardErrorPath</key><string>${HOME}/.openclaw/openclaw.err</string>
</dict>
</plist>
PLISTEOF
  info "$L_LAUNCHD_CREATED"
}

case "$OS_TYPE" in
  linux) setup_systemd ;;
  macos) setup_launchd ;;
esac

# ============================================================
# Step 9: Start OpenClaw
# ============================================================
step "$L_STEP9"

case "$OS_TYPE" in
  linux)
    if systemctl --user is-active openclaw.service &>/dev/null; then
      info "$L_RUNNING_RESTART"
      systemctl --user restart openclaw.service
    else
      systemctl --user start openclaw.service
    fi
    spin_start "$L_WAITING_START"
    sleep 3
    spin_stop
    if systemctl --user is-active openclaw.service &>/dev/null; then
      info "$L_STARTED"
    else
      warn "$L_START_FAILED_LINUX"
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
    spin_start "$L_WAITING_START"
    sleep 3
    spin_stop
    if launchctl list com.crazyrouter.openclaw &>/dev/null; then
      info "$L_STARTED"
    else
      warn "$L_START_FAILED_MACOS"
    fi
    ;;
esac

spin_start "doctor --fix..."
openclaw doctor --fix >/dev/null 2>&1 || true
spin_stop
info "$L_DOCTOR_APPLIED"

# ============================================================
# Step 10: Summary
# ============================================================
step "$L_STEP10"

LAN_IP=""
if [ "$OS_TYPE" = "macos" ]; then
  LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "")
  PUBLIC_IP="127.0.0.1"
else
  LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
  PUBLIC_IP=$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "$L_YOUR_SERVER_IP")
fi

echo ""
echo -e "${GREEN}"
cat << 'DONE'
    ╔═══════════════════════════════════════════╗
    ║                                           ║
    ║   ✓  Installation Complete!               ║
    ║                                           ║
    ╚═══════════════════════════════════════════╝
DONE
echo -e "${NC}"

echo -e "  ${BOLD}WebUI${NC}         http://${PUBLIC_IP}:${GATEWAY_PORT}"
if [ -n "$LAN_IP" ]; then
  echo -e "  ${BOLD}$L_LAN${NC}           http://${LAN_IP}:${GATEWAY_PORT}"
fi
echo -e "  ${BOLD}$L_AUTO_LOGIN${NC}      http://${PUBLIC_IP}:${GATEWAY_PORT}?token=${GATEWAY_TOKEN}"
echo -e "  ${BOLD}$L_DEFAULT_MODEL${NC} ${DEFAULT_MODEL}"
echo -e "  ${BOLD}$L_CONFIG_FILE${NC}      ${CONFIG_FILE}"
echo ""
echo -e "  ${DIM}┌─ $L_TOKEN_SAVE ─────────────────┐${NC}"
echo -e "  ${DIM}│${NC} ${YELLOW}${GATEWAY_TOKEN}${NC} ${DIM}│${NC}"
echo -e "  ${DIM}└───────────────────────────────────────────┘${NC}"
echo ""

if [ "$OS_TYPE" = "linux" ]; then
  echo -e "  ${BOLD}$L_MANAGEMENT${NC}"
  echo -e "  ${DIM}├${NC} $L_STATUS   ${CYAN}systemctl --user status openclaw${NC}"
  echo -e "  ${DIM}├${NC} $L_LOGS   ${CYAN}journalctl --user -u openclaw -f${NC}"
  echo -e "  ${DIM}├${NC} $L_RESTART   ${CYAN}systemctl --user restart openclaw${NC}"
  echo -e "  ${DIM}└${NC} $L_STOP   ${CYAN}systemctl --user stop openclaw${NC}"
else
  echo -e "  ${BOLD}$L_MANAGEMENT${NC}"
  echo -e "  ${DIM}├${NC} $L_LOGS   ${CYAN}tail -f ~/.openclaw/openclaw.log${NC}"
  echo -e "  ${DIM}├${NC} $L_RESTART   ${CYAN}launchctl stop com.crazyrouter.openclaw && launchctl start com.crazyrouter.openclaw${NC}"
  echo -e "  ${DIM}└${NC} $L_STOP   ${CYAN}launchctl stop com.crazyrouter.openclaw${NC}"
fi

echo ""
echo -e "  ${DIM}$L_POWERED_BY${NC}"
echo ""

# ============================================================
# Post-install: Interactive Telegram setup
# ============================================================
echo ""
echo -e "  ${DIM}$(printf '%.0s─' {1..48})${NC}"
echo -e "  ${BOLD}${MAGENTA}$L_TG_SETUP_TITLE${NC}"
echo -e "  ${DIM}$(printf '%.0s─' {1..48})${NC}"
echo ""

echo -ne "  $L_TG_SETUP_NOW ${DIM}[Y/n]${NC} "
read -r SETUP_TG < /dev/tty || SETUP_TG="n"
SETUP_TG="${SETUP_TG:-Y}"

if [[ "$SETUP_TG" =~ ^[Yy]$ ]]; then

  echo ""
  echo -e "  ${BOLD}$L_TG_STEP1${NC}"
  echo ""
  echo -e "  ${DIM}┌──────────────────────────────────────────────┐${NC}"
  echo -e "  ${DIM}│${NC}  1. Open Telegram, search ${BOLD}@BotFather${NC}          ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  2. Send ${CYAN}/newbot${NC}                              ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  3. Follow prompts to name your bot          ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  4. Copy the ${YELLOW}bot token${NC}                       ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  Token format: ${DIM}123456789:ABCdef...${NC}           ${DIM}│${NC}"
  echo -e "  ${DIM}└──────────────────────────────────────────────┘${NC}"
  echo ""

  echo -ne "  ${CYAN}▸${NC} $L_TG_PASTE_TOKEN"
  read -r TG_TOKEN < /dev/tty || TG_TOKEN=""

  if [ -z "$TG_TOKEN" ]; then
    warn "$L_TG_NO_TOKEN"
    echo -e "  ${DIM}$L_TG_LATER_HINT${NC}"
    echo -e "  ${CYAN}\"channels\": { \"telegram\": { \"botToken\": \"<token>\" } }${NC}"
    echo ""
    exit 0
  fi

  echo ""
  spin_start "$L_TG_REGISTERING"
  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    if (!cfg.channels) cfg.channels = {};
    cfg.channels.telegram = { enabled: true, botToken: '$TG_TOKEN', dmPolicy: 'pairing', groupPolicy: 'allowlist', streaming: 'off' };
    if (!cfg.plugins) cfg.plugins = {};
    if (!cfg.plugins.entries) cfg.plugins.entries = {};
    cfg.plugins.entries.telegram = { enabled: true };
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2));
  " 2>/dev/null
  spin_stop

  if node -e "const c=JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));process.exit(c.channels?.telegram?.botToken?0:1)" 2>/dev/null; then
    info "$L_TG_TOKEN_WRITTEN"
  else
    error "$L_TG_WRITE_FAILED"
    echo -e "  ${CYAN}\"channels\": { \"telegram\": { \"botToken\": \"<token>\" } }${NC}"
    exit 1
  fi

  spin_start "$L_TG_RESTARTING"
  case "$OS_TYPE" in
    linux) systemctl --user restart openclaw.service 2>/dev/null ;;
    macos) launchctl stop com.crazyrouter.openclaw 2>/dev/null; launchctl start com.crazyrouter.openclaw 2>/dev/null ;;
  esac
  sleep 4
  spin_stop
  info "$L_TG_RESTARTED"

  echo ""
  echo -e "  ${BOLD}$L_TG_STEP2${NC}"
  echo ""
  echo -e "  ${DIM}┌──────────────────────────────────────────────┐${NC}"
  echo -e "  ${DIM}│${NC}  Send ${BOLD}any message${NC} to your new bot            ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  Auto-pair will approve you as owner         ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  (first message = owner)                     ${DIM}│${NC}"
  echo -e "  ${DIM}└──────────────────────────────────────────────┘${NC}"
  echo ""

  if [ -f "$AUTO_PAIR_SCRIPT" ]; then
    node "$AUTO_PAIR_SCRIPT" &
    AUTO_PAIR_PID=$!
  fi

  echo -ne "  ${DIM}$L_TG_PRESS_ENTER${NC}"
  read -r < /dev/tty || true

  sleep 2
  if [ -f "$CONFIG_DIR/credentials/.telegram-owner-paired" ]; then
    echo ""
    echo -e "${GREEN}"
    cat << 'TGDONE'
    ╔═══════════════════════════════════════════╗
    ║   ✓  Telegram Bot Paired!                 ║
    ╚═══════════════════════════════════════════╝
TGDONE
    echo -e "${NC}"
    echo -e "  $L_TG_PAIRED_MSG"
    echo ""
  else
    warn "$L_TG_NOT_PAIRED"
    echo -e "  ${DIM}$L_TG_CHECK_HINT${NC}"
    echo -e "  ${CYAN}ls ~/.openclaw/credentials/.telegram-owner-paired${NC}"
    echo -e "  ${DIM}$L_TG_MANUAL_PAIR${NC} ${CYAN}openclaw pairing list${NC} → ${CYAN}openclaw pairing approve <code>${NC}"
    echo ""
  fi

  kill "$AUTO_PAIR_PID" 2>/dev/null || true

else
  echo ""
  echo -e "  ${DIM}$L_TG_LATER_SETUP${NC}"
  echo -e "  ${CYAN}\"channels\": { \"telegram\": { \"botToken\": \"<token>\" } }${NC}"
  echo ""
fi

