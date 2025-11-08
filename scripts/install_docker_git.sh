#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_git() {
  if command_exists git; then
    log "git 已安装，跳过。"
    return
  fi

  log "开始安装 git..."
  if command_exists apt-get; then
    sudo apt-get update
    sudo apt-get install -y git
  elif command_exists yum; then
    sudo yum install -y git
  elif command_exists dnf; then
    sudo dnf install -y git
  elif command_exists pacman; then
    sudo pacman -Sy --noconfirm git
  elif command_exists zypper; then
    sudo zypper install -y git
  elif command_exists brew; then
    brew update
    brew install git
  else
    log "未检测到可用的包管理器，请手动安装 git。"
    exit 1
  fi
}

install_docker() {
  if command_exists docker; then
    log "docker 已安装: $(docker --version)"
  else
    log "开始安装最新稳定版 docker..."
    if [ "$(uname -s)" = "Darwin" ] && command_exists brew; then
      brew install --cask docker
    else
      if ! command_exists curl; then
        log "未检测到 curl，无法通过官方脚本安装 docker。请先安装 curl。"
        exit 1
      fi
      curl -fsSL https://get.docker.com | sudo sh
    fi
  fi

  if command_exists systemctl; then
    if ! sudo systemctl is-active --quiet docker; then
      log "尝试启动 docker 服务..."
      sudo systemctl enable --now docker
    fi
  fi

  configure_docker_storage
}

install_compose() {
  if ! command_exists docker; then
    log "未检测到 docker，无法安装 Docker Compose。"
    return
  fi

  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose v2 已安装: $(docker compose version | head -n1)"
    return
  fi

  if ! command_exists curl; then
    log "未检测到 curl，无法下载安装 Docker Compose。"
    exit 1
  fi

  local compose_version="${DOCKER_COMPOSE_VERSION:-v2.29.2}"
  local uname_s
  local uname_m
  uname_s=$(uname -s | tr '[:upper:]' '[:lower:]')
  uname_m=$(uname -m)

  case "$uname_m" in
    x86_64|amd64)
      uname_m="x86_64"
      ;;
    arm64|aarch64)
      uname_m="aarch64"
      ;;
    *)
      log "暂不支持的架构: $uname_m"
      exit 1
      ;;
  esac

  log "Docker Compose v2 未检测到，开始安装 ${compose_version}..."

  local binary_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-${uname_s}-${uname_m}"
  local plugin_dir=""

  if [ "$uname_s" = "linux" ]; then
    plugin_dir="/usr/local/lib/docker/cli-plugins"
    if [ "$(id -u)" -ne 0 ]; then
      sudo mkdir -p "$plugin_dir"
      sudo curl -fsSL "$binary_url" -o "${plugin_dir}/docker-compose"
      sudo chmod +x "${plugin_dir}/docker-compose"
    else
      mkdir -p "$plugin_dir"
      curl -fsSL "$binary_url" -o "${plugin_dir}/docker-compose"
      chmod +x "${plugin_dir}/docker-compose"
    fi
  elif [ "$uname_s" = "darwin" ]; then
    plugin_dir="${HOME}/.docker/cli-plugins"
    mkdir -p "$plugin_dir"
    curl -fsSL "$binary_url" -o "${plugin_dir}/docker-compose"
    chmod +x "${plugin_dir}/docker-compose"
  else
    log "暂不支持的系统: $uname_s"
    exit 1
  fi

  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose v2 安装完成: $(docker compose version | head -n1)"
  else
    log "Docker Compose v2 安装失败，请参考 https://docs.docker.com/compose/install/ 手动安装。"
  fi
}

read_current_data_root() {
  local daemon_file="/etc/docker/daemon.json"
  local config=""
  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    config=$(sudo cat "$daemon_file" 2>/dev/null || true)
  else
    config=$(cat "$daemon_file" 2>/dev/null || true)
  fi

  if [ -z "$config" ]; then
    return
  fi

  local interpreter=""
  if command_exists python3; then
    interpreter="python3"
  elif command_exists python; then
    interpreter="python"
  fi

  if [ -z "$interpreter" ]; then
    return
  fi

  printf '%s' "$config" | "$interpreter" <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
value = data.get("data-root")
if value:
    print(value)
PY
}

