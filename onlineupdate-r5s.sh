#!/bin/bash
cd /tmp
mount -t tmpfs -o remount,size=100% tmpfs /tmp
wget https://github.com/xuanranran/OpenWrt_RockChip/releases/latest/download/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz
gunzip immortalwrt-rockchip-armv8-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz
sysupgrade -F immortalwrt-rockchip-armv8-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img