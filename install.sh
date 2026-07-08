#!/bin/bash
#
# Macless Haystack 一键安装脚本
# 
# 快速部署 FindMy 网络服务器，支持自动安装依赖、智能登录、备用镜像等功能。
#
# GitHub: https://github.com/tinydream96/macless-haystack-installer
# 用法: curl -sSL https://raw.githubusercontent.com/tinydream96/macless-haystack-installer/main/install.sh | sudo bash
#

# 注意：不使用 set -e，因为交互式菜单中大量命令可能返回非零值
# 错误处理通过显式检查完成

# ==================== 版本信息 ====================
VERSION="1.2.0"
OS_TYPE=$(uname)

# ==================== 临时文件清理 ====================
CLEANUP_FILES=()
cleanup() {
    for f in "${CLEANUP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null
    done
}
trap cleanup EXIT INT TERM

# ==================== 镜像配置 ====================
# 主镜像（原作者）
PRIMARY_ANISETTE_IMAGE="dadoum/anisette-v3-server"
PRIMARY_MH_IMAGE="christld/macless-haystack"

# 备用镜像（你的 Docker Hub 用户名）
BACKUP_ANISETTE_IMAGE="tinydream96/anisette-v3-server"
BACKUP_MH_IMAGE="tinydream96/macless-haystack"

# 实际使用的镜像（运行时确定）
ANISETTE_IMAGE=""
MH_IMAGE=""

# ==================== 其他配置 ====================
CREDENTIALS_FILE="$HOME/.mh-credentials"
ENDPOINT_CREDENTIALS_FILE="$HOME/.mh-endpoint-credentials"
DOCKER_NETWORK="mh-network"
ANISETTE_CONTAINER="anisette"
MH_CONTAINER="macless-haystack"
ANISETTE_VOLUME="anisette-v3_data"
MH_VOLUME="mh_data"
MH_PORT="6176"
ANISETTE_PORT="6969"

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==================== 工具函数 ====================
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║   🍎 Macless Haystack Installer v${VERSION}                  ║"
    echo "║                                                           ║"
    echo "║   FindMy Network Server Deployment Tool                   ║"
    echo "║   FindMy 网络服务器快速部署工具                           ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_menu() {
    # 显示实时服务状态
    local status_line=""
    if command -v docker &>/dev/null; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${MH_CONTAINER}$"; then
            local ip=""
            if [[ "$OS_TYPE" == "Darwin" ]]; then
                ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname)
            else
                ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi
            status_line="  ${GREEN}🟢 运行中 (Running)${NC} | 📍 http://${ip}:${MH_PORT}"
        else
            status_line="  ${RED}🔴 未运行 (Stopped)${NC}"
        fi
    else
        status_line="  ${YELLOW}⚠️  Docker 未安装 (Docker not installed)${NC}"
    fi
    echo -e "$status_line"
    echo ""
    echo -e "${BLUE}请选择操作 (Select an option)：${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} 🚀 全新安装 (Clean Install)"
    echo -e "  ${GREEN}2.${NC} 🔑 重新登录（保留数据）(Re-login / Keep Data)"
    echo -e "  ${GREEN}3.${NC} 🔄 完全重置（删除所有数据）(Full Reset / Delete All Data)"
    echo -e "  ${GREEN}4.${NC} 📊 查看服务状态 (Check Status)"
    echo -e "  ${GREEN}5.${NC} 🛑 停止所有服务 (Stop All Services)"
    echo -e "  ${GREEN}6.${NC} 🔐 修改 Web UI 密码 (Change Web UI Password)"
    echo -e "  ${GREEN}7.${NC} ♻️  重启所有服务 (Restart All Services)"
    echo -e "  ${GREEN}8.${NC} 👤 查看当前账户 (View Account Info)"
    echo -e "  ${GREEN}9.${NC} ❌ 退出 (Exit)"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# ==================== 依赖检查 ====================
