#!/bin/bash
echo "=== PayPro 彻底卸载 ==="
echo "⚠️  将删除：服务/数据库/代码/日志"
read -p "确认卸载？(y/n) " yn
[ "$yn" != "y" ] && [ "$yn" != "Y" ] && echo "已取消" && exit 0

echo "[1/5] 停止服务..."
systemctl stop paypro 2>/dev/null
systemctl disable paypro 2>/dev/null
rm -f /etc/systemd/system/paypro.service
systemctl daemon-reload
echo "  ✅ 服务已移除"

echo "[2/5] 删除代码..."
rm -rf /www/wwwroot/paypro
echo "  ✅ 代码已删除"

echo "[3/5] 删除数据库..."
mysql -u root $( [ -f /root/.my.cnf ] && echo "--defaults-extra-file=/root/.my.cnf" ) -e "DROP DATABASE IF EXISTS paypro; DROP USER IF EXISTS 'paypro'@'localhost';" 2>/dev/null && echo "  ✅ 数据库已删除" || echo "  ⚠️  数据库删除失败（可能已不存在）"

echo "[4/5] 清理日志..."
rm -f /var/log/paypro* 2>/dev/null
journalctl --rotate 2>/dev/null
echo "  ✅ 日志已清理"

echo "[5/5] 清理临时文件..."
rm -f /tmp/paypro* 2>/dev/null
echo "  ✅ 临时文件已清理"

echo ""
echo "=========================="
echo "🗑️  PayPro 已彻底卸载"
echo "=========================="
