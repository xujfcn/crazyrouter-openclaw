#!/usr/bin/env bash
#
# OpenClaw 一键部署脚本
# - 使用 CrazyRouter，默认模型 Claude Opus 4.6
# - 需用户填写：CrazyRouter API Token、Telegram Bot Token
# - 支持 Docker 或本机 Node 运行
#
set -e

OPENCLAW_DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-openclaw-bot:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-openclaw-bot}"

# --- 颜色与输出 ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
nc='\033[0m'
info() { echo -e "${green}[INFO]${nc} $*"; }
warn() { echo -e "${yellow}[WARN]${nc} $*"; }
err()  { echo -e "${red}[ERROR]${nc} $*"; }

# --- 检测 root / sudo ---
need_sudo() {
  if [ -w "$OPENCLAW_DATA_DIR" ] 2>/dev/null || [ ! -d "$OPENCLAW_DATA_DIR" ]; then
    return 1
  fi
  [ "$(id -u)" != "0" ]
}

# --- 读取用户输入（带默认环境变量）---
read_token() {
  local name="$1"
  local env_name="$2"
  local prompt="$3"
  local val="${!env_name}"
  if [ -n "$val" ]; then
    echo "$val"
    return
  fi
  while true; do
    read -r -p "$prompt" val
    val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
    warn "不能为空，请重新输入。"
  done
}

# --- 检测并安装 Docker ---
ensure_docker() {
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    info "Docker 已就绪。"
    return 0
  fi
  warn "未检测到 Docker 或 Docker 未运行。"
  if [ "$(uname -s)" != "Linux" ]; then
    err "当前仅支持 Linux 自动安装 Docker。请先安装 Docker 后重试。"
    exit 1
  fi
  if [ "$(id -u)" != "0" ]; then
    err "安装 Docker 需要 root。请使用: sudo $0"
    exit 1
  fi
  info "正在安装 Docker..."
  if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gpg
    install -m 0755 -d /etc/apt/keyrings
    local distro="ubuntu"
    local codename="jammy"
    if [ -f /etc/os-release ]; then
      # shellcheck source=/dev/null
      . /etc/os-release
      [ "$ID" = "debian" ] && distro="debian"
      [ -n "$VERSION_CODENAME" ] && codename="$VERSION_CODENAME"
    fi
    curl -fsSL "https://download.docker.com/linux/$distro/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro $codename stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  else
    err "仅支持 apt (Debian/Ubuntu) 自动安装 Docker。请手动安装 Docker 后重试。"
    exit 1
  fi
  info "Docker 安装完成。"
}

# --- 检测是否可用 Docker（已安装且可连接）---
docker_available() {
  command -v docker &>/dev/null && docker info &>/dev/null 2>&1
}

# --- 检测 jq ---
ensure_jq() {
  if command -v jq &>/dev/null; then
    return 0
  fi
  if [ "$(uname -s)" != "Linux" ]; then
    err "生成配置需要 jq。请安装 jq 后重试。"
    exit 1
  fi
  if command -v apt-get &>/dev/null && [ "$(id -u)" = "0" ]; then
    apt-get update -qq && apt-get install -y -qq jq
  else
    err "请先安装 jq (apt install jq 或 yum install jq)。"
    exit 1
  fi
}

# --- 生成 openclaw.json ---
write_openclaw_config() {
  local data_dir="$1"
  local crazyrouter_key="$2"
  local telegram_token="$3"
  local gateway_token
  gateway_token=$(openssl rand -hex 16 2>/dev/null || echo "fallback-$(date +%s)-$$")

  mkdir -p "$data_dir/workspace"
  local cfg_path="$data_dir/openclaw.json"

  # 使用 jq 安全生成 JSON（避免 token 中的特殊字符问题）
  jq -n \
    --arg cr "$crazyrouter_key" \
    --arg tg "$telegram_token" \
    --arg gw "$gateway_token" \
    --arg workspace "$data_dir/workspace" \
    --argjson port "$OPENCLAW_PORT" \
    '{
      meta: { lastTouchedVersion: "2026.2.3-1", lastTouchedAt: (now | todate) },
      models: {
        mode: "merge",
        providers: {
          crazyrouter: {
            baseUrl: "https://crazyrouter.com/v1",
            apiKey: $cr,
            api: "openai-completions",
            models: [
              {
                id: "claude-opus-4-6",
                name: "Claude Opus 4.6",
                reasoning: false,
                input: ["text", "image"],
                contextWindow: 200000,
                maxTokens: 8192
              }
            ]
          }
        }
      },
      agents: {
        defaults: {
          model: { primary: "crazyrouter/claude-opus-4-6" },
          workspace: $workspace,
          maxConcurrent: 4
        }
      },
      channels: {
        telegram: {
          enabled: true,
          dmPolicy: "pairing",
          botToken: $tg,
          groupPolicy: "open",
          streamMode: "partial"
        }
      },
      gateway: {
        port: $port,
        mode: "local",
        bind: "loopback",
        auth: { mode: "token", token: $gw }
      }
    }' > "$cfg_path"

  chmod 600 "$cfg_path"
  info "已生成配置: $cfg_path"
}

