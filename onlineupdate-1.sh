#!/bin/bash
#=================================================
# File name: onlineupdate.sh
# System Required: Linux
#=================================================
cd /tmp
mount -t tmpfs -o remount,size=100% tmpfs /tmp
wget https://github.moeyy.xyz/https://github.com/xuanranran/OpenWRT-X86_64/releases/latest/download/immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz
gunzip immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz
sysupgrade -F immortalwrt-x86-64-generic-squashfs-combined-efi.img