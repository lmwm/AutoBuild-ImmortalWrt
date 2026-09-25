#!/bin/bash
#
# Cudy TR3000 自定义软件包
# 此脚本在 feeds install 之后、make defconfig 之前执行
# 由 AutoBuild.yml 的 [3.1] 步骤调用
#
# 用法：在 immortalwrt 源码根目录下执行
#

set -e

OPENWRT_DIR="$(pwd)"

# -----------------------------------------------------------
# luci-theme-argon (最新版)
# 删除 feeds 旧版本，克隆到 package/app/
# -----------------------------------------------------------
#find "$OPENWRT_DIR/package/feeds/" -name "luci-theme-argon" -exec rm -rf {} + 2>/dev/null
#git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git \
#    "$OPENWRT_DIR/package/app/luci-theme-argon"
#echo "[OK] 已添加: luci-theme-argon"

# -----------------------------------------------------------
# luci-app-argon-config (配套)
# 删除 feeds 旧版本，克隆到 package/app/
# -----------------------------------------------------------
#find "$OPENWRT_DIR/package/feeds/" -name "luci-app-argon-config" -exec rm -rf {} + 2>/dev/null
#git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git \
#    "$OPENWRT_DIR/package/app/luci-app-argon-config"
#echo "[OK] 已添加: luci-app-argon-config"

# -----------------------------------------------------------
# OpenClash
# 删除 feeds 旧版本，克隆到 package/app/
# -----------------------------------------------------------
#find "$OPENWRT_DIR/package/feeds/" -name "luci-app-openclash" -exec rm -rf {} + 2>/dev/null
#git clone --depth 1 https://github.com/vernesong/OpenClash.git \
#    "$OPENWRT_DIR/package/app/OpenClash"
#echo "[OK] 已添加: OpenClash (luci-app-openclash)"

# -----------------------------------------------------------
# （已移除）OpenAppFilter
#
# 历史：此前在此克隆 OpenAppFilter（luci-app-oaf/appfilter/kmod-oaf）
#       并给 oaf/Makefile 打 KCFLAGS 补丁（修复 6.12 内核的
#       -Wstrict-prototypes 编译错误）。现已按需求移除 luci-app-oaf，
#       克隆与补丁一并删除。
# -----------------------------------------------------------

# -----------------------------------------------------------

# -----------------------------------------------------------
# luci-app-harbor-file
# 克隆到 package/app/
# -----------------------------------------------------------
#git clone --depth 1 #https://github.com/destan19/luci-app-harbor-file.git \
#    "$OPENWRT_DIR/package/app/luci-app-harbor-file"
#echo "[OK] 已添加: luci-app-harbor-file"
