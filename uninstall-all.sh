#!/bin/bash
echo "=== PayPro 彻底卸载清理 ==="
read -p "确认卸载？(y/n) " yn
[ "$yn" != "y" ] && [ "$yn" != "Y" ] && echo "已取消" && exit 0

echo "[1/5] 停止服务..."
systemctl stop paypro 2>/dev/null || true
systemctl stop paypro-premium 2>/dev/null || true
systemctl disable paypro 2>/dev/null || true
systemctl disable paypro-premium 2>/dev/null || true
rm -f /etc/systemd/system/paypro.service /etc/systemd/system/paypro-premium.service
systemctl daemon-reload
pkill -f "java.*pay" 2>/dev/null || true
echo "  ✅ 服务已停止"

echo "[2/5] 删除代码..."
rm -rf /www/wwwroot/paypro /www/wwwroot/paypro-premium
echo "  ✅ 代码已删除"

echo "[3/5] 删除数据库..."
mysql -u root $( [ -f /root/.my.cnf ] && echo "--defaults-extra-file=/root/.my.cnf" ) -e "DROP DATABASE IF EXISTS paypro;" 2>/dev/null || mysql -u root -p'd886355845ba8327' -e "DROP DATABASE IF EXISTS paypro;" 2>/dev/null
echo "  ✅ 数据库已删除"

echo "[4/5] 清理Swap..."
swapoff /swapfile 2>/dev/null || true
rm -f /swapfile
echo "  ✅ Swap已清理"

echo "[5/5] 清理日志和临时文件..."
rm -f /var/log/paypro* /tmp/paypro* /tmp/pay-1.0-SNAPSHOT.jar
journalctl --rotate 2>/dev/null
echo "  ✅ 已清理"

echo ""
echo "🗑️  PayPro 已彻底卸载"
