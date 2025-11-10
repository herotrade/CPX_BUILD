#!/bin/bash

# 初始化所有容器需要的目录并设置权限
# Elasticsearch 需要 UID 1000 的权限

set -euo pipefail

CONFIG_FILES=(
  "runner-compose.yml"
  "redis_cache/redis.conf"
  "redis_market/redis.conf"
)

NGINX_TEMPLATE="nginx/conf.d/cpx_exchange.temp.conf"
NGINX_CONFIG="nginx/conf.d/cpx_exchange.conf"

APP_REPO_URL=${APP_REPO_URL:-https://github.com/herotrade/CPX_EXCHANGE.git}
APP_REPO_BRANCH=${APP_REPO_BRANCH:-prod}
APP_CLONE_DIR=${APP_CLONE_DIR:-/app}

COMPOSE_BIN=()

ensure_docker_env() {
  if command -v docker >/dev/null 2>&1; then
    echo "✓ 已检测到 Docker: $(docker --version | head -n1)"
  else
    echo "未检测到 Docker，正在执行安装脚本..."
    if [ ! -x "./scripts/install_docker_git.sh" ]; then
      chmod +x ./scripts/install_docker_git.sh
    fi
    ./scripts/install_docker_git.sh
  fi

  detect_compose() {
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_BIN=(docker compose)
      return 0
    elif command -v docker-compose >/dev/null 2>&1; then
      COMPOSE_BIN=(docker-compose)
      return 0
    fi
    return 1
  }

  if ! detect_compose; then
    echo "未检测到 Docker Compose，尝试安装..."
    if [ ! -x "./scripts/install_docker_git.sh" ]; then
      chmod +x ./scripts/install_docker_git.sh
    fi
    ./scripts/install_docker_git.sh
    if ! detect_compose; then
      echo "错误: 无法检测到 Docker Compose，请确认安装成功后重试。" >&2
      exit 1
    fi
  fi

  local compose_version
  compose_version=$("${COMPOSE_BIN[@]}" version | head -n1)
  echo "✓ Docker Compose 可用: $compose_version"
  echo ""
}

ensure_config_files() {
  local missing=false
  for file in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      echo "未检测到必要配置文件: $file"
      missing=true
    fi
  done

  if [ "$missing" = true ]; then
    echo "正在自动生成配置文件..."
    if [ ! -x "./scripts/generate_runner_passwords.sh" ]; then
      chmod +x ./scripts/generate_runner_passwords.sh
    fi
    ./scripts/generate_runner_passwords.sh
  fi

  for file in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      echo "错误: 仍未找到 $file，请检查模板或手动生成后重试。" >&2
      exit 1
    fi
  done

  echo "✓ 所有配置文件已准备就绪"
  echo ""
}

ensure_nginx_config() {
  if [ -f "$NGINX_CONFIG" ]; then
    echo "✓ Nginx 配置已存在: $NGINX_CONFIG"
    echo ""
    return
  fi

  if [ ! -f "$NGINX_TEMPLATE" ]; then
    echo "错误: 找不到 Nginx 模板文件: $NGINX_TEMPLATE" >&2
    exit 1
  fi

  echo "未检测到 Nginx 配置文件，将启动交互式配置..."
  if [ ! -x "./scripts/configure_nginx_domains.sh" ]; then
    chmod +x ./scripts/configure_nginx_domains.sh
  fi

  NGINX_TEMPLATE="$NGINX_TEMPLATE" NGINX_OUTPUT="$NGINX_CONFIG" ./scripts/configure_nginx_domains.sh

  if [ ! -f "$NGINX_CONFIG" ]; then
    echo "错误: 生成 Nginx 配置失败，请检查脚本输出后重试。" >&2
    exit 1
  fi

  echo "✓ 已生成 Nginx 配置: $NGINX_CONFIG"
  echo ""
}

prepare_directories() {
  echo "正在初始化容器卷目录..."

  # 创建 Redis 市场数据目录
  mkdir -p ./redis_market/data
  chmod -R 755 ./redis_market/data

  # 创建 Redis 缓存目录
  mkdir -p ./redis_cache/data
  chmod -R 755 ./redis_cache/data

  # 创建 Elasticsearch 目录并设置权限 (UID 1000)
  mkdir -p ./elasticsearch/data
  mkdir -p ./elasticsearch/logs
  chmod -R 777 ./elasticsearch/data
  chmod -R 777 ./elasticsearch/logs
  chown -R 1000:1000 ./elasticsearch/data 2>/dev/null || true
  chown -R 1000:1000 ./elasticsearch/logs 2>/dev/null || true

  # 创建 MySQL 目录
  mkdir -p ./mysql/data
  mkdir -p ./mysql/logs
  chmod -R 755 ./mysql/data
  chmod -R 755 ./mysql/logs

  # 创建日志目录
  mkdir -p ./logs/manager
  chmod -R 755 ./logs/manager

  echo "✓ 所有目录已创建并设置权限"
  echo ""
}

start_containers() {
  echo "正在启动容器..."
  "${COMPOSE_BIN[@]}" -f runner-compose.yml up -d
  echo ""
  echo "✓ 部署完成!"
  echo "查看状态: ${COMPOSE_BIN[*]} -f runner-compose.yml ps"
  echo "查看日志: ${COMPOSE_BIN[*]} -f runner-compose.yml logs -f"
}

sync_app_repo() {
  echo "正在同步应用代码..."
  if ! command -v git >/dev/null 2>&1; then
    echo "错误: 未检测到 git，请确认 scripts/install_docker_git.sh 已正确运行。" >&2
    exit 1
  fi

  local repo_dir="$APP_CLONE_DIR"
  local branch="$APP_REPO_BRANCH"
  local repo="$APP_REPO_URL"

  if [ -d "$repo_dir/.git" ]; then
    echo "检测到已存在仓库，正在更新 ${repo_dir} ..."
    git -C "$repo_dir" fetch --all --prune
    git -C "$repo_dir" checkout "$branch"
    git -C "$repo_dir" pull --ff-only origin "$branch"
  else
    if [ -d "$repo_dir" ] && [ "$(ls -A "$repo_dir" 2>/dev/null)" ]; then
      echo "错误: 目录 ${repo_dir} 已存在且包含内容，无法在其中克隆仓库。" >&2
      exit 1
    fi
    rm -rf "$repo_dir"
    mkdir -p "$(dirname "$repo_dir")"
    echo "首次拉取 ${repo} (${branch}) 至 ${repo_dir} ..."
    git clone --branch "$branch" --single-branch "$repo" "$repo_dir"
  fi

  echo "✓ 应用代码已同步到 ${repo_dir}"
  echo ""
}

ensure_docker_env
ensure_config_files
ensure_nginx_config
prepare_directories
sync_app_repo
start_containers
