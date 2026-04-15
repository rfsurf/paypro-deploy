#!/bin/bash
echo "=== PayPro 高级版 彻底卸载 ==="
read -p "确认卸载？(y/n) " yn
[ "$yn" != "y" ] && [ "$yn" != "Y" ] && echo "已取消" && exit 0

systemctl stop paypro-premium 2>/dev/null
systemctl disable paypro-premium 2>/dev/null
rm -f /etc/systemd/system/paypro-premium.service
systemctl daemon-reload
rm -rf /www/wwwroot/paypro-premium
mysql -u root $( [ -f /root/.my.cnf ] && echo "--defaults-extra-file=/root/.my.cnf" ) -e "DROP DATABASE IF EXISTS paypro;" 2>/dev/null
journalctl --rotate 2>/dev/null
echo "🗑️  PayPro 高级版已彻底卸载"