check_root() {
    if [[ "$OS_TYPE" == "Linux" && "$EUID" -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本 (Please run as root)"
        log_info "运行 (Run): sudo bash $0"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            log_error "未检测到 Docker，请先安装 Docker Desktop 或 OrbStack (Docker not found, please install Docker Desktop or OrbStack)"
            log_info "下载地址 (Download): https://www.docker.com/products/docker-desktop/"
            exit 1
        else
            log_warn "Docker 未安装，正在安装... (Docker not found, installing...)"
            install_docker
        fi
    else
        log_info "Docker 已安装 (Docker installed): $(docker --version)"
    fi
}

install_docker() {
    log_step "安装 Docker..."
    
    # 检测发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION_CODENAME=${VERSION_CODENAME:-$UBUNTU_CODENAME}
    else
        log_error "无法检测操作系统版本"
        exit 1
    fi
    
    # 目前仅支持 Ubuntu/Debian
    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        log_warn "非 Ubuntu/Debian 系统，尝试使用官方脚本安装..."
        curl -fsSL https://get.docker.com | sh
    else
        log_info "检测到 ${DISTRO} ${VERSION_CODENAME}，使用手动安装方式... (Detected ${DISTRO} ${VERSION_CODENAME}, installing manually...)"
        
        # 安装依赖
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg
        
        # 添加 Docker GPG 密钥
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        
        # 添加 Docker 仓库
        ARCH=$(dpkg --print-architecture)
        echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
        
        # 更新并安装 Docker（仅安装必要组件，避免 docker-model-plugin 问题）
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
        
        log_info "Docker 手动安装完成 (Docker installation completed)"
    fi
    
    systemctl enable docker
    systemctl start docker
    log_info "Docker 安装完成"
}

check_expect() {
    if ! command -v expect &> /dev/null; then
        log_warn "expect 未安装，正在安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y -qq expect
        elif command -v yum &> /dev/null; then
            yum install -y -q expect
        elif command -v apk &> /dev/null; then
            apk add --quiet expect
        else
            log_error "无法自动安装 expect，请手动安装 (Cannot install expect automatically, please install manually)"
            exit 1
        fi
        log_info "expect 安装完成 (expect installed)"
    fi
}

# ==================== 镜像管理 ====================
try_pull_image() {
    local primary="$1"
    local backup="$2"
    local result_var="$3"
    
    log_step "拉取镜像 (Pulling Image): $primary"
    if docker pull "$primary" 2>/dev/null; then
        log_info "成功拉取主镜像 (Primary image pulled): $primary"
        eval "$result_var='$primary'"
        return 0
    else
        log_warn "主镜像拉取失败，尝试备用镜像 (Primary failed, trying backup): $backup"
        if docker pull "$backup" 2>/dev/null; then
            log_info "成功拉取备用镜像 (Backup image pulled): $backup"
            eval "$result_var='$backup'"
            return 0
        else
            log_error "所有镜像源都无法访问！(All image sources are unreachable!)"
            return 1
        fi
    fi
}

pull_images() {
    log_step "检查并拉取 Docker 镜像 (Checking and pulling Docker images)..."
    
    # 拉取 Anisette 镜像
    if ! try_pull_image "$PRIMARY_ANISETTE_IMAGE" "$BACKUP_ANISETTE_IMAGE" "ANISETTE_IMAGE"; then
        log_error "无法拉取 Anisette 镜像，请检查网络连接"
        exit 1
    fi
    
    # 拉取 Macless Haystack 镜像
    if ! try_pull_image "$PRIMARY_MH_IMAGE" "$BACKUP_MH_IMAGE" "MH_IMAGE"; then
        log_error "无法拉取 Macless Haystack 镜像，请检查网络连接"
        exit 1
    fi
    
    log_info "所有镜像已就绪"
}

# ==================== 凭据管理 ====================
get_credentials() {
    if [ -f "$CREDENTIALS_FILE" ]; then
        log_info "发现已保存的凭据 (Found saved credentials)"
        read -p "是否使用已保存的凭据？[Y/n] (Use saved credentials? [Y/n]) " use_saved
        if [[ "$use_saved" =~ ^[Nn]$ ]]; then
            input_credentials
        fi
    else
        input_credentials
    fi
}

input_credentials() {
    echo ""
    log_step "请输入 Apple ID 凭据 (Enter Apple ID Credentials)"
    echo -e "${YELLOW}⚠️  建议使用专用小号，避免主账号风险 (Use a burner account recommended)${NC}"
    echo ""
    
    read -p "Apple ID (手机号/邮箱/Email/Phone): " apple_id
    read -s -p "密码 (Password): " password
    echo ""
    
    # 保存凭据
    echo "$apple_id" > "$CREDENTIALS_FILE"
    echo "$password" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    
    log_info "凭据已安全保存到 (Credentials saved to) $CREDENTIALS_FILE"
}

read_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "凭据文件不存在，请先运行全新安装 (Credentials not found, please run Clean Install first)"
        exit 1
    fi
    APPLE_ID=$(sed -n '1p' "$CREDENTIALS_FILE")
    PASSWORD=$(sed -n '2p' "$CREDENTIALS_FILE")
}

# ==================== Web UI 凭据管理 ====================
get_endpoint_credentials() {
    echo ""
    log_step "设置 Web UI 登录保护 (Setup Web UI Protection)"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  设置后访问 http://IP:6176 需要输入账号密码               ${NC}"
    echo -e "${YELLOW}  Protection prevents unauthorized access to FindMy service${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "是否设置 Web UI 登录保护？[Y/n] (Enable Web UI Protection? [Y/n]) " set_auth
    if [[ "$set_auth" =~ ^[Nn]$ ]]; then
        log_warn "跳过 Web UI 登录保护设置 (Skipping Web UI protection setup)"
        rm -f "$ENDPOINT_CREDENTIALS_FILE"
        return
    fi
    
    read -p "Web UI 用户名 (Username): " endpoint_user
    while [ -z "$endpoint_user" ]; do
        log_error "用户名不能为空 (Username cannot be empty)"
        read -p "Web UI 用户名 (Username): " endpoint_user
    done
    
    read -s -p "Web UI 密码 (Password): " endpoint_pass
    echo ""
    while [ -z "$endpoint_pass" ]; do
        log_error "密码不能为空 (Password cannot be empty)"
        read -s -p "Web UI 密码 (Password): " endpoint_pass
        echo ""
    done
    
    # 保存凭据
    echo "$endpoint_user" > "$ENDPOINT_CREDENTIALS_FILE"
    echo "$endpoint_pass" >> "$ENDPOINT_CREDENTIALS_FILE"
    chmod 600 "$ENDPOINT_CREDENTIALS_FILE"
    
    log_info "Web UI 凭据已保存 (Web UI credentials saved)"
}

configure_endpoint_auth() {
    # 读取凭据
    if [ ! -f "$ENDPOINT_CREDENTIALS_FILE" ]; then
        return
    fi
    
    local endpoint_user=$(sed -n '1p' "$ENDPOINT_CREDENTIALS_FILE")
    local endpoint_pass=$(sed -n '2p' "$ENDPOINT_CREDENTIALS_FILE")
    
    # 如果没有设置凭据，跳过
    if [ -z "$endpoint_user" ] || [ -z "$endpoint_pass" ]; then
        return
    fi
    
    log_step "配置 Web UI 登录保护..."
    
    # 等待容器完全启动并生成配置文件
    sleep 5
    
    # 检查文件是否存在，最多等待 30 秒
    # 优先使用 docker exec（容器已在运行），避免反复启动临时容器
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if docker exec "$MH_CONTAINER" test -f /app/endpoint/data/config.ini &>/dev/null; then
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    if [[ $wait_count -eq 30 ]]; then
        log_warn "配置文件尚未创建，请手动配置 Web UI 登录 (Config file not found, please configure manually)"
        return
    fi

    # 使用临时容器更新配置（跨平台通用）
    log_step "更新 Web UI 凭据配置 (Updating Web UI credentials)..."
    docker run --rm -v "${MH_VOLUME}:/data" alpine sh -c "
        if grep -q '^endpoint_user' /data/config.ini; then
            sed -i 's|^endpoint_user.*|endpoint_user = $endpoint_user|' /data/config.ini
        else
            echo 'endpoint_user = $endpoint_user' >> /data/config.ini
        fi
        if grep -q '^endpoint_pass' /data/config.ini; then
            sed -i 's|^endpoint_pass.*|endpoint_pass = $endpoint_pass|' /data/config.ini
        else
            echo 'endpoint_pass = $endpoint_pass' >> /data/config.ini
        fi
    "
    
    # 重启容器使配置生效
    log_step "重启服务使配置生效 (Restarting service to apply config)..."
    docker restart "$MH_CONTAINER" >/dev/null 2>&1
    sleep 3
    
    log_info "✅ Web UI 登录保护已配置 (Web UI Protection Configured)"
    echo -e "  用户名 (Username): ${GREEN}$endpoint_user${NC}"
}

# ==================== 容器管理 ====================
setup_network() {
    if ! docker network ls | grep -q "$DOCKER_NETWORK"; then
        log_step "创建 Docker 网络 (Creating Docker network): $DOCKER_NETWORK"
        docker network create "$DOCKER_NETWORK"
    else
        log_info "Docker 网络已存在 (Docker network exists): $DOCKER_NETWORK"
    fi
}

start_anisette() {
    # 确定使用哪个镜像
    if [ -z "$ANISETTE_IMAGE" ]; then
        # 检查本地是否有镜像
        if docker images --format '{{.Repository}}' | grep -q "^${PRIMARY_ANISETTE_IMAGE}$"; then
            ANISETTE_IMAGE="$PRIMARY_ANISETTE_IMAGE"
        elif docker images --format '{{.Repository}}' | grep -q "^${BACKUP_ANISETTE_IMAGE}$"; then
            ANISETTE_IMAGE="$BACKUP_ANISETTE_IMAGE"
        else
            # 需要拉取镜像
            try_pull_image "$PRIMARY_ANISETTE_IMAGE" "$BACKUP_ANISETTE_IMAGE" "ANISETTE_IMAGE"
        fi
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^${ANISETTE_CONTAINER}$"; then
        log_info "Anisette 容器已存在，正在重新创建以应用配置 (Recreating Anisette container)..."
        docker stop "$ANISETTE_CONTAINER" >/dev/null 2>&1 || true
        docker rm "$ANISETTE_CONTAINER" >/dev/null 2>&1 || true
    fi

    log_step "启动 Anisette 服务 (Starting Anisette service)..."
    docker run -d \
        --restart unless-stopped \
        --name "$ANISETTE_CONTAINER" \
        -p "${ANISETTE_PORT}:${ANISETTE_PORT}" \
        --volume "${ANISETTE_VOLUME}:/home/Alcoholic/.config/anisette-v3" \
        --network "$DOCKER_NETWORK" \
        "$ANISETTE_IMAGE" \
        --host 0.0.0.0
    
    # 等待 Anisette 启动并确保可连接
    log_info "等待 Anisette 服务就绪 (通常需要 20-40 秒) (Waiting for Anisette service, 20-40s)..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if docker run --rm --network "$DOCKER_NETWORK" alpine sh -c "nc -z ${ANISETTE_CONTAINER} ${ANISETTE_PORT}" &>/dev/null; then
            log_info "✅ Anisette 服务已就绪 (Anisette service ready)"
            return
        fi
        echo -n "."
        sleep 2
        wait_count=$((wait_count + 1))
    done
    echo ""
    log_error "Anisette 服务启动超时，请检查日志 (Anisette timed out, check logs): docker logs anisette"
    exit 1
}

stop_containers() {
    log_step "停止容器 (Stopping containers)..."
    docker stop "$MH_CONTAINER" 2>/dev/null || true
    docker stop "$ANISETTE_CONTAINER" 2>/dev/null || true
}

remove_containers() {
    log_step "删除容器 (Removing containers)..."
    docker rm "$MH_CONTAINER" 2>/dev/null || true
    docker rm "$ANISETTE_CONTAINER" 2>/dev/null || true
}

remove_volumes() {
    log_step "删除数据卷 (Removing volumes)..."
    docker volume rm "$MH_VOLUME" 2>/dev/null || true
    docker volume rm "$ANISETTE_VOLUME" 2>/dev/null || true
}

restart_services() {
    log_step "重启所有服务 (Restarting all services)..."
    docker restart "$ANISETTE_CONTAINER" 2>/dev/null || true
    docker restart "$MH_CONTAINER" 2>/dev/null || true
    log_info "服务重启指令已发送 (Restart command sent)"
    show_status
}

modify_endpoint_credentials() {
    log_step "修改 Web UI 密码 (Change Web UI Password)"
    
    # 获取新凭据
    read -p "新用户名为 (New Username): " endpoint_user
    while [ -z "$endpoint_user" ]; do
        log_error "用户名不能为空 (Username cannot be empty)"
        read -p "新用户名为 (New Username): " endpoint_user
    done
    
    read -s -p "新密码为 (New Password): " endpoint_pass
    echo ""
    while [ -z "$endpoint_pass" ]; do
        log_error "密码不能为空 (Password cannot be empty)"
        read -s -p "新密码为 (New Password): " endpoint_pass
        echo ""
    done

    # 更新本地凭据文件
    echo "$endpoint_user" > "$ENDPOINT_CREDENTIALS_FILE"
    echo "$endpoint_pass" >> "$ENDPOINT_CREDENTIALS_FILE"
    chmod 600 "$ENDPOINT_CREDENTIALS_FILE"
    log_info "本地凭据文件已更新 (Local credentials updated)"

    # 检查容器/卷是否存在
    if ! docker volume ls | grep -q "$MH_VOLUME"; then
        log_error "数据卷不存在，请先安装服务 (Volume not found, please install first)"
        return
    fi
    
    # 检查 auth.json 确保服务已初始化
    if ! docker run --rm -v "${MH_VOLUME}:/data" alpine ls /data/config.ini &>/dev/null; then
         log_error "配置文件不存在，服务可能未初始化 (Config file not found, service might not be initialized)"
         return
    fi

    log_step "正在更新配置文件... (Updating config file...)"
    # 使用临时容器更新 config.ini
    docker run --rm -v "${MH_VOLUME}:/data" alpine sh -c "
        # 如果不存在则追加，存在则替换
        if grep -q '^endpoint_user' /data/config.ini; then
            sed -i 's|^endpoint_user.*|endpoint_user = $endpoint_user|' /data/config.ini
        else
            echo 'endpoint_user = $endpoint_user' >> /data/config.ini
        fi
        
        if grep -q '^endpoint_pass' /data/config.ini; then
            sed -i 's|^endpoint_pass.*|endpoint_pass = $endpoint_pass|' /data/config.ini
        else
            echo 'endpoint_pass = $endpoint_pass' >> /data/config.ini
        fi
    "
    
    log_info "配置已更新，正在重启服务... (Config updated, restarting service...)"
    docker restart "$MH_CONTAINER" >/dev/null 2>&1
    
    sleep 2
    log_info "✅Web UI 密码修改成功并已重启生效！(Web UI password changed and service restarted!)"
    echo -e "  新用户 (New User): ${GREEN}$endpoint_user${NC}"
}

# ==================== 交互式登录 ====================
interactive_login() {
    read_credentials
    
    # 确定使用哪个镜像
    if [ -z "$MH_IMAGE" ]; then
        if docker images --format '{{.Repository}}' | grep -q "^${PRIMARY_MH_IMAGE}$"; then
            MH_IMAGE="$PRIMARY_MH_IMAGE"
        elif docker images --format '{{.Repository}}' | grep -q "^${BACKUP_MH_IMAGE}$"; then
            MH_IMAGE="$BACKUP_MH_IMAGE"
        else
            try_pull_image "$PRIMARY_MH_IMAGE" "$BACKUP_MH_IMAGE" "MH_IMAGE"
        fi
    fi
    
    # 确保旧容器已删除
    docker stop "$MH_CONTAINER" 2>/dev/null || true
    docker rm "$MH_CONTAINER" 2>/dev/null || true

    # 如果是重新登录，询问是否清理旧 session
    local HAS_AUTH=0
    if docker run --rm -v "${MH_VOLUME}:/data" alpine ls /data/auth.json &>/dev/null; then
        HAS_AUTH=1
    fi

    if [ $HAS_AUTH -eq 1 ]; then
        echo ""
        log_warn "检测到已存在的登录会话 (auth.json) (Found existing session)"
        read -p "是否清除旧会话并重新进行 2FA 认证？[y/N] (Clear old session and re-authenticate? [y/N]) " clear_auth
        if [[ "$clear_auth" =~ ^[Yy]$ ]]; then
            docker run --rm -v "${MH_VOLUME}:/data" alpine rm -f /data/auth.json
            log_info "已清理旧会话 (Old session cleared)"
        fi
    fi
    
    log_step "启动交互式登录 (Starting interactive login)..."
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  📱 账号密码将自动填入，请等待输入验证码提示              ${NC}"
    echo -e "${YELLOW}  📲 验证码会发送到你的 Apple 设备                         ${NC}"
    echo -e "${YELLOW}  ⌨️  输入验证码后请按回车键确认                            ${NC}"
    echo -e "${YELLOW}  -------------------------------------------------------  ${NC}"
    echo -e "${YELLOW}  📱 Credentials will be auto-filled, wait for 2FA prompt  ${NC}"
    echo -e "${YELLOW}  📲 Code will be sent to your Apple device                ${NC}"
    echo -e "${YELLOW}  ⌨️  Press Enter after typing the code                     ${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}  💡 当看到以下信息时，请按 Ctrl+C 继续后续配置 (Press Ctrl+C when you see)：${NC}"
    echo -e "${CYAN}     \"INFO - serving at :6176 over HTTP\"                  ${NC}"
    echo ""
    
    # 创建临时文件用于记录日志
    local LOGIN_LOG=$(mktemp)
    local EXPECT_SCRIPT=$(mktemp)
    # 注册到全局清理列表，确保异常退出时也能清理
    CLEANUP_FILES+=("$LOGIN_LOG" "$EXPECT_SCRIPT")
    
    # 写入 expect 脚本（避免 heredoc 转义问题）
    # 安全改进：敏感信息通过环境变量传递，不会出现在 ps 进程列表中
    cat > "$EXPECT_SCRIPT" << 'EXPECT_EOF'
#!/usr/bin/expect -f
set timeout 300
# 从环境变量读取敏感信息，避免通过命令行参数暴露
set apple_id $env(MH_APPLE_ID)
set password $env(MH_PASSWORD)
set container_name [lindex $argv 0]
set port [lindex $argv 1]
set volume [lindex $argv 2]
set network [lindex $argv 3]
set image [lindex $argv 4]
set logfile [lindex $argv 5]

log_file -noappend $logfile

spawn docker run -it --name $container_name -p ${port}:${port} --volume ${volume}:/app/endpoint/data --network $network $image

expect {
    "Apple ID:" {
        send "$apple_id\r"
        exp_continue
    }
    "Password:" {
        send "$password\r"
        exp_continue
    }
    -re "code.*:" {
        # 进入交互模式让用户输入验证码
        expect_user -re "(.*)\n"
        send "$expect_out(1,string)\r"
        # 等待登录完成或出错
        expect {
            "Logged in" {
                # 登录成功，继续等待服务就绪
                exp_continue
            }
            "serving at :6176 over HTTP" {
                # 服务已正常启动，可以安全退出交互模式
                exit 0
            }
            "Error" {
                # 出错
                exit 1
            }
            timeout {
                # 超时，可能已经完成
                exit 0
            }
            eof {
                # 容器退出
                exit 1
            }
        }
    }
    "serving at :6176 over HTTP" {
        # 如果直接跳过登录流程看到此消息
        exit 0
    }
    "Traceback" {
        # Python 错误
    }
    "KeyError" {
        # 认证错误
    }
    eof {
        # 容器退出
    }
}
EXPECT_EOF
    
    chmod +x "$EXPECT_SCRIPT"
    
    # 执行 expect 脚本（敏感信息通过环境变量传递，不暴露在 ps 中）
    MH_APPLE_ID="$APPLE_ID" MH_PASSWORD="$PASSWORD" \
        "$EXPECT_SCRIPT" "$MH_CONTAINER" "$MH_PORT" "$MH_VOLUME" "$DOCKER_NETWORK" "$MH_IMAGE" "$LOGIN_LOG" || true
    
    # 清理 expect 脚本
    rm -f "$EXPECT_SCRIPT"
    
    echo ""
    
    # 等待一下让容器日志产生
    sleep 2
    
    # 检查容器日志中是否有错误
    local CONTAINER_LOGS=""
    CONTAINER_LOGS=$(docker logs "$MH_CONTAINER" 2>&1 || cat "$LOGIN_LOG" 2>/dev/null || echo "")
    
    # 检查登录是否有错误
    local LOGIN_ERROR=0
    
    # 检查常见的登录错误模式
    if echo "$CONTAINER_LOGS" | grep -q "KeyError"; then
        LOGIN_ERROR=1
        log_error "检测到认证错误 (KeyError)，可能是账号或密码错误 (Auth Error: Check credentials)"
    elif echo "$CONTAINER_LOGS" | grep -q "Authentication failed"; then
        LOGIN_ERROR=1
        log_error "认证失败 (Authentication failed)"
    elif echo "$CONTAINER_LOGS" | grep -q "Invalid credentials"; then
        LOGIN_ERROR=1
        log_error "凭据无效 (Invalid credentials)"
    elif echo "$CONTAINER_LOGS" | grep -q "Traceback" && ! echo "$CONTAINER_LOGS" | grep -q "Logged in"; then
        LOGIN_ERROR=1
        log_error "检测到程序异常 (Program Exception detected)"
    fi
    
    # 清理临时日志
    rm -f "$LOGIN_LOG"
    
    # 如果有错误，清理凭据并提示重试
    if [ "$LOGIN_ERROR" -eq 1 ]; then
        echo ""
        log_error "登录失败！正在清理... (Login failed! Cleaning up...)"
        
        # 停止并删除容器
        docker stop "$MH_CONTAINER" 2>/dev/null || true
        docker rm "$MH_CONTAINER" 2>/dev/null || true
        
        # 删除凭据文件
        rm -f "$CREDENTIALS_FILE"
        log_warn "已删除保存的凭据文件 (Credentials file deleted)"
        
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  登录失败，请检查以下几点 (Login Failed, check these)：   ${NC}"
        echo -e "${YELLOW}  1. 确认账号密码正确（可先在 appleid.apple.com 测试）   ${NC}"
        echo -e "${YELLOW}     (Verify credentials on appleid.apple.com)           ${NC}"
        echo -e "${YELLOW}  2. 如果是手机号，请确认格式正确（如 +86xxxxxxxxxx）   ${NC}"
        echo -e "${YELLOW}     (Check phone format e.g. +86...)                    ${NC}"
        echo -e "${YELLOW}  3. 密码中避免使用特殊字符（如 \$、\\、\"）             ${NC}"
        echo -e "${YELLOW}     (Avoid special chars like \$ \\ \" in password)       ${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        log_info "请重新运行安装脚本，选择「全新安装」重新输入凭据"
        log_info "(Please re-run script and choose 'Clean Install')"
        return 1
    fi
    
    # 检查容器是否还在运行
    if ! docker ps --format '{{.Names}}' | grep -q "^${MH_CONTAINER}$"; then
        log_step "重启容器为后台模式 (Restarting container in background)..."
        docker start "$MH_CONTAINER" 2>/dev/null || docker restart "$MH_CONTAINER" 2>/dev/null || true
    fi
    
    # 设置自动重启策略
    docker update --restart unless-stopped "$MH_CONTAINER" 2>/dev/null || true
    
    log_info "登录流程完成 (Login process completed)"
    
    # 配置 Web UI 登录保护
    configure_endpoint_auth
    
    # 获取 IP 地址
    local SERVER_IP=""
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        SERVER_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || hostname)
    else
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi

    echo ""
    log_info "✅ 部署完成！(Deployment Completed!)"
    echo ""
    echo -e "  访问地址 (URL): ${GREEN}http://${SERVER_IP}:${MH_PORT}${NC}"
    if [ -f "$ENDPOINT_CREDENTIALS_FILE" ]; then
        local ep_user=$(sed -n '1p' "$ENDPOINT_CREDENTIALS_FILE")
        if [ -n "$ep_user" ]; then
            echo -e "  登录用户 (User): ${GREEN}$ep_user${NC}"
        fi
    fi
    echo ""
}

