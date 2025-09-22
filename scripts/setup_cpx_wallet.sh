#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/herotrade/CPX_WALLET.git"
REPO_DIR="${REPO_DIR:-$PWD/CPX_WALLET}"
BRANCH="${BRANCH:-master}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

ensure_git_installed() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  log "git 未安装，尝试自动安装..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y git
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y git
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y git
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y git
  elif command -v brew >/dev/null 2>&1; then
    brew update
    brew install git
  else
    log "无法自动安装 git，请手动安装后重新运行脚本。"
    exit 1
  fi
}

ensure_git_installed

if [ -d "$REPO_DIR/.git" ]; then
  log "检测到已存在仓库目录 $REPO_DIR，执行更新。"
  git -C "$REPO_DIR" fetch --all --prune
else
  log "开始克隆仓库到 $REPO_DIR。"
  git clone "$REPO_URL" "$REPO_DIR"
fi

log "切换到分支 $BRANCH 并拉取最新代码。"
git -C "$REPO_DIR" checkout "$BRANCH"
git -C "$REPO_DIR" pull --ff-only origin "$BRANCH"

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN=(docker-compose)
  else
    log "找不到 docker compose 命令，请安装 Docker Compose 后重试。"
    exit 1
  fi
else
  log "找不到 docker 命令，请先安装 Docker。"
  exit 1
fi

if ! docker network ls --format '{{.Name}}' | grep -q '^data_network$'; then
  log "检测不到 data_network，尝试创建共享网络。"
  docker network create data_network
fi

log "启动 Docker Compose 服务。"
"${COMPOSE_BIN[@]}" -f "$REPO_DIR/docker-compose.yml" up -d

log "完成。"
