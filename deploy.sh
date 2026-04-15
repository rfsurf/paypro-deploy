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
if [ -d .git ]; then git pull; else git clone --depth 1 https://gitee.com/luo2422003895/PayPro.git .; fi
echo "  ✅ 代码已就绪"

echo "[5/8] 重写配置文件..."
cp src/main/resources/application.yml{,.bak}

cat > src/main/resources/application.yml << 'YAML'
server:
  port: 8080

spring:
  profiles:
    active: local
  mail:
    host: smtp.163.com
    password: xxxx
    port: 25
    properties:
      mail:
        smtp:
          auth: true
          starttls:
            enable: true
            required: true
          ssl:
            trust: "smtp.163.com"
    username: codewendao@163.com
  output:
    ansi:
      enabled: DETECT
  thymeleaf:
    cache: false
    enabled: true
    mode: LEGACYHTML5
  datasource:
    driverClassName: com.mysql.jdbc.Driver
    filters: stat,wall,log4j
    initialSize: 5
    maxActive: 20
    maxPoolPreparedStatementPerConnectionSize: 20
    maxWait: 60000
    minEvictableIdleTimeMillis: 300000
    minIdle: 5
    password: PayPro@2026Secure
    poolPreparedStatements: true
    testOnBorrow: false
    testOnReturn: false
    testWhileIdle: true
    timeBetweenEvictionRunsMillis: 60000
    type: com.alibaba.druid.pool.DruidDataSource
    url: jdbc:mysql://127.0.0.1:3306/paypro?useSSL=false&characterEncoding=utf-8&serverTimezone=Asia/Shanghai
    username: paypro
    validationQuery: SELECT 1 FROM DUAL
  redis:
    database: 1
    host: 127.0.0.1
    password:
    pool:
      max-active: -1
      max-idle: 8
      max-wait: -1
      min-idle: 0
    port: 6379
    timeout: 10000

mybatis-plus:
  configuration:
    log-impl: org.apache.ibatis.logging.stdout.StdOutImpl
  mapper-locations: classpath*:mapper/*.xml
  global-config:
    db-config:
      update-strategy: NOT_EMPTY
      logic-delete-field: delFlag
      logic-delete-value: 1
      logic-not-delete-value: 0

paypro:
  alipayCustomQrUrl: https://qr.alipay.com/fkx17492eze99maemka1u81
  alipayUserId: 2088122989840531
  indexTitle: PayPro个人收款系统
  name: codewendao
  title: PayPro个人收款系统
  site: https://agent-token.top
  mobile: xxxxxx
  email:
    receiver: 958625993@qq.com
    sender: codewendao@163.com
  rateLimit:
    ipExpire: 2
  token:
    value: paypro-token-2026
    expire: 14
  qrCodeNum: 2
  openapi:
    secret: your_openapi_secret_key_here
  payMethods:
    - id: 'alipay'
      name: '支付宝支付'
      description: '免输备注，手动收款'
      icon: '🔵'
      status: true
      allow-night: false
      use-local-qr-code: false
    - id: 'wechat'
      name: '微信支付'
      description: '需备注，自动确认收款'
      icon: '🟢'
      status: true
      allow-night: true
      use-local-qr-code: true
    - id: 'wechat_zs'
      name: '微信赞赏码支付'
      description: '需备注，自动确认收款'
      icon: '🟢'
      status: true
      allow-night: false
      use-local-qr-code: true
    - id: 'alipay_dmf'
      name: '支付宝当面付'
      description: '支付宝官方产品，无需营业执照，免备注自动收款'
      icon: '🔵'
      status: true
      allow-night: true
      use-local-qr-code: false
YAML

echo "  ✅ 配置文件已重写（不再用Python正则）"

echo "[6/8] 构建项目 (首次需3-5分钟)..."
cd $P
MAVEN_OPTS="-Xmx256m -Xms128m" mvn clean package -DskipTests
J=$(find target -name "*.jar" -not -name "*-sources.jar" | head -1)
echo "  → JAR: $J"

echo "[7/8] 启动服务..."
systemctl stop paypro 2>/dev/null || true
rm -f /etc/systemd/system/paypro.service
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
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable paypro && systemctl start paypro

echo "[8/8] 检查服务..."
sleep 10
if systemctl is-active paypro >/dev/null 2>&1; then
    echo "  ✅ 服务运行中"
    curl -sf http://127.0.0.1:$PORT >/dev/null && echo "  ✅ 端口 $PORT 可访问" || echo "  ⚠️  端口无响应，等一会儿再试"
else
    echo "  ❌ 服务启动失败"
    journalctl -u paypro --no-pager -n 15
fi

echo ""
echo "=========================="
echo "🎉 部署完成！"
echo "🌐 访问: http://你的IP:$PORT"
echo "📋 systemctl status paypro"
echo "📋 journalctl -u paypro -f"
echo "=========================="
