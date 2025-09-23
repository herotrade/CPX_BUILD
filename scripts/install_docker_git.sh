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
    log "docker 已安装，跳过。"
  else
    log "开始安装 docker..."
    if command_exists apt-get; then
      sudo apt-get update
      sudo apt-get install -y docker.io
    elif command_exists yum; then
      sudo yum install -y docker
    elif command_exists dnf; then
      sudo dnf install -y docker
    elif command_exists pacman; then
      sudo pacman -Sy --noconfirm docker
    elif command_exists zypper; then
      sudo zypper install -y docker
    elif command_exists brew; then
      brew install --cask docker
      log "请手动启动 Docker.app 并完成初始化。"
    else
      log "未检测到可用的包管理器，尝试官方安装脚本。"
      curl -fsSL https://get.docker.com | sh
    fi
  fi

  if command_exists systemctl; then
    if ! sudo systemctl is-active --quiet docker; then
      log "尝试启动 docker 服务..."
      sudo systemctl enable --now docker
    fi
  fi
}

main() {
  install_git
  install_docker
  log "依赖安装完成。"
}

main "$@"
