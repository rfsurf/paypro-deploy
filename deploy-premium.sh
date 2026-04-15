#!/bin/bash
set -e
P="/www/wwwroot/paypro-premium"
DB="paypro"
U="paypro"
PW="PayPro@2026Secure"
PORT=8080
MYSQL_ROOT_PASS="d886355845ba8327"
GITEE_USER="luo2422003895"
GITEE_TOKEN="a57cb5c970603edda9a7f68752885ab2"
echo "=== PayPro 高级版 宝塔一键部署 ==="

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
mysql -u root -p"${MYSQL_PASS}" -e "DROP DATABASE IF EXISTS $DB; CREATE DATABASE $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && echo "  ✅ 数据库已创建（含重置）"

echo "[4/8] 获取代码..."
mkdir -p $P && cd $P
if [ -d .git ]; then
    git pull
else
    git clone --depth 1 https://${GITEE_USER}:${GITEE_TOKEN}@gitee.com/${GITEE_USER}/paypro-premium.git .
fi
echo "  ✅ 代码已就绪（高级版）"

echo "[5/8] 导入数据库..."
cd $P
mysql -u $U -p"$PW" $DB < src/main/resources/pay.sql 2>/dev/null && echo "  ✅ 数据库表已导入（含管理员账号）" || echo "  ⚠️  数据库导入可能有问题"

echo "[6/8] 修改配置..."
cd $P
cp src/main/resources/application.yml{,.bak}
python3 << 'PYEOF'
lines = open('src/main/resources/application.yml').readlines()
result = []
section = ""
subsection = ""
for line in lines:
    s = line.strip()
    if s and not line.startswith(' ') and ':' in s:
        section = s.split(':')[0].strip()
        subsection = ""
    elif line.startswith('  ') and not line.startswith('    ') and ':' in s:
        subsection = s.split(':')[0].strip()
    
    indent = len(line) - len(line.lstrip())
    
    if section == 'server' and s.startswith('port:'):
        result.append(' ' * indent + 'port: 8080\n')
        continue
    
    if subsection == 'datasource' and s.startswith('url:') and 'jdbc:mysql' in s:
        result.append(' ' * indent + 'url: jdbc:mysql://127.0.0.1:3306/paypro?useSSL=false&characterEncoding=utf-8&serverTimezone=Asia/Shanghai\n')
        continue
    
    if subsection == 'datasource' and s.startswith('username:') and 'root' in s:
        result.append(' ' * indent + 'username: paypro\n')
        continue
    
    if subsection == 'datasource' and s.startswith('password:') and 'xxxx' in s:
        result.append(' ' * indent + 'password: PayPro@2026Secure\n')
        continue
    
    if section == 'paypro' and s.startswith('site:'):
        result.append(' ' * indent + 'site: https://agent-token.top\n')
        continue
    
    if section == 'paypro' and s.startswith('token:') and not line.startswith('  '):
        result.append(' ' * indent + 'token:\n')
        continue
    
    result.append(line)

# Add GameUrl at the end if not present
final = ''.join(result)
if 'GameUrl' not in final:
    final += '\nGameUrl: https://agent-token.top\n'
open('src/main/resources/application.yml', 'w').write(final)
print('  ✅ 配置已更新（含 GameUrl 修复）')
    
    result.append(line)

open('src/main/resources/application.yml', 'w').writelines(result)
print('  ✅ 配置已更新')
PYEOF

echo "[7/8] 构建项目 (首次需3-5分钟)..."
cd $P
MAVEN_OPTS="-Xmx256m -Xms128m" mvn clean package -DskipTests
J=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)
echo "  → JAR: $J"

echo "[8/8] 启动服务..."
systemctl stop paypro-premium 2>/dev/null || true
rm -f /etc/systemd/system/paypro-premium.service
tee /etc/systemd/system/paypro-premium.service > /dev/null <<SVC
[Unit]
Description=PayPro Premium Payment System
After=network.target
[Service]
Type=simple
WorkingDirectory=$P
ExecStart=/usr/bin/java -jar $J --server.port=$PORT
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable paypro-premium && systemctl start paypro-premium

echo ""
echo "=== 检查服务 ==="
sleep 10
if systemctl is-active paypro-premium >/dev/null 2>&1; then
    echo "  ✅ 服务运行中"
    curl -sf http://127.0.0.1:$PORT >/dev/null && echo "  ✅ 端口 $PORT 可访问" || echo "  ⚠️  端口无响应，可能是启动慢"
else
    echo "  ❌ 服务启动失败"
    journalctl -u paypro-premium --no-pager -n 15
fi

echo ""
echo "=========================="
echo "🎉 PayPro 高级版 部署完成！"
echo "=========================="
echo ""
echo "🌐 前台访问: http://你的IP:$PORT"
echo "🔐 后台管理: http://你的IP:$PORT/admin/login.html"
echo "👤 默认账号: admin / admin123"
echo "📊 API文档:  http://你的IP:$PORT/swagger-ui.html"
echo ""
echo "📋 管理命令:"
echo "   systemctl status paypro-premium"
echo "   journalctl -u paypro-premium -f"
echo "   systemctl restart paypro-premium"
echo "=========================="
