# OpenClaw Gateway - 用于一键部署脚本的镜像
# 使用 CrazyRouter + Claude Opus 4.6，配置由宿主机挂载到 /root/.openclaw

FROM node:22-bookworm-slim

# openclaw 安装时 npm 会用到 git（部分依赖或脚本）
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest

# 配置通过 -v 挂载到 /root/.openclaw
WORKDIR /root/.openclaw

EXPOSE 18789

ENTRYPOINT ["openclaw", "gateway", "--port", "18789"]
