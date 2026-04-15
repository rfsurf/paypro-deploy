#!/bin/bash
set -e
P="/www/wwwroot/paypro"
DB="paypro"
U="paypro"
PW="PayPro@2026Secure"
PORT=8080
echo "=== PayPro 宝塔一键部署 ==="

echo "[1/8] 环境检查..."
command -v java &>/dev/null || yum install -y java-17-openjdk java-17-openjdk-devel
command -v mvn &>/dev/null || yum install -y maven
command -v git &>/dev/null || yum install -y git

# Redis 检测 + 自动安装
if command -v redis-cli &>/dev/null; then
    echo "  ✅ Redis 已安装"
    redis-cli ping &>/dev/null && echo "  ✅ Redis 运行中" || (systemctl start redis && systemctl enable redis && echo "  ✅ Redis 已启动")
elif [ -d /www/server/redis ]; then
    echo "  ✅ 宝塔 Redis 已安装"
    /www/server/redis/bin/redis-cli ping &>/dev/null && echo "  ✅ Redis 运行中" || (/etc/init.d/redis start 2>/dev/null || systemctl start redis 2>/dev/null && systemctl enable redis 2>/dev/null && echo "  ✅ Redis 已启动")
else
    echo "  → Redis 未安装，正在自动安装..."
    yum install -y epel-release 2>/dev/null
    yum install -y redis 2>/dev/null || {
        echo "  ⚠️  yum 安装失败，尝试宝塔命令行安装..."
        if [ -f /www/server/panel/install/redis.sh ]; then
            bash /www/server/panel/install/redis.sh install 2>/dev/null
        else
            echo "  ❌ 自动安装失败，请在宝塔面板 → 软件商店 安装 Redis"
            exit 1
        fi
    }
    systemctl start redis && systemctl enable redis
    echo "  ✅ Redis 已安装并启动"
fi

[ -d /www/server/mysql ] && export PATH="/www/server/mysql/bin:$PATH"

echo "[2/8] 获取MySQL root密码..."
MYSQL_PASS=""
if [ -f /www/server/panel/config.pl ]; then
    MYSQL_PASS=$(cat /www/server/panel/config.pl 2>/dev/null)
fi
if [ -z "$MYSQL_PASS" ] && [ -f /root/.my.cnf ]; then
    MYSQL_PASS=$(grep -oP 'password\s*=\s*\K.*' /root/.my.cnf 2>/dev/null)
fi
if [ -z "$MYSQL_PASS" ] && [ -f /www/server/mysql/password.pl ]; then
    MYSQL_PASS=$(cat /www/server/mysql/password.pl 2>/dev/null)
fi
if [ -z "$MYSQL_PASS" ] && [ -f /www/server/panel/data/default.pl ]; then
    MYSQL_PASS=$(cat /www/server/panel/data/default.pl 2>/dev/null)
fi
if [ -z "$MYSQL_PASS" ]; then
    echo "  ⚠️  未自动获取到 MySQL root 密码"
    echo "  请在宝塔面板 -> 数据库 -> root密码 查看"
    read -p "  输入 MySQL root 密码: " MYSQL_PASS
fi
echo "  ✅ 已获取 MySQL 密码"

echo "[3/8] 创建数据库..."
mysql -u root -p"${MYSQL_PASS}" -e "CREATE DATABASE IF NOT EXISTS $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" && echo "  ✅ 数据库已创建"

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
python3 -c "
import re
f='src/main/resources/application.yml'; c=open(f).read()
c=re.sub(r'jdbc:mysql://\S+','jdbc:mysql://localhost:3306/paypro?useUnicode=true&characterEncoding=utf-8&useSSL=false&serverTimezone=Asia/Shanghai',c)
c=re.sub(r'(username:\s*)\S+',r'\1paypro',c)
c=re.sub(r'(password:\s*)\S+',r'\1PayPro@2026Secure',c)
c=re.sub(r'(domain:\s*)\S+',r'\1https://agent-token.top',c)
open(f,'w').write(c); print('  ✅ 配置已更新')
"

echo "[6/8] 构建项目 (首次需3-5分钟)..."
cd $P
mvn clean package -DskipTests
J=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)

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
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable paypro && systemctl start paypro

echo "[8/8] 检查端口..."
sleep 3
if curl -s http://127.0.0.1:$PORT >/dev/null; then
    echo "  ✅ 服务运行正常"
else
    echo "  ⚠️  服务未响应，查看日志: journalctl -u paypro -f"
fi

echo ""
echo "=========================="
echo "🎉 部署完成！"
echo "🌐 访问: http://你的IP:8080"
echo "📋 systemctl status paypro"
echo "📋 journalctl -u paypro -f"
echo "=========================="
