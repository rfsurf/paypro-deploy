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
    echo "  ✅ Redis 已安装"
    redis-cli ping &>/dev/null && echo "  ✅ Redis 运行中" || (systemctl start redis 2>/dev/null && systemctl enable redis 2>/dev/null && echo "  ✅ Redis 已启动")
    REDIS_OK=true
elif [ -d /www/server/redis ]; then
    echo "  ✅ 宝塔 Redis 已安装"
    /www/server/redis/bin/redis-cli ping &>/dev/null && echo "  ✅ Redis 运行中" || (/etc/init.d/redis start 2>/dev/null || systemctl start redis 2>/dev/null)
    systemctl enable redis 2>/dev/null
    REDIS_OK=true
fi

if [ "$REDIS_OK" = false ]; then
    echo "  → Redis 未安装，正在自动安装..."
    yum install -y redis --allowerasing --nobest 2>/dev/null && {
        systemctl start redis && systemctl enable redis && echo "  ✅ Redis yum 安装成功"
        REDIS_OK=true
    } || {
        if [ -f /www/server/panel/install/redis.sh ]; then
            echo "  → 使用宝塔脚本安装 Redis..."
            bash /www/server/panel/install/redis.sh install 2>/dev/null && {
                /etc/init.d/redis start 2>/dev/null || systemctl start redis 2>/dev/null
                echo "  ✅ 宝塔 Redis 安装成功"
                REDIS_OK=true
            }
        fi
    }
    if [ "$REDIS_OK" = false ]; then
        echo "  ❌ Redis 自动安装失败，请在宝塔面板 → 软件商店 安装 Redis"
        exit 1
    fi
fi

[ -d /www/server/mysql ] && export PATH="/www/server/mysql/bin:$PATH"

echo "[2/8] 获取MySQL root密码..."
MYSQL_PASS="$MYSQL_ROOT_PASS"
# 尝试自动获取覆盖
for f in /www/server/panel/config.pl /root/.my.cnf /www/server/mysql/password.pl /www/server/panel/data/default.pl /www/server/mysql/my.cnf; do
    if [ -f "$f" ]; then
        TMP=$(grep -oP '(?:password|passwd)\s*=\s*\K[^\s]+' "$f" 2>/dev/null || cat "$f" 2>/dev/null)
        [ -n "$TMP" ] && [ ${#TMP} -gt 4 ] && MYSQL_PASS="$TMP" && echo "  → 从 $f 获取"
    fi
done
# bt 面板默认密码路径
if [ -z "$MYSQL_PASS" ] && command -v bt &>/dev/null; then
    MYSQL_PASS=$(bt 14 2>/dev/null | head -1)
fi
[ -z "$MYSQL_PASS" ] && { echo "❌ MySQL密码为空"; exit 1; }
echo "  ✅ 已获取 MySQL 密码"

echo "[3/8] 创建数据库..."
mysql -u root -p"${MYSQL_PASS}" -e "CREATE DATABASE IF NOT EXISTS $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && echo "  ✅ 数据库已创建" || echo "  ⚠️  数据库可能已存在，跳过"

echo "[4/8] 获取代码..."
mkdir -p $P && cd $P
if [ -d .git ]; then
    git pull
else
    git clone https://github.com/codewendao/PayPro.git .
fi
echo "  ✅ 代码已就绪"

echo "[5/8] 配置修改..."
cd $P
cp src/main/resources/application.yml{,.bak}
# 查看配置文件实际格式
echo "  → 当前配置内容："
grep -n "datasource\|url\|username\|password\|domain\|redis" src/main/resources/application.yml | head -15
echo ""
python3 << 'PYEOF'
import re
f='src/main/resources/application.yml'
c=open(f).read()
c=re.sub(r'jdbc:mysql://[^\s"]+','jdbc:mysql://localhost:3306/paypro?useUnicode=true&characterEncoding=utf-8&useSSL=false&serverTimezone=Asia/Shanghai',c)
# 只改 datasource 块下的 password，不改 mail 等其他 password
c=re.sub(r'(spring:\s*\n.*?datasource:\s*\n(?:.*\n)*?password:\s*)\S+','\1PayPro@2026Secure',c,flags=re.DOTALL,count=1)
c=re.sub(r'(spring:\s*\n.*?datasource:\s*\n(?:.*\n)*?username:\s*)\S+','\1paypro',c,flags=re.DOTALL,count=1)
c=re.sub(r'(domain:\s*)\S+','\1https://agent-token.top',c)
open(f,'w').write(c)
print('  ✅ 配置已更新')
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
RestartSec=5
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable paypro
systemctl start paypro

echo "[8/8] 检查服务..."
sleep 5
if systemctl is-active paypro >/dev/null 2>&1; then
    echo "  ✅ 服务运行中"
    if curl -sf http://127.0.0.1:$PORT >/dev/null; then
        echo "  ✅ 端口 $PORT 可访问"
    else
        echo "  ⚠️  服务运行中但端口无响应，可能是启动慢或配置错误"
        echo "  → 查看日志: journalctl -u paypro --no-pager -n 30"
        echo "  → 查看端口: ss -tlnp | grep $PORT"
    fi
else
    echo "  ❌ 服务启动失败"
    journalctl -u paypro --no-pager -n 30
fi

echo ""
echo "=========================="
echo "🎉 部署流程完成！"
echo "🌐 访问: http://你的IP:8080"
echo "📋 systemctl status paypro"
echo "📋 journalctl -u paypro -f"
echo "=========================="
