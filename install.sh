#!/bin/bash

# CPX Exchange 交互式安装脚本
# 基于 deployment.md 流程

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 生成随机密钥函数
generate_random_key() {
    local length=$1
    openssl rand -base64 "$length" | tr -d '\n'
}

# 获取配置文件中的值
get_config_value() {
    local file=$1
    local key=$2

    if [ ! -f "$file" ]; then
        echo ""
        return 1
    fi

    # 读取配置值
    grep "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2- | head -1
}

# 交互式输入函数（带默认值，支持当前值）
ask_input() {
    local prompt=$1
    local default=$2
    local current=$3  # 当前值（可选）
    local value
    local allow_empty=false

    # 检查第4个参数，是否允许空值
    if [ "$4" = "allow_empty" ]; then
        allow_empty=true
    fi

    # 始终展示当前值（输出到 stderr 避免被变量捕获）
    if [ -n "$current" ]; then
        log_info "当前值: $current" >&2
    else
        log_info "当前值: (未设置)" >&2
    fi

    if [ -n "$default" ]; then
        # 同时存在默认值和当前值
        if [ -n "$current" ]; then
            log_info "提示: 回车（保持当前值）, 输入'd'（使用默认值($default)）, 输入新值（设置新值）" >&2
            read -p "$prompt: " value

            if [ -z "$value" ]; then
                # 直接回车 - 保持当前值
                echo "$current"
            elif [ "$value" = "d" ] || [ "$value" = "D" ]; then
                # 输入 d - 使用默认值
                echo "$default"
            else
                # 输入其他 - 使用新值
                echo "$value"
            fi
        else
            # 只有默认值，没有当前值
            read -p "$prompt [默认: $default, 直接回车使用默认值]: " value
            if [ -z "$value" ]; then
                echo "$default"
            else
                echo "$value"
            fi
        fi
    else
        # 没有默认值的情况
        if [ "$allow_empty" = true ]; then
            read -p "$prompt [直接回车保持当前值]: " value
            if [ -z "$value" ]; then
                echo "$current"
            else
                echo "$value"
            fi
        else
            read -p "$prompt: " value
            while [ -z "$value" ]; do
                log_warn "输入不能为空，请重新输入" >&2
                read -p "$prompt: " value
            done
            echo "$value"
        fi
    fi
}