prompt_docker_data_root() {
  local default_dir="$1"
  local env_dir="${DOCKER_DATA_ROOT:-}"
  local input_dir=""

  if [ -n "$env_dir" ]; then
    log "检测到环境变量 DOCKER_DATA_ROOT，将使用: $env_dir"
    input_dir="$env_dir"
  elif [ -t 0 ]; then
    read -r -p "请输入 Docker 数据/容器存储目录 (默认: ${default_dir}): " input_dir
  else
    log "未检测到交互式终端，将使用默认 Docker 数据目录: $default_dir"
  fi

  if [ -z "$input_dir" ]; then
    input_dir="$default_dir"
  fi

  printf '%s\n' "$input_dir"
}

ensure_docker_data_dir() {
  local data_dir="$1"
  local owner_cmd=""
  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    owner_cmd="sudo"
  fi

  if [ -n "$owner_cmd" ]; then
    $owner_cmd mkdir -p "$data_dir"
    $owner_cmd chown root:root "$data_dir" 2>/dev/null || true
  else
    mkdir -p "$data_dir"
    chown root:root "$data_dir" 2>/dev/null || true
  fi

  if [ -n "$owner_cmd" ]; then
    $owner_cmd chmod 711 "$data_dir" 2>/dev/null || true
  else
    chmod 711 "$data_dir" 2>/dev/null || true
  fi
}

write_daemon_config_data_root() {
  local data_dir="$1"
  local daemon_file="/etc/docker/daemon.json"
  local config="{}"

  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    config=$(sudo cat "$daemon_file" 2>/dev/null || true)
  else
    config=$(cat "$daemon_file" 2>/dev/null || true)
  fi

  if [ -z "$config" ]; then
    config="{}"
  fi

  local interpreter=""
  if command_exists python3; then
    interpreter="python3"
  elif command_exists python; then
    interpreter="python"
  fi

  local updated_config=""
  if [ -n "$interpreter" ]; then
    updated_config="$(printf '%s' "$config" | DATA_ROOT="$data_dir" "$interpreter" <<'PY'
import json, os, sys
raw = sys.stdin.read().strip()
if not raw:
    raw = "{}"
try:
    data = json.loads(raw)
except Exception:
    data = {}
data["data-root"] = os.environ["DATA_ROOT"]
print(json.dumps(data, indent=2))
PY
)"
  else
    updated_config=$(cat <<EOF
{
  "data-root": "$data_dir"
}
EOF
)
  fi

  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    printf '%s\n' "$updated_config" | sudo tee "$daemon_file" >/dev/null
  else
    printf '%s\n' "$updated_config" > "$daemon_file"
  fi
}

restart_docker_service() {
  if command_exists systemctl; then
    log "重启 docker 服务以应用新的数据目录..."
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl restart docker
  elif command_exists service; then
    log "通过 service 重启 docker 服务以应用新的数据目录..."
    sudo service docker restart
  else
    log "请手动重启 docker 服务以应用新的数据目录。"
  fi
}

configure_docker_storage() {
  if ! command_exists docker; then
    return
  fi

  local os_name
  os_name=$(uname -s)
  if [ "$os_name" != "Linux" ]; then
    log "当前系统 ${os_name} 由 Docker Desktop 管理存储，若需更改目录请在 Docker Desktop 中设置。"
    return
  fi

  local current_root
  current_root=$(read_current_data_root 2>/dev/null || true)
  local default_root="${current_root:-/var/lib/docker}"
  local data_root
  data_root=$(prompt_docker_data_root "$default_root")
  data_root="${data_root%/}"

  if [ -z "$data_root" ]; then
    data_root="$default_root"
  fi

  if [ "${data_root#/}" = "$data_root" ]; then
    if command_exists realpath; then
      data_root=$(realpath -m "$data_root")
    else
      data_root="$(pwd)/$data_root"
    fi
  fi

  if [ -n "$current_root" ] && [ "$data_root" = "$current_root" ]; then
    log "Docker 数据/容器目录保持为: $data_root"
    return
  fi

  log "Docker 数据/容器目录将设置为: $data_root"
  ensure_docker_data_dir "$data_root"

  if [ -n "$current_root" ] && [ "$data_root" != "$current_root" ]; then
    log "提示: 变更存储目录不会自动迁移旧数据 ($current_root)，如需保留请自行迁移。"
  fi

  write_daemon_config_data_root "$data_root"
  restart_docker_service
  log "Docker 数据/容器目录已更新为: $data_root"
}

main() {
  install_git
  install_docker
  install_compose
  log "依赖安装完成。"
}

main "$@"
