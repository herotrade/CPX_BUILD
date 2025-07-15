# Docker Compose 操作文档

## 基本启动命令

### 启动所有服务
```bash
# 后台启动所有服务
docker compose -f runner-compose.yml up -d

# 前台启动（查看实时日志）
docker compose -f runner-compose.yml up
```

### 启动特定服务
```bash
# 只启动Redis服务
docker compose -f runner-compose.yml up -d redis_market redis_cache

# 只启动Elasticsearch相关服务
docker compose -f runner-compose.yml up -d elasticsearch elasticvue
```

## 服务管理命令

### 查看服务状态
```bash
# 查看所有服务状态
docker compose -f runner-compose.yml ps

# 查看详细状态
docker compose -f runner-compose.yml ps -a
```

### 停止服务
```bash
# 停止所有服务
docker compose -f runner-compose.yml stop

# 停止特定服务
docker compose -f runner-compose.yml stop elasticsearch

# 停止并删除容器
docker compose -f runner-compose.yml down
```

### 重启服务
```bash
# 重启所有服务
docker compose -f runner-compose.yml restart

# 重启特定服务
docker compose -f runner-compose.yml restart redis_market
```

## 日志管理

### 查看日志
```bash
# 查看所有服务日志
docker compose -f runner-compose.yml logs

# 查看特定服务日志
docker compose -f runner-compose.yml logs elasticsearch

# 实时跟踪日志
docker compose -f runner-compose.yml logs -f

# 查看最近100行日志
docker compose -f runner-compose.yml logs --tail=100
```

## 容器操作

### 进入容器
```bash
# 进入Redis容器
docker exec -it redis_market redis-cli -a DmUYTbggA6JMPDrkmqykuLfgp5raj3

# 进入Elasticsearch容器
docker exec -it elasticsearch_kline bash

# 进入任意容器的shell
docker exec -it <容器名> sh
```

### 资源监控
```bash
# 查看所有容器资源使用
docker stats

# 查看特定容器资源使用
docker stats redis_market elasticsearch_kline
```

## 数据管理

### 备份数据
```bash
# 备份Redis数据
docker exec redis_cache redis-cli -a DmUYTbggA6JMPDrkmqykuLfgp5raj3 BGSAVE

# 备份Elasticsearch数据
docker exec elasticsearch_kline curl -u elastic:DmUYTbggA6JMPDrkmqykuLfgp5raj3 -X PUT "localhost:9200/_snapshot/backup"
```

### 清理数据
```bash
# 停止服务并删除数据卷
docker compose -f runner-compose.yml down -v

# 清理未使用的镜像和容器
docker system prune -a
```

## 服务访问地址

| 服务 | 地址 | 用途 |
|------|------|------|
| Redis Market | localhost:6378 | 市场数据缓存 |
| Redis Cache | localhost:6380 | 通用缓存 |
| Elasticsearch | localhost:9200 | K线数据存储 |
| ElasticVue | http://localhost:8080 | ES管理界面 |
| LibreTranslate | http://localhost:9000 | 翻译服务 |
| RocketMQ NameServer | localhost:9876 | 消息队列注册中心 |
| RocketMQ Broker | localhost:10911 | 消息队列代理 |

## 故障排查

### 健康检查
```bash
# 检查服务健康状态
docker compose -f runner-compose.yml ps

# 测试Redis连接
docker exec redis_market redis-cli -a DmUYTbggA6JMPDrkmqykuLfgp5raj3 ping

# 测试Elasticsearch连接
curl -u elastic:DmUYTbggA6JMPDrkmqykuLfgp5raj3 http://localhost:9200/_cluster/health
```

### 常用排查命令
```bash
# 查看容器详细信息
docker inspect <容器名>

# 查看网络信息
docker network ls
docker network inspect cpx_build_data_network

# 查看数据卷
docker volume ls
```

## 更新和维护

### 更新镜像
```bash
# 拉取最新镜像
docker compose -f runner-compose.yml pull

# 重新构建并启动
docker compose -f runner-compose.yml up -d --force-recreate
```

### 配置更新
```bash
# 配置文件修改后重启相关服务
docker compose -f runner-compose.yml restart <服务名>

# 重新加载配置
docker compose -f runner-compose.yml up -d --force-recreate <服务名>
```

## 容器列表

总共7个容器实例：
1. **redis_market** - Redis市场数据缓存
2. **redis_cache** - Redis通用缓存  
3. **elasticsearch_kline** - Elasticsearch K线数据存储
4. **elasticvue** - Elasticsearch管理界面
5. **libretranslate** - 翻译服务
6. **rocketmq-nameserver** - RocketMQ注册中心
7. **rocketmq-broker** - RocketMQ消息代理

## 快速启动指南

1. 确保Docker已安装并运行
2. 在项目根目录执行：`docker compose -f runner-compose.yml up -d`
3. 等待所有服务启动完成（约2-3分钟）
4. 通过 `docker compose -f runner-compose.yml ps` 检查服务状态
5. 访问各服务的Web界面进行验证
