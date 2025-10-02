#!/bin/bash

# 初始化所有容器需要的目录并设置权限
# Elasticsearch 需要 UID 1000 的权限

set -e

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
echo "正在启动容器..."
docker-compose -f runner-compose.yml up -d

echo ""
echo "✓ 部署完成!"
echo "查看状态: docker-compose -f runner-compose.yml ps"
echo "查看日志: docker-compose -f runner-compose.yml logs -f"
