#!/bin/bash
set -e
P="/www/wwwroot/paypro"
DB="paypro"
U="paypro"
PW="PayPro@2026Secure"
PORT=8080
echo "=== PayPro 宝塔一键部署 ==="
echo "[1/6] 环境检查..."
command -v java &>/dev/null || yum install -y java-17-openjdk java-17-openjdk-devel
command -v mvn &>/dev/null || yum install -y maven
command -v mysql &>/dev/null || [ -d /www/server/mysql ] || { echo "❌ 请先在宝塔面板安装 MySQL"; exit 1; }
[ -d /www/server/mysql ] && export PATH="/www/server/mysql/bin:$PATH"
command -v redis-cli &>/dev/null || [ -d /www/server/redis ] || { echo "❌ 请先在宝塔面板安装 Redis"; exit 1; }
echo "[2/6] 创建数据库..."
MC="" && [ -f /root/.my.cnf ] && MC="--defaults-extra-file=/root/.my.cnf"
mysql $MC -e "CREATE DATABASE IF NOT EXISTS $DB DEFAULT CHARACTER SET utf8mb4; CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$PW'; GRANT ALL ON $DB.* TO '$U'@'localhost'; FLUSH PRIVILEGES;" && echo "  ✅ 数据库已创建"
echo "[3/6] 获取代码..."
mkdir -p $P && cd $P && ([ -d .git ] && git pull || git clone https://github.com/codewendao/PayPro.git .) && echo "  ✅ 代码已就绪"
echo "[4/6] 配置修改..."
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
echo "[5/6] 构建项目..."
mvn clean package -DskipTests
J=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)
echo "[6/6] 启动服务..."
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
