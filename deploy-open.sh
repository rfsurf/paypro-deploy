#!/bin/bash
set -e
P="/www/wwwroot/paypro"
DB="paypro"
U="paypro"
PW="PayPro@2026Secure"
PORT=8080
MYSQL_ROOT_PASS="d886355845ba8327"

echo "=== PayPro 开源版 · 宝塔部署 ==="

echo "[1/7] 环境检查..."
command -v java &>/dev/null || yum install -y --skip-broken java-17-openjdk java-17-openjdk-devel
command -v mvn &>/dev/null || yum install -y --skip-broken maven
command -v git &>/dev/null || yum install -y --skip-broken git

REDIS_OK=false
if command -v redis-cli &>/dev/null; then
    redis-cli ping &>/dev/null && REDIS_OK=true || { systemctl start redis 2>/dev/null && systemctl enable redis 2>/dev/null; REDIS_OK=true; }
elif [ -d /www/server/redis ]; then
    /www/server/redis/bin/redis-cli ping &>/dev/null && REDIS_OK=true || /etc/init.d/redis start 2>/dev/null
    REDIS_OK=true
fi
if [ "$REDIS_OK" = false ]; then
    yum install -y redis --allowerasing --nobest 2>/dev/null && systemctl start redis && systemctl enable redis && REDIS_OK=true
fi
[ "$REDIS_OK" = false ] && { echo "❌ 请先在宝塔安装 Redis"; exit 1; }
echo "  ✅ Redis 就绪"

[ -d /www/server/mysql ] && export PATH="/www/server/mysql/bin:$PATH"

echo "[2/7] MySQL 密码..."
MYSQL_PASS="$MYSQL_ROOT_PASS"
for f in /www/server/panel/config.pl /root/.my.cnf /www/server/mysql/password.pl; do
    if [ -f "$f" ]; then
        TMP=$(grep -oP '(?:password|passwd)\s*=\s*\K\S+' "$f" 2>/dev/null || cat "$f" 2>/dev/null)
        [ -n "$TMP" ] && [ ${#TMP} -gt 4 ] && MYSQL_PASS="$TMP"
    fi
done
echo "  ✅ 已获取"

echo "[3/7] 创建数据库..."
mysql -u root -p"${MYSQL_PASS}" -e "CREATE DATABASE IF NOT EXISTS $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
echo "  ✅ 数据库已创建"

echo "[4/7] 获取代码..."
mkdir -p $P && cd $P
if [ -d .git ]; then
    git pull
else
    git clone --depth 1 https://gitee.com/luo2422003895/PayPro.git .
fi
echo "  ✅ 代码已就绪"

echo "[5/7] 修复配置..."
cd $P
sed -i 's|<version>${lombok.version}</version>|<version>1.18.30</version>|' pom.xml 2>/dev/null || true

python3 << 'PYEOF'
f = 'src/main/resources/application.yml'
c = open(f, 'r', encoding='utf-8').read()
c = c.replace('🔵', 'blue').replace('🟢', 'green')
open(f, 'w', encoding='utf-8').write(c)
print("  ✅ 配置已修复（emoji → text）")
PYEOF

echo "[6/7] 构建项目 (限制内存256MB, 约3分钟)..."
cd $P
export MAVEN_OPTS="-Xmx256m -Xms128m"
mvn clean package -DskipTests
JAR=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)
echo "  ✅ 构建完成: $JAR"

echo "[7/7] 启动服务..."
systemctl stop paypro 2>/dev/null || true
rm -f /etc/systemd/system/paypro.service
cat > /etc/systemd/system/paypro.service << SVC
[Unit]
Description=PayPro Payment System
After=network.target
[Service]
Type=simple
WorkingDirectory=$P
ExecStart=/usr/bin/java -Xms128m -Xmx384m -jar $JAR --server.port=$PORT
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable paypro && systemctl start paypro

echo ""
echo "=== 检查服务 ==="
sleep 10
if systemctl is-active paypro >/dev/null 2>&1; then
    echo "  ✅ 服务运行中"
    curl -sf http://127.0.0.1:$PORT >/dev/null && echo "  ✅ 端口 $PORT 可访问" || echo "  ⚠️  启动中"
else
    echo "  ❌ 启动失败: journalctl -u paypro -n 15"
fi

echo ""
echo "=========================="
echo "🎉 PayPro 开源版 部署完成！"
echo "🌐 http://你的IP:$PORT"
echo "📋 systemctl status paypro"
echo "=========================="
