#!/bin/bash

apk add luci-app-xlnetacc luci-i18n-xlnetacc-zh-cn

cd ..

curl -s https://raw.githubusercontent.com/xuanranran/luci-app-xlnetacc/refs/heads/master/luasrc/model/cbi/xlnetacc.lua > /usr/lib/lua/luci/model/cbi/xlnetacc.lua
curl -s https://raw.githubusercontent.com/xuanranran/luci-app-xlnetacc/refs/heads/master/luasrc/view/xlnetacc/logview.htm > /usr/lib/lua/luci/view/xlnetacc/logview.htm
curl -s https://raw.githubusercontent.com/xuanranran/luci-app-xlnetacc/refs/heads/master/root/usr/bin/xlnetacc.sh > /usr/bin/xlnetacc.sh

reboot -f