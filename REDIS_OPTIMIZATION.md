# Redis 生产环境配置优化说明

## 概述
已将Redis配置优化为生产环境级别，包含两个独立的Redis实例：
- `redis_market`: 高性能市场数据缓存（无持久化）
- `redis_cache`: 完整持久化缓存服务

## 主要优化项

### 1. 内存配置优化
- **redis_market**: 1.8GB (预留200MB给系统)
- **redis_cache**: 1.8GB (预留200MB给系统)
- 内存淘汰策略: `allkeys-lru`
- 内存采样数: 10 (提高LRU精度)

### 2. 持久化策略
#### redis_market (无持久化)
- 完全关闭RDB和AOF
- `save ""`
- `appendonly no`
- 最高性能，适合实时市场数据

#### redis_cache (完整持久化)
- RDB快照: 1小时1次变更、5分钟100次变更、1分钟10000次变更
- AOF日志: 每秒同步，混合持久化模式
- 数据安全性最高，适合重要缓存数据

### 3. 网络性能优化
- TCP backlog: 2048 (提高并发连接处理)
- TCP keepalive: 300秒
- 连接超时: 300秒
- 最大客户端: 65000

### 4. 线程配置
- IO线程数: 4 (充分利用多核CPU)
- 启用IO线程读取: `io-threads-do-reads yes`

### 5. 内存优化
- 启用惰性释放: `lazyfree-lazy-*`
- 优化数据结构压缩参数
- 客户端输出缓冲区限制

### 6. 安全配置
- 禁用危险命令: FLUSHDB, FLUSHALL, KEYS, CONFIG, DEBUG
- 重命名SHUTDOWN命令
- 保持密码保护

### 7. 监控配置
- 慢查询日志: 记录超过10ms的查询
- 日志级别: warning (redis_market) / notice (redis_cache)

## 资源限制
- 内存限制: 2GB
- CPU限制: 2核
- 内存预留: 512MB
- CPU预留: 0.5核

## 端口映射
- redis_market: 6378:6379
- redis_cache: 6380:6379

## 健康检查
- 检查间隔: 30秒
- 超时时间: 10秒
- 重试次数: 3次
- 启动等待: 30秒

## 使用建议
1. 定期监控内存使用情况
2. 关注慢查询日志
3. 根据实际负载调整配置参数
4. 定期备份redis_cache的持久化文件
5. 监控网络连接数和客户端连接
