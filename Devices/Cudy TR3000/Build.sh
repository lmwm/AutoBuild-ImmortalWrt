#!/bin/bash
#
# Cudy TR3000 构建脚本（外部软件包 + 设备定制）
#
# 执行时机（均在源码树/SDK 根目录下执行）：
#   FullBuild.yml    [3.1]：feeds install 之后、make defconfig 之前，完整执行
#   ImageBuilder.yml [IB.2]：SDK 内 feeds install 之后执行（外部包段有效；
#                     设备定制段的目标文件在 SDK 中不存在，自动跳过）
#
# 段落约定（顺序即执行顺序）：
#   1) 外部软件包：git clone 到 package/app/，必要时对外部包打补丁
#   2) 设备定制：改 DTS、内核配置等（仅 FullBuild 源码树中生效）
#
# 历史：本文件由原 Packages.sh 与 Customize.sh 合并而来（两段各取其一）。
#

set -e

OPENWRT_DIR="$(pwd)"

# ============================================================
# 1) 外部软件包（克隆到 package/app/）
# ============================================================

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
# luci-app-harbor-file
# 克隆到 package/app/
# -----------------------------------------------------------
#git clone --depth 1 https://github.com/destan19/luci-app-harbor-file.git \
#    "$OPENWRT_DIR/package/app/luci-app-harbor-file"
#echo "[OK] 已添加: luci-app-harbor-file"

# ============================================================
# 2) 设备定制（DTS、内核配置等）
# ============================================================

# -----------------------------------------------------------
# 修改设备型号名称
# -----------------------------------------------------------
DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"

if [ -f "$DTS_FILE" ]; then
    sed -i 's/Cudy TR3000 v1 (OpenWrt U-Boot layout)/Cudy TR3000/g' "$DTS_FILE"
    echo "[OK] 设备型号已修改: Cudy TR3000 v1 (OpenWrt U-Boot layout) -> Cudy TR3000"
else
    echo "[WARN] DTS 文件不存在: $DTS_FILE，跳过型号修改（ImageBuilder/SDK 中属正常）"
fi

# -----------------------------------------------------------
# 其他设备定制（按需添加）
# -----------------------------------------------------------
# 示例：修改默认 IP
# sed -i 's/192.168.1.1/192.168.50.1/g' package/base-files/files/bin/config_generate

echo "[OK] Build.sh 执行完成"
