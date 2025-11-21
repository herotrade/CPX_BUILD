-- 创建只读账号 public
-- 密码: 123456qwe.

-- 创建用户 (如果不存在)
CREATE USER IF NOT EXISTS 'public'@'%' IDENTIFIED BY '123456qwe.';

-- 授予 cpx_exchange 数据库的只读权限
GRANT SELECT ON cpx_exchange.* TO 'public'@'%';

-- 授予一些必要的元数据查询权限
GRANT SHOW DATABASES ON *.* TO 'public'@'%';
GRANT SHOW VIEW ON cpx_exchange.* TO 'public'@'%';

-- 刷新权限
FLUSH PRIVILEGES;
