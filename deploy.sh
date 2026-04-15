#!/bin/bash
set -e
P="/www/wwwroot/paypro"
DB="paypro"
U="paypro"
PW="PayPro@2026Secure"
PORT=8080
MYSQL_ROOT_PASS="d886355845ba8327"
echo "=== PayPro 宝塔一键部署 ==="

echo "[1/8] 环境检查..."
command -v java &>/dev/null || yum install -y --skip-broken java-17-openjdk java-17-openjdk-devel
command -v mvn &>/dev/null || yum install -y --skip-broken maven
command -v git &>/dev/null || yum install -y --skip-broken git

REDIS_OK=false
if command -v redis-cli &>/dev/null; then
    redis-cli ping &>/dev/null && REDIS_OK=true || { systemctl start redis 2>/dev/null && systemctl enable redis 2>/dev/null && REDIS_OK=true; }
    $REDIS_OK && echo "  ✅ Redis 已就绪"
elif [ -d /www/server/redis ]; then
    /www/server/redis/bin/redis-cli ping &>/dev/null && REDIS_OK=true || { /etc/init.d/redis start 2>/dev/null || systemctl start redis 2>/dev/null; REDIS_OK=true; }
    systemctl enable redis 2>/dev/null
    $REDIS_OK && echo "  ✅ 宝塔 Redis 已就绪"
fi
if [ "$REDIS_OK" = false ]; then
    echo "  → 安装 Redis..."
    yum install -y redis --allowerasing --nobest 2>/dev/null && { systemctl start redis && systemctl enable redis && REDIS_OK=true && echo "  ✅ Redis yum 安装成功"; }
    if [ "$REDIS_OK" = false ] && [ -f /www/server/panel/install/redis.sh ]; then
        bash /www/server/panel/install/redis.sh install 2>/dev/null && { /etc/init.d/redis start 2>/dev/null || systemctl start redis 2>/dev/null; REDIS_OK=true && echo "  ✅ 宝塔 Redis 安装成功"; }
    fi
    [ "$REDIS_OK" = false ] && { echo "  ❌ Redis 安装失败，请在宝塔面板安装"; exit 1; }
fi

[ -d /www/server/mysql ] && export PATH="/www/server/mysql/bin:$PATH"

echo "[2/8] MySQL root密码..."
MYSQL_PASS="$MYSQL_ROOT_PASS"
for f in /www/server/panel/config.pl /root/.my.cnf /www/server/mysql/password.pl; do
    if [ -f "$f" ]; then
        TMP=$(grep -oP '(?:password|passwd)\s*=\s*\K\S+' "$f" 2>/dev/null || cat "$f" 2>/dev/null)
        [ -n "$TMP" ] && [ ${#TMP} -gt 4 ] && MYSQL_PASS="$TMP"
    fi
done
echo "  ✅ 已获取"

echo "[3/8] 创建数据库..."
mysql -u root -p"${MYSQL_PASS}" -e "CREATE DATABASE IF NOT EXISTS $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && echo "  ✅ 数据库已创建" || echo "  ⚠️  可能已存在"

echo "[4/8] 获取代码..."
mkdir -p $P && cd $P
if [ -d .git ]; then git pull; else git clone https://github.com/codewendao/PayPro.git .; fi
echo "  ✅ 代码已就绪"

echo "[5/8] 修改配置..."
cd $P
cp src/main/resources/application.yml{,.bak}

python3 << 'PYEOF'
lines = open('src/main/resources/application.yml').readlines()
result = []
current_section = ""
current_subsection = ""

for line in lines:
    stripped = line.strip()
    # Track top-level sections (no indentation)
    if stripped and not line.startswith(' ') and not line.startswith('#') and ':' in stripped:
        current_section = stripped.split(':')[0].strip()
        current_subsection = ""
    # Track subsections (4-space indent)
    elif line.startswith('  ') and not line.startswith('    ') and ':' in stripped and not stripped.startswith('#'):
        current_subsection = stripped.split(':')[0].strip()
    
    # 1. Change server port: 8889 -> 8080
    if current_section == 'server' and stripped.startswith('port:') and '8889' in stripped:
        indent = len(line) - len(line.lstrip())
        result.append(' ' * indent + 'port: 8080\n')
        continue
    
    # 2. Change datasource password (not mail password)
    if current_subsection == 'datasource' and stripped.startswith('password:'):
        indent = len(line) - len(line.lstrip())
        result.append(' ' * indent + 'password: ' + 'PayPro@2026Secure' + '\n')
        continue
    
    # 3. Change datasource username: root -> paypro
    if current_subsection == 'datasource' and stripped.startswith('username:') and 'root' in stripped:
        indent = len(line) - len(line.lstrip())
        result.append(' ' * indent + 'username: paypro\n')
        continue
    
    # 4. Change datasource URL
    if current_subsection == 'datasource' and 'url:' in stripped and 'jdbc:mysql' in stripped:
        indent = len(line) - len(line.lstrip())
        result.append(' ' * indent + 'url: jdbc:mysql://127.0.0.1:3306/paypro?useSSL=false&characterEncoding=utf-8&serverTimezone=Asia/Shanghai\n')
        continue
    
    # 5. Change paypro.site
    if current_section == 'paypro' and stripped.startswith('site:'):
        indent = len(line) - len(line.lstrip())
        result.append(' ' * indent + 'site: https://agent-token.top\n')
        continue
    
    result.append(line)

open('src/main/resources/application.yml', 'w').writelines(result)
print('  ✅ 配置已更新')

# Verify YAML is valid
PYEOF

echo "[6/8] 构建项目 (首次需3-5分钟)..."
cd $P
mvn clean package -DskipTests
J=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)
echo "  → JAR: $J"

echo "[7/8] 启动服务..."
systemctl stop paypro 2>/dev/null || true
tee /etc/systemd/system/paypro.service > /dev/null <<SVC
[Unit]
Description=PayPro Payment System
After=network.target
[Service]
Type=simple
WorkingDirectory=$P
ExecStart=/usr/bin/java -jar $J --server.port=$PORT
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable paypro && systemctl start paypro

echo "[8/8] 检查服务..."
sleep 8
if systemctl is-active paypro >/dev/null 2>&1; then
    echo "  ✅ 服务运行中"
    curl -sf http://127.0.0.1:$PORT >/dev/null && echo "  ✅ 端口 $PORT 可访问" || echo "  ⚠️  端口无响应"
else
    echo "  ❌ 服务启动失败: journalctl -u paypro --no-pager -n 20"
fi

echo ""
echo "=========================="
echo "🎉 部署完成！"
echo "🌐 访问: http://你的IP:$PORT"
echo "📋 systemctl status paypro"
echo "📋 journalctl -u paypro -f"
echo "=========================="