# ==================== 状态检查 ====================
show_status() {
    echo ""
    log_step "服务状态 (Service Status)"
    echo ""
    
    echo -e "${BLUE}容器状态 (Containers):${NC}"
    docker ps -a --filter "name=$ANISETTE_CONTAINER" --filter "name=$MH_CONTAINER" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  无运行中的容器 (No running containers)"
    
    echo ""
    echo -e "${BLUE}数据卷 (Volumes):${NC}"
    docker volume ls --filter "name=$MH_VOLUME" --filter "name=$ANISETTE_VOLUME" 2>/dev/null || echo "  无数据卷 (No volumes)"
    
    echo ""
    echo -e "${BLUE}使用的镜像 (Images used):${NC}"
    echo "  Anisette: ${ANISETTE_IMAGE:-未确定 (Unknown)}"
    echo "  Macless Haystack: ${MH_IMAGE:-未确定 (Unknown)}"
    
    echo ""
    
    # 检查服务是否可访问
    if docker ps --format '{{.Names}}' | grep -q "^${MH_CONTAINER}$"; then
        local ip=$(hostname -I | awk '{print $1}')
        [[ "$OS_TYPE" == "Darwin" ]] && ip=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || hostname)
        echo -e "${GREEN}✅ 服务运行中 (Service Running)${NC}"
        echo -e "  访问地址 (URL): http://${ip}:${MH_PORT}"
    else
        echo -e "${YELLOW}⚠️  Macless Haystack 服务未运行 (Service not running)${NC}"
    fi
    echo ""
}