# Docker 容器内需使用 /root/.openclaw/workspace（挂载点为 /root/.openclaw）
fix_workspace_for_docker() {
  local cfg_path="$OPENCLAW_DATA_DIR/openclaw.json"
  if [ -f "$cfg_path" ]; then
    jq '.agents.defaults.workspace = "/root/.openclaw/workspace"' "$cfg_path" > "${cfg_path}.tmp" && mv "${cfg_path}.tmp" "$cfg_path"
  fi
}

# 本机 Node 运行时 workspace 使用数据目录下的 workspace
fix_workspace_for_node() {
  local cfg_path="$OPENCLAW_DATA_DIR/openclaw.json"
  if [ -f "$cfg_path" ]; then
    jq --arg w "$OPENCLAW_DATA_DIR/workspace" '.agents.defaults.workspace = $w' "$cfg_path" > "${cfg_path}.tmp" && mv "${cfg_path}.tmp" "$cfg_path"
  fi
}

# --- 构建本地 OpenClaw 镜像（若不存在）---
ensure_image() {
  if docker image inspect "$OPENCLAW_IMAGE" &>/dev/null; then
    info "镜像已存在: $OPENCLAW_IMAGE"
    return 0
  fi
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$script_dir/Dockerfile" ]; then
    info "正在构建镜像: $OPENCLAW_IMAGE"
    docker build -t "$OPENCLAW_IMAGE" "$script_dir"
  else
    err "未找到镜像 $OPENCLAW_IMAGE 且同目录下无 Dockerfile。请先构建镜像或设置 OPENCLAW_IMAGE。"
    err "示例: docker build -t openclaw-bot:latest -f $script_dir/Dockerfile $script_dir"
    exit 1
  fi
}

# --- Docker 方式启动 ---
run_docker() {
  ensure_docker
  fix_workspace_for_docker
  ensure_image
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    info "已存在容器 $CONTAINER_NAME，正在删除并重建..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  fi
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -v "${OPENCLAW_DATA_DIR}:/root/.openclaw" \
    -p "${OPENCLAW_PORT}:${OPENCLAW_PORT}" \
    "$OPENCLAW_IMAGE"
  info "容器已启动: $CONTAINER_NAME (端口 $OPENCLAW_PORT)"
}

# --- 本机 Node 方式启动 ---
run_node() {
  fix_workspace_for_node
  if ! command -v node &>/dev/null; then
    err "未检测到 Node.js。"
    if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" != "0" ]; then
      echo -e "  ${yellow}请使用 sudo 重新运行本脚本，将自动安装 Docker 并部署：${nc} sudo $0"
    else
      echo -e "  请安装 Node.js 22+ 后重试，或（Linux）使用 ${green}sudo $0${nc} 以自动安装 Docker 部署。"
    fi
    exit 1
  fi
  local v
  v=$(node -p "process.versions.node.split('.')[0]")
  if [ "${v:-0}" -lt 22 ]; then
    warn "建议使用 Node.js 22+，当前: $(node -v)"
  fi
  if ! command -v openclaw &>/dev/null; then
    info "正在全局安装 openclaw..."
    npm install -g openclaw@latest
  fi
  export OPENCLAW_HOME="$OPENCLAW_DATA_DIR"
  info "正在启动 OpenClaw Gateway (端口 $OPENCLAW_PORT)..."
  nohup openclaw gateway --port "$OPENCLAW_PORT" >> "${OPENCLAW_DATA_DIR}/gateway.log" 2>&1 &
  echo $! > "${OPENCLAW_DATA_DIR}/gateway.pid"
  info "Gateway 已在后台启动，PID: $(cat "${OPENCLAW_DATA_DIR}/gateway.pid")"
}

