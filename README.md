# 提示
## 如果不清楚本仓库的代码的作用，请不要随意下载并运行
# 脚本说明
- 适用于骷髅头FusionWrt固件进行在线升级(2G内存以下设备大概率会失败)，脚本中可选R4S/DN2/X86。
```
wget https://raw.githubusercontent.com/xuanranran/scripts/main/onlineupdate.sh && sh onlineupdate.sh
```
 - 如果出现“raw.githubusercontent.com|0.0.0.0”，可以尝试使用下述命令后，再使用升级脚本。
```
echo "185.199.109.133  raw.githubusercontent.com" >> /etc/hosts
```
- 适用Openwrt扩容（新建分区），Docker根目录为/opt/docker的固件，将会修改Docker根目录使其挂载至新分区。
```
wget https://raw.githubusercontent.com/xuanranran/scripts/main/incr.sh && sh incr.sh
```
- 适用于含Docker的Openwrt固件，安装/操作 双Adg容器。（默认路径为Flippy Op固件的/mnt/mmcblk2p4）
- 其余设备食用，需手动设定容器目录(修改后会自动退出 输入sh adg.sh重新运行脚本），或者修改default_path模块中的save_path。
```
wget https://raw.githubusercontent.com/xuanranran/scripts/main/adg.sh && sh adg.sh
```
- 适用于Flippy Arm盒子+Op固件，精简插件，保留最重要的SSRP+动态DNS（已验证）。
```
wget https://raw.githubusercontent.com/xuanranran/scripts/main/remove.sh && sh remove.sh
```
- 多合一脚本，目前只有双Adg，更多脚本待开发？？(有空再改，貌似联动有问题)
```
wget https://raw.githubusercontent.com/xuanranran/scripts/main/script.sh && sh script.sh
```