# ==================== 账户信息 ====================
show_account_info() {
    echo ""
    log_step "当前账户信息 (Account Info)"
    echo ""
    
    # Apple ID 凭据
    echo -e "${BLUE}━━━ Apple ID ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ -r "$CREDENTIALS_FILE" ]; then
        local saved_id=$(sed -n '1p' "$CREDENTIALS_FILE")
        local saved_pass=$(sed -n '2p' "$CREDENTIALS_FILE")
        if [ -n "$saved_id" ]; then
            echo -e "  账号 (Apple ID): ${GREEN}${saved_id}${NC}"
            # 密码脱敏：只显示前2位和后1位，中间用 * 替代
            if [ -n "$saved_pass" ]; then
                local pass_len=${#saved_pass}
                if [ $pass_len -le 4 ]; then
                    local masked=$(printf '%*s' "$pass_len" | tr ' ' '*')
                else
                    local masked="${saved_pass:0:2}$(printf '%*s' $((pass_len - 3)) | tr ' ' '*')${saved_pass: -1}"
                fi
                echo -e "  密码 (Password): ${YELLOW}${masked}${NC}"
            else
                echo -e "  密码 (Password): ${RED}未设置 (Not set)${NC}"
            fi
        else
            echo -e "  ${YELLOW}凭据文件为空 (Credentials file is empty)${NC}"
        fi
        echo -e "  文件 (File): ${CYAN}${CREDENTIALS_FILE}${NC}"
    elif [ -f "$CREDENTIALS_FILE" ]; then
        echo -e "  ${YELLOW}🔒 凭据文件存在但无读取权限 (Permission denied)${NC}"
        echo -e "  ${YELLOW}   请使用 sudo 运行此脚本 (Please run with sudo)${NC}"
        echo -e "  文件 (File): ${CYAN}${CREDENTIALS_FILE}${NC}"
    else
        echo -e "  ${YELLOW}未配置 (Not configured) — 请先运行全新安装${NC}"
    fi
    
    echo ""
    
    # Web UI 凭据
    echo -e "${BLUE}━━━ Web UI 登录保护 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ -r "$ENDPOINT_CREDENTIALS_FILE" ]; then
        local ep_user=$(sed -n '1p' "$ENDPOINT_CREDENTIALS_FILE")
        local ep_pass=$(sed -n '2p' "$ENDPOINT_CREDENTIALS_FILE")
        if [ -n "$ep_user" ]; then
            echo -e "  用户名 (Username): ${GREEN}${ep_user}${NC}"
            if [ -n "$ep_pass" ]; then
                local ep_len=${#ep_pass}
                if [ $ep_len -le 4 ]; then
                    local ep_masked=$(printf '%*s' "$ep_len" | tr ' ' '*')
                else
                    local ep_masked="${ep_pass:0:2}$(printf '%*s' $((ep_len - 3)) | tr ' ' '*')${ep_pass: -1}"
                fi
                echo -e "  密码 (Password): ${YELLOW}${ep_masked}${NC}"
            else
                echo -e "  密码 (Password): ${RED}未设置 (Not set)${NC}"
            fi
        else
            echo -e "  ${YELLOW}未启用 Web UI 保护 (Web UI protection not enabled)${NC}"
        fi
        echo -e "  文件 (File): ${CYAN}${ENDPOINT_CREDENTIALS_FILE}${NC}"
    elif [ -f "$ENDPOINT_CREDENTIALS_FILE" ]; then
        echo -e "  ${YELLOW}🔒 凭据文件存在但无读取权限 (Permission denied)${NC}"
        echo -e "  ${YELLOW}   请使用 sudo 运行此脚本 (Please run with sudo)${NC}"
        echo -e "  文件 (File): ${CYAN}${ENDPOINT_CREDENTIALS_FILE}${NC}"
    else
        echo -e "  ${YELLOW}未启用 (Not enabled) — 可在安装时设置或选择菜单 6 配置${NC}"
    fi
    
    echo ""
}

# ==================== 主菜单 ====================
main() {
    check_root
    print_banner
    
    while true; do
        print_menu
        read -p "请输入选项 [1-9] (Select option): " choice
        echo ""
        
        case $choice in
            1)
                # 全新安装
                # 安全检查：如果已有安装数据，警告用户
                if command -v docker &>/dev/null && docker volume ls -q 2>/dev/null | grep -q "^${MH_VOLUME}$"; then
                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${RED}  ⚠️  检测到已有安装数据！                                   ${NC}"
                    echo -e "${RED}  全新安装将删除所有现有数据（认证、配置等）！               ${NC}"
                    echo -e "${RED}  WARNING: Clean install will DELETE all existing data!      ${NC}"
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo ""
                    read -p "确定要继续吗？输入 y 确认 (Continue? Type y to confirm) [y/N]: " confirm_clean
                    if [[ ! "$confirm_clean" =~ ^[Yy]$ ]]; then
                        log_info "已取消全新安装 (Clean install cancelled)"
                        continue
                    fi
                fi
                log_step "开始全新安装 (Starting Clean Install)..."
                check_docker
                check_expect
                stop_containers
                remove_containers
                remove_volumes
                setup_network
                pull_images
                get_credentials
                get_endpoint_credentials
                start_anisette
                interactive_login
                ;;
            2)
                # 重新登录
                log_step "重新登录 (Re-login)..."
                check_expect
                get_credentials
                start_anisette
                interactive_login
                ;;
            3)
                # 完全重置
                echo -e "${RED}⚠️  警告：这将删除所有数据，包括认证信息和配置！(Warning: This will delete ALL data)${NC}"
                read -p "确定要继续吗？[y/N] (Continue? [y/N]) " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    stop_containers
                    remove_containers
                    remove_volumes
                    rm -f "$CREDENTIALS_FILE"
                    rm -f "$ENDPOINT_CREDENTIALS_FILE"
                    log_info "已完全重置，请重新运行脚本进行安装 (Reset complete)"
                fi
                ;;
            4)
                # 查看状态
                show_status
                ;;
            5)
                # 停止服务
                stop_containers
                log_info "所有服务已停止 (All services stopped)"
                ;;
            6)
                # 修改 Web UI 密码
                modify_endpoint_credentials
                ;;
            7)
                # 重启服务
                restart_services
                ;;
            8)
                # 查看当前账户
                show_account_info
                ;;
            9)
                # 退出
                log_info "再见！(Goodbye!)"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新选择 (Invalid option)"
                ;;
        esac
        
        echo ""
        read -p "按 Enter 继续... (Press Enter to continue)"
        clear
        print_banner
    done
}

# ==================== 入口 ====================
main "$@"