# --- 主流程 ---
main() {
  echo ""
  echo "=============================================="
  echo "  OpenClaw 一键部署 (CrazyRouter + Opus 4.6)"
  echo "=============================================="
  echo ""

  # 数据目录
  if [ ! -d "$OPENCLAW_DATA_DIR" ]; then
    if need_sudo; then
      err "创建 $OPENCLAW_DATA_DIR 需要 root。请使用: sudo $0"
      exit 1
    fi
    mkdir -p "$OPENCLAW_DATA_DIR"
  fi

  ensure_jq

  # 读取 Token（环境变量 TELEGRAM_BOT_TOKEN / CRAZYROUTER_API_KEY 可预先设置）
  CRAZYROUTER_API_KEY="${CRAZYROUTER_API_KEY:-}"
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

  info "请在 CrazyRouter 获取 API Key: https://crazyrouter.com"
  CRAZYROUTER_API_KEY=$(read_token "CrazyRouter API Key" "CRAZYROUTER_API_KEY" "请输入 CrazyRouter API Token: ")

  info "请在 Telegram @BotFather 创建 Bot 并获取 Token"
  TELEGRAM_BOT_TOKEN=$(read_token "Telegram Bot Token" "TELEGRAM_BOT_TOKEN" "请输入 Telegram Bot Token: ")

  write_openclaw_config "$OPENCLAW_DATA_DIR" "$CRAZYROUTER_API_KEY" "$TELEGRAM_BOT_TOKEN"

  # 运行方式：已设置 USE_DOCKER 则用环境变量；否则交互选择或按 PREFER_NODE 自动选
  USE_DOCKER="${USE_DOCKER:-}"
  if [ "$USE_DOCKER" != "1" ] && [ "$USE_DOCKER" != "0" ] && [ "$USE_DOCKER" != "yes" ] && [ "$USE_DOCKER" != "no" ] && [ "$USE_DOCKER" != "true" ] && [ "$USE_DOCKER" != "false" ]; then
    # 未显式指定时：有 CI/非交互则自动选，否则让用户选
    if [ -n "${CI:-}" ] || [ ! -t 0 ]; then
      PREFER_NODE="${PREFER_NODE:-0}"
      if [ "$PREFER_NODE" = "1" ] || [ "$PREFER_NODE" = "yes" ] || [ "$PREFER_NODE" = "true" ]; then
        command -v node &>/dev/null && USE_DOCKER=0 || USE_DOCKER=1
      else
        docker_available && USE_DOCKER=1 || USE_DOCKER=0
      fi
    else
      echo ""
      echo "  请选择运行方式："
      echo "    [1] Docker（推荐）— 环境一致、不污染系统、易升级"
      echo "    [2] 本机 Node     — 无容器、占用略小，需已安装 Node.js 22+"
      echo ""
      while true; do
        read -r -p "请输入 1 或 2（直接回车默认选 1）: " choice
        choice=$(echo "${choice:-1}" | tr '[:upper:]' '[:lower:]')
        case "$choice" in
          1|docker) USE_DOCKER=1; break ;;
          2|node)   USE_DOCKER=0; break ;;
          *) warn "请输入 1 或 2。" ;;
        esac
      done
    fi
  fi

  # 用户选了 Docker 但未安装时，在 Linux root 下尝试自动安装
  if [ "$USE_DOCKER" = "1" ] || [ "$USE_DOCKER" = "yes" ] || [ "$USE_DOCKER" = "true" ]; then
    if ! docker_available && [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" = "0" ]; then
      info "正在安装 Docker..."
      ensure_docker
    fi
  fi

  if [ "$USE_DOCKER" = "1" ] || [ "$USE_DOCKER" = "yes" ] || [ "$USE_DOCKER" = "true" ]; then
    run_docker
    RUN_MODE=docker
  else
    run_node
    RUN_MODE=node
  fi

  echo ""
  echo "=============================================="
  echo -e "  ${green}部署完成${nc}"
  echo "=============================================="
  echo "  - 模型: Claude Opus 4.6 (CrazyRouter)"
  echo "  - 网关: http://127.0.0.1:$OPENCLAW_PORT"
  echo "  - 配置: $OPENCLAW_DATA_DIR/openclaw.json"
  echo ""
  echo "  请在 Telegram 中搜索你的 Bot 并发送 /start 开始使用。"
  echo "  私聊需先配对：Bot 会显示配对码，在服务器执行: openclaw pairing approve telegram <配对码>"
  echo ""

  # 可选：立即配对第一个 Telegram 用户（交互模式下询问）
  if [ -t 0 ] && [ -z "${CI:-}" ]; then
    echo "  是否现在配对？请在 Telegram 向你的 Bot 发送 /start，"
    echo "  将显示的配对码（如 QE8E59CF）输入下方，直接回车则跳过。"
    echo ""
    read -r -p "请输入配对码（直接回车跳过）: " pairing_code
    pairing_code=$(echo "$pairing_code" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$pairing_code" ]; then
      if [ "$RUN_MODE" = "docker" ]; then
        if docker exec "$CONTAINER_NAME" openclaw pairing approve telegram "$pairing_code" 2>/dev/null; then
          info "配对成功，该用户已可在私聊中使用 Bot。"
        else
          warn "配对失败，请确认配对码正确且 Bot 已运行。稍后可在服务器执行: docker exec $CONTAINER_NAME openclaw pairing approve telegram <配对码>"
        fi
      else
        if OPENCLAW_HOME="$OPENCLAW_DATA_DIR" openclaw pairing approve telegram "$pairing_code" 2>/dev/null; then
          info "配对成功，该用户已可在私聊中使用 Bot。"
        else
          warn "配对失败，请确认配对码正确且 Gateway 已运行。稍后可在服务器执行: OPENCLAW_HOME=$OPENCLAW_DATA_DIR openclaw pairing approve telegram <配对码>"
        fi
      fi
    fi
  fi
  echo ""
}

main "$@"