# 询问是否确认（y/n）
ask_confirm() {
    local prompt=$1
    local response
    read -p "$prompt (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 替换配置文件中的值（带修改明细展示）
replace_config() {
    local file=$1
    local key=$2
    local value=$3
    local old_value

    if [ ! -f "$file" ]; then
        log_error "配置文件不存在: $file"
        return 1
    fi

    # 获取旧值
    old_value=$(get_config_value "$file" "$key")

    # 转义特殊字符（处理空值）
    local value_escaped=""
    if [ -n "$value" ]; then
        value_escaped=$(echo "$value" | sed 's/[\/&]/\\&/g')
    fi

    # 检查是否存在该配置项
    if grep -q "^${key}=" "$file"; then
        # 如果值相同，跳过修改
        if [ "$old_value" = "$value" ]; then
            log_info "  $key: 保持不变"
            return 0
        fi

        # 使用 | 作为分隔符避免冲突
        sed -i "s|^${key}=.*|${key}=${value_escaped}|" "$file"
        echo -e "${GREEN}  ✓ ${key}${NC}"
        if [ -n "$old_value" ]; then
            echo "    旧值: ${old_value}"
        else
            echo "    旧值: (空)"
        fi
        if [ -n "$value" ]; then
            echo "    新值: ${value}"
        else
            echo "    新值: (空)"
        fi
    else
        echo "${key}=${value}" >> "$file"
        echo -e "${GREEN}  ✓ 新增 ${key}${NC}"
        if [ -n "$value" ]; then
            echo "    值: ${value}"
        else
            echo "    值: (空)"
        fi
    fi
}

# 替换 Nginx 配置中的 server_name
replace_nginx_server_name() {
    local file=$1
    local domain=$2

    if [ ! -f "$file" ]; then
        log_error "Nginx 配置文件不存在: $file"
        return 1
    fi

    # 使用 sed 按行号直接替换，避免复杂的模式匹配
    # 第1个 server_name (API) - 行49
    sed -i "49s|^.*server_name.*;|    server_name api.${domain};|" "$file"

    # 第2个 server_name (Manager) - 行86
    sed -i "86s|^.*server_name.*;|    server_name manager.${domain};|" "$file"

    # 第3个 server_name (H5) - 行114
    sed -i "114s|^.*server_name.*;|    server_name h5.${domain};|" "$file"

    # 第4个 server_name (APP) - 行142
    sed -i "142s|^.*server_name.*;|    server_name app.${domain};|" "$file"

    log_info "Nginx 配置已更新为域名: $domain"
    log_info "  - API: api.$domain"
    log_info "  - Manager: manager.$domain"
    log_info "  - H5: h5.$domain"
    log_info "  - APP: app.$domain"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ====================================
# 主流程开始
# ====================================

clear
echo "======================================"
echo "  CPX Exchange 交互式安装脚本"
echo "======================================"
echo ""

# 检查是否在正确的目录
EXPECTED_DIR="/data/CPX_BUILD"
CURRENT_DIR=$(pwd)

if [ "$CURRENT_DIR" != "$EXPECTED_DIR" ]; then
    log_warn "当前目录: $CURRENT_DIR"
    log_warn "建议在 $EXPECTED_DIR 目录下运行此脚本"
    if ! ask_confirm "是否继续？"; then
        exit 0
    fi
fi

# ====================================
# 1. 创建目录
# ====================================
log_info "步骤 1/6: 创建容器卷目录..."
echo ""

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

log_info "目录创建完成"
echo ""

# ====================================
# 2. 安装 Docker
# ====================================
log_info "步骤 2/6: 检查 Docker 安装..."
echo ""

if command_exists docker; then
    log_info "Docker 已安装: $(docker --version)"
    if ! ask_confirm "是否重新安装 Docker？"; then
        log_info "跳过 Docker 安装"
    else
        log_info "正在安装 Docker..."
        curl -fsSL https://get.docker.com | sudo sh
        log_info "Docker 安装完成"
    fi
else
    log_info "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sudo sh
    log_info "Docker 安装完成"
fi

# 检查 Docker Compose
if command_exists docker; then
    if ! docker compose version >/dev/null 2>&1; then
        log_warn "Docker Compose 未安装或版本过旧"
        log_warn "建议安装 Docker Compose V2"
        log_warn "您可以稍后手动安装: https://docs.docker.com/compose/install/"
    else
        log_info "Docker Compose 已安装: $(docker compose version)"
    fi
fi
echo ""

# ====================================
# 3. 修改 Nginx 配置
# ====================================
log_info "步骤 3/6: 配置 Nginx 域名..."
echo ""

NGINX_CONF="./nginx/conf.d/cpx_exchange.conf"
DOMAIN=$(ask_input "请输入域名（例如：xxx.com）" "")

if [ -f "$NGINX_CONF" ]; then
    replace_nginx_server_name "$NGINX_CONF" "$DOMAIN"
else
    log_warn "Nginx 配置文件不存在: $NGINX_CONF"
    log_warn "请手动配置 Nginx"
fi
echo ""

# ====================================
# 4. 拉取服务端代码
# ====================================
log_info "步骤 4/6: 拉取服务端代码..."
echo ""

log_warn "提示: 如果仓库是私有的，克隆时会要求输入:"
log_warn "  - Username: 你的 GitHub 用户名"
log_warn "  - Password: 你的 Personal Access Token (不是账号密码)"
log_warn "  - 获取 Token: https://github.com/settings/tokens"
echo ""

# 创建 app 目录
mkdir -p app
cd app

# 拉取 CPX_EXCHANGE
if [ ! -d "CPX_EXCHANGE" ] || [ ! "$(ls -A CPX_EXCHANGE 2>/dev/null)" ]; then
    log_info "正在克隆 CPX_EXCHANGE (dev 分支)..."
    if ! git clone -b dev https://github.com/herotrade/CPX_EXCHANGE.git; then
        log_error "克隆 CPX_EXCHANGE 失败"
        log_error "请检查网络连接和仓库访问权限"
        exit 1
    fi
    cd CPX_EXCHANGE
    # 删除脑图
    rm -rf *.emmx
    cd ..
    log_info "CPX_EXCHANGE 克隆完成"
else
    log_info "CPX_EXCHANGE 已存在，跳过克隆"
fi

# 拉取 CPX_GO_SERVER
if [ ! -d "CPX_GO_SERVER" ] || [ ! "$(ls -A CPX_GO_SERVER 2>/dev/null)" ]; then
    log_info "正在克隆 CPX_GO_SERVER..."
    if ! git clone https://github.com/herotrade/CPX_GO_SERVER.git; then
        log_error "克隆 CPX_GO_SERVER 失败"
        log_error "请检查网络连接和仓库访问权限"
        exit 1
    fi
    log_info "CPX_GO_SERVER 克隆完成"
else
    log_info "CPX_GO_SERVER 已存在，跳过克隆"
fi

# 返回主目录
cd ..
log_info "代码拉取完成"
echo ""

# ====================================
# 5. 修改配置
# ====================================
log_info "步骤 5/6: 配置应用参数..."
echo ""

# 配置文件路径
CPX_EXCHANGE_ENV="./app/CPX_EXCHANGE/prod.env"
CPX_GO_SERVER_ENV="./app/CPX_GO_SERVER/prod.env"
RUNNER_COMPOSE="./runner-compose.yml"

# 检查配置文件是否存在
if [ ! -f "$CPX_EXCHANGE_ENV" ]; then
    log_error "配置文件不存在: $CPX_EXCHANGE_ENV"
    exit 1
fi

if [ ! -f "$CPX_GO_SERVER_ENV" ]; then
    log_error "配置文件不存在: $CPX_GO_SERVER_ENV"
    exit 1
fi

if [ ! -f "$RUNNER_COMPOSE" ]; then
    log_error "配置文件不存在: $RUNNER_COMPOSE"
    exit 1
fi

# 应用名称
log_info "配置应用基本信息..."
echo ""
CURRENT_APP_NAME=$(get_config_value "$CPX_EXCHANGE_ENV" "APP_NAME")
APP_NAME=$(ask_input "应用名称（APP_NAME）" "AlgoQuant" "$CURRENT_APP_NAME")
echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "APP_NAME" "$APP_NAME"
echo ""

# MySQL root 密码
log_info "配置 MySQL 数据库密码..."
echo ""
CURRENT_DB_PASSWORD=$(get_config_value "$CPX_EXCHANGE_ENV" "DB_PASSWORD")
DEFAULT_DB_PASSWORD=$(generate_random_key 48)
DB_PASSWORD=$(ask_input "MySQL root 密码（DB_PASSWORD）" "$DEFAULT_DB_PASSWORD" "$CURRENT_DB_PASSWORD")
echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "DB_PASSWORD" "$DB_PASSWORD"
replace_config "$CPX_GO_SERVER_ENV" "DB_PASSWORD" "$DB_PASSWORD"

# 转义密码中的特殊字符用于 sed（转义 \ & / |）
DB_PASSWORD_ESCAPED=$(echo "$DB_PASSWORD" | sed 's/[\/&|]/\\&/g')

# 更新 runner-compose.yml 中的 MYSQL_ROOT_PASSWORD（环境变量格式）
OLD_MYSQL_ROOT=$(grep "MYSQL_ROOT_PASSWORD=" "$RUNNER_COMPOSE" | cut -d'=' -f2)
if grep -q "MYSQL_ROOT_PASSWORD=" "$RUNNER_COMPOSE"; then
    sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${DB_PASSWORD_ESCAPED}|" "$RUNNER_COMPOSE"
    echo -e "${GREEN}  ✓ runner-compose.yml: MYSQL_ROOT_PASSWORD${NC}"
    echo "    旧值: ${OLD_MYSQL_ROOT}"
    echo "    新值: ${DB_PASSWORD}"
fi
# 更新 healthcheck 中的密码（YAML数组格式）
if grep -q '"-p.*",' "$RUNNER_COMPOSE"; then
    sed -i "s|\"-p[^\"]*\",|\"-p${DB_PASSWORD_ESCAPED}\",|" "$RUNNER_COMPOSE"
    echo -e "${GREEN}  ✓ runner-compose.yml: MySQL healthcheck 密码已同步${NC}"
fi
echo ""

# MySQL cpx_exchange 密码
log_info "配置 MySQL 用户密码..."
echo ""
CURRENT_MYSQL_PASSWORD=$(grep "MYSQL_PASSWORD=" "$RUNNER_COMPOSE" | cut -d'=' -f2 | head -1)
DEFAULT_MYSQL_PASSWORD=$(generate_random_key 48)
MYSQL_PASSWORD=$(ask_input "MySQL cpx_exchange 密码（MYSQL_PASSWORD）" "$DEFAULT_MYSQL_PASSWORD" "$CURRENT_MYSQL_PASSWORD")
echo ""
log_info "更新配置文件..."
MYSQL_PASSWORD_ESCAPED=$(echo "$MYSQL_PASSWORD" | sed 's/[\/&|]/\\&/g')
OLD_MYSQL_USER_PASS=$(grep "MYSQL_PASSWORD=" "$RUNNER_COMPOSE" | cut -d'=' -f2 | head -1)
if grep -q "MYSQL_PASSWORD=" "$RUNNER_COMPOSE"; then
    sed -i "s|MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${MYSQL_PASSWORD_ESCAPED}|" "$RUNNER_COMPOSE"
    echo -e "${GREEN}  ✓ runner-compose.yml: MYSQL_PASSWORD${NC}"
    echo "    旧值: ${OLD_MYSQL_USER_PASS}"
    echo "    新值: ${MYSQL_PASSWORD}"
fi
echo ""

# 应用地址
log_info "配置应用访问地址..."
echo ""
CURRENT_APP_URL=$(get_config_value "$CPX_EXCHANGE_ENV" "APP_URL")
DEFAULT_APP_URL="https://api.${DOMAIN}"
APP_URL=$(ask_input "应用地址（APP_URL）" "$DEFAULT_APP_URL" "$CURRENT_APP_URL")
echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "APP_URL" "$APP_URL"
echo ""

# JWT_SECRET
log_info "配置 JWT 密钥..."
echo ""
CURRENT_JWT_SECRET=$(get_config_value "$CPX_EXCHANGE_ENV" "JWT_SECRET")
DEFAULT_JWT_SECRET=$(generate_random_key 64)
JWT_SECRET=$(ask_input "JWT_SECRET" "$DEFAULT_JWT_SECRET" "$CURRENT_JWT_SECRET")
echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "JWT_SECRET" "$JWT_SECRET"
echo ""

# JWT_API_SECRET
CURRENT_JWT_API_SECRET=$(get_config_value "$CPX_EXCHANGE_ENV" "JWT_API_SECRET")
DEFAULT_JWT_API_SECRET=$(generate_random_key 64)
JWT_API_SECRET=$(ask_input "JWT_API_SECRET" "$DEFAULT_JWT_API_SECRET" "$CURRENT_JWT_API_SECRET")
echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "JWT_API_SECRET" "$JWT_API_SECRET"
echo ""

# LibreTranslate 翻译服务
log_info "配置翻译服务..."
CURRENT_TRANSLATION=$(get_config_value "$CPX_EXCHANGE_ENV" "TRANSLATION_ENABLED")
log_info "当前翻译服务状态: ${CURRENT_TRANSLATION:-未设置}"
if ask_confirm "是否开启 LibreTranslate 翻译服务"; then
    echo ""
    log_info "更新配置文件..."
    replace_config "$CPX_EXCHANGE_ENV" "TRANSLATION_ENABLED" "true"
else
    echo ""
    log_info "更新配置文件..."
    replace_config "$CPX_EXCHANGE_ENV" "TRANSLATION_ENABLED" "false"
fi
echo ""

# 阿里云邮件推送
log_info "配置阿里云邮件推送..."
echo ""
CURRENT_ALIYUN_ACCESS_KEY_ID=$(get_config_value "$CPX_EXCHANGE_ENV" "ALIYUN_ACCESS_KEY_ID")
ALIYUN_ACCESS_KEY_ID=$(ask_input "邮件推送 ALIYUN_ACCESS_KEY_ID" "" "$CURRENT_ALIYUN_ACCESS_KEY_ID" "allow_empty")

CURRENT_ALIYUN_ACCESS_KEY_SECRET=$(get_config_value "$CPX_EXCHANGE_ENV" "ALIYUN_ACCESS_KEY_SECRET")
ALIYUN_ACCESS_KEY_SECRET=$(ask_input "邮件推送 ALIYUN_ACCESS_KEY_SECRET" "" "$CURRENT_ALIYUN_ACCESS_KEY_SECRET" "allow_empty")

CURRENT_ALIYUN_MAIL_ACCOUNT=$(get_config_value "$CPX_EXCHANGE_ENV" "ALIYUN_MAIL_ACCOUNT")
ALIYUN_MAIL_ACCOUNT=$(ask_input "邮件推送-发信地址 ALIYUN_MAIL_ACCOUNT" "" "$CURRENT_ALIYUN_MAIL_ACCOUNT" "allow_empty")

CURRENT_ALIYUN_MAIL_ALIAS=$(get_config_value "$CPX_EXCHANGE_ENV" "ALIYUN_MAIL_ALIAS")
ALIYUN_MAIL_ALIAS=$(ask_input "邮件推送-发信人 ALIYUN_MAIL_ALIAS" "" "$CURRENT_ALIYUN_MAIL_ALIAS" "allow_empty")

CURRENT_ALIYUN_REGION_ID=$(get_config_value "$CPX_EXCHANGE_ENV" "ALIYUN_REGION_ID")
ALIYUN_REGION_ID=$(ask_input "邮件推送-REGION_ID ALIYUN_REGION_ID" "cn-hangzhou" "$CURRENT_ALIYUN_REGION_ID")

echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "ALIYUN_ACCESS_KEY_ID" "$ALIYUN_ACCESS_KEY_ID"
replace_config "$CPX_EXCHANGE_ENV" "ALIYUN_ACCESS_KEY_SECRET" "$ALIYUN_ACCESS_KEY_SECRET"
replace_config "$CPX_EXCHANGE_ENV" "ALIYUN_MAIL_ACCOUNT" "$ALIYUN_MAIL_ACCOUNT"
replace_config "$CPX_EXCHANGE_ENV" "ALIYUN_MAIL_ALIAS" "$ALIYUN_MAIL_ALIAS"
replace_config "$CPX_EXCHANGE_ENV" "ALIYUN_REGION_ID" "$ALIYUN_REGION_ID"
echo ""

# ES 密码
log_info "配置 Elasticsearch..."
echo ""
CURRENT_ES_PASSWORD=$(get_config_value "$CPX_EXCHANGE_ENV" "ES_PASSWORD")
DEFAULT_ES_PASSWORD=$(generate_random_key 48)
ES_PASSWORD=$(ask_input "Elasticsearch 密码（ES_PASSWORD）" "$DEFAULT_ES_PASSWORD" "$CURRENT_ES_PASSWORD")
echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "ES_PASSWORD" "$ES_PASSWORD"
replace_config "$CPX_GO_SERVER_ENV" "ES_PASSWORD" "$ES_PASSWORD"

# 转义密码中的特殊字符用于 sed
ES_PASSWORD_ESCAPED=$(echo "$ES_PASSWORD" | sed 's/[\/&|]/\\&/g')

# 更新 runner-compose.yml 中的 ELASTIC_PASSWORD（环境变量格式）
OLD_ELASTIC_PASS=$(grep "ELASTIC_PASSWORD=" "$RUNNER_COMPOSE" | cut -d'=' -f2)
if grep -q "ELASTIC_PASSWORD=" "$RUNNER_COMPOSE"; then
    sed -i "s|ELASTIC_PASSWORD=.*|ELASTIC_PASSWORD=${ES_PASSWORD_ESCAPED}|" "$RUNNER_COMPOSE"
    echo -e "${GREEN}  ✓ runner-compose.yml: ELASTIC_PASSWORD${NC}"
    echo "    旧值: ${OLD_ELASTIC_PASS}"
    echo "    新值: ${ES_PASSWORD}"
fi
# 更新 ES healthcheck 中的密码
if grep -q "curl -u elastic:" "$RUNNER_COMPOSE"; then
    sed -i "s|curl -u elastic:[^ ]*|curl -u elastic:${ES_PASSWORD_ESCAPED}|" "$RUNNER_COMPOSE"
    echo -e "${GREEN}  ✓ runner-compose.yml: ES healthcheck 密码已同步${NC}"
fi
echo ""

# 阿里云 OSS
log_info "配置阿里云 OSS..."
echo ""
CURRENT_OSS_ALIYUN_KEY=$(get_config_value "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_KEY")
OSS_ALIYUN_KEY=$(ask_input "阿里云 OSS-OSS_ALIYUN_KEY" "" "$CURRENT_OSS_ALIYUN_KEY" "allow_empty")

CURRENT_OSS_ALIYUN_SECRET=$(get_config_value "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_SECRET")
OSS_ALIYUN_SECRET=$(ask_input "阿里云 OSS-OSS_ALIYUN_SECRET" "" "$CURRENT_OSS_ALIYUN_SECRET" "allow_empty")

CURRENT_OSS_ALIYUN_BUCKET=$(get_config_value "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_BUCKET")
OSS_ALIYUN_BUCKET=$(ask_input "阿里云 OSS-OSS_ALIYUN_BUCKET" "" "$CURRENT_OSS_ALIYUN_BUCKET" "allow_empty")

CURRENT_OSS_ALIYUN_ENDPOINT=$(get_config_value "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_ENDPOINT")
OSS_ALIYUN_ENDPOINT=$(ask_input "阿里云 OSS-OSS_ALIYUN_ENDPOINT" "" "$CURRENT_OSS_ALIYUN_ENDPOINT" "allow_empty")

CURRENT_OSS_ALIYUN_DOMAIN=$(get_config_value "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_DOMAIN")
OSS_ALIYUN_DOMAIN=$(ask_input "阿里云 OSS-OSS_ALIYUN_DOMAIN" "" "$CURRENT_OSS_ALIYUN_DOMAIN" "allow_empty")

echo ""
log_info "更新配置文件..."
replace_config "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_KEY" "$OSS_ALIYUN_KEY"
replace_config "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_SECRET" "$OSS_ALIYUN_SECRET"
replace_config "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_BUCKET" "$OSS_ALIYUN_BUCKET"
replace_config "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_ENDPOINT" "$OSS_ALIYUN_ENDPOINT"
replace_config "$CPX_EXCHANGE_ENV" "OSS_ALIYUN_DOMAIN" "$OSS_ALIYUN_DOMAIN"

echo ""
log_info "所有配置已更新完成"
echo ""

# ====================================
# 6. 启动服务
# ====================================
log_info "步骤 6/6: 启动服务..."
echo ""

log_info "所有配置已完成，即将启动服务"
echo ""
echo "======================================"
echo "配置摘要："
echo "======================================"
echo "应用名称: $APP_NAME"
echo "域名: $DOMAIN"
echo "应用地址: $APP_URL"
echo "======================================"
echo ""

if ask_confirm "是否立即启动服务"; then
    log_info "正在拉取镜像（单个拉取以提高稳定性）..."
    echo ""

    # 定义需要拉取的服务列表
    SERVICES=(
        "redis_market"
        "redis_cache"
        "elasticsearch"
        "mysql"
        "cpx_runserver"
        "cpx_manager"
    )

    # 逐个拉取服务镜像
    TOTAL=${#SERVICES[@]}
    CURRENT=0

    for SERVICE in "${SERVICES[@]}"; do
        CURRENT=$((CURRENT + 1))
        log_info "[$CURRENT/$TOTAL] 正在拉取服务镜像: $SERVICE"

        # 尝试拉取镜像，失败时询问是否重试
        PULL_SUCCESS=false
        while [ "$PULL_SUCCESS" = false ]; do
            if docker compose -f runner-compose.yml pull "$SERVICE"; then
                log_info "[$CURRENT/$TOTAL] 服务镜像拉取成功: $SERVICE"
                PULL_SUCCESS=true
            else
                log_error "[$CURRENT/$TOTAL] 服务镜像拉取失败: $SERVICE"
                log_error "请检查网络连接或镜像配置是否正确"

                if ask_confirm "是否重试拉取镜像 $SERVICE"; then
                    log_info "正在重试拉取: $SERVICE"
                    continue
                else
                    log_warn "跳过服务镜像: $SERVICE"
                    log_warn "您可以稍后手动执行拉取: docker compose -f runner-compose.yml pull $SERVICE"
                    if ! ask_confirm "是否继续拉取其他服务镜像"; then
                        exit 1
                    fi
                    break
                fi
            fi
        done
        echo ""
    done

    log_info "所有镜像拉取完成，正在启动服务..."
    docker compose -f runner-compose.yml up -d
    log_info "服务启动完成"
    echo ""
    log_info "您可以使用以下命令查看服务状态:"
    log_info "  docker compose -f runner-compose.yml ps"
    log_info "  docker compose -f runner-compose.yml logs -f"
else
    log_info "跳过启动服务"
    log_info "您可以稍后手动执行:"
    log_info "  1. 拉取镜像:"
    log_info "     docker compose -f runner-compose.yml pull redis_market"
    log_info "     docker compose -f runner-compose.yml pull redis_cache"
    log_info "     docker compose -f runner-compose.yml pull elasticsearch"
    log_info "     docker compose -f runner-compose.yml pull mysql"
    log_info "     docker compose -f runner-compose.yml pull cpx_runserver"
    log_info "     docker compose -f runner-compose.yml pull cpx_manager"
    log_info "  2. 启动服务:"
    log_info "     docker compose -f runner-compose.yml up -d"
fi

echo ""
log_info "安装脚本执行完成！"
echo ""

echo ""
log_info "重置管理员密码~"
echo ""
# 请输入管理员密码
ADMIN_PASSWORD=$(ask_input "管理员密码" "123456")

docker exec cpx_runserver /bin/bash -c "php bin/hyperf.php reset:admin:pwd --password=$ADMIN_PASSWORD"

log_info "管理员密码已重置为: $ADMIN_PASSWORD"
