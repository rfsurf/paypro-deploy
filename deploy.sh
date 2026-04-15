#!/bin/bash
set -e
P="/www/wwwroot/paypro"
DB="paypro"
U="paypro"
PW="PayPro@2026Secure"
PORT=8080
echo "=== PayPro 宝塔一键部署 ==="

echo "[1/7] 环境检查..."
command -v java &>/dev/null || yum install -y java-17-openjdk java-17-openjdk-devel
command -v mvn &>/dev/null || yum install -y maven
command -v git &>/dev/null || yum install -y git
[ -d /www/server/mysql ] && export PATH="/www/server/mysql/bin:$PATH"
command -v redis-cli &>/dev/null || [ -d /www/server/redis ] || { echo "❌ 请先在宝塔面板安装 Redis"; exit 1; }

echo "[2/7] 获取MySQL root密码..."
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

echo "[3/7] 创建数据库..."
mysql -u root -p"${MYSQL_PASS}" -e "CREATE DATABASE IF NOT EXISTS $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" && echo "  ✅ 数据库已创建"

echo "[4/7] 获取代码..."
mkdir -p $P && cd $P
if [ -d .git ]; then
    git pull
else
    git clone https://github.com/codewendao/PayPro.git .
fi
echo "  ✅ 代码已就绪"

echo "[5/7] 配置修改..."
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

echo "[6/7] 构建项目 (首次需3-5分钟)..."
cd $P
mvn clean package -DskipTests
J=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)

echo "[7/7] 启动服务..."
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

echo ""
echo "=========================="
echo "🎉 部署完成！"
echo "🌐 访问: http://你的IP:8080"
echo "📋 systemctl status paypro"
echo "📋 journalctl -u paypro -f"
echo "=========================="
