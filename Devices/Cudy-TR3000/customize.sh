#!/bin/bash
#
# Cudy TR3000 设备定制脚本
# 在 packages.sh 和 generate-config 之后执行
#
# 功能：修改设备特定设置（DTS、内核配置等）
#

set -e

OPENWRT_DIR="$(pwd)"

# ============================================================
# 修改设备型号名称
# ============================================================
DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"

if [ -f "$DTS_FILE" ]; then
    sed -i 's/Cudy TR3000 v1 (OpenWrt U-Boot layout)/Cudy TR3000/g' "$DTS_FILE"
    echo "[OK] 设备型号已修改: Cudy TR3000 v1 (OpenWrt U-Boot layout) -> Cudy TR3000"
else
    echo "[WARN] DTS 文件不存在: $DTS_FILE，跳过型号修改"
fi

# ============================================================
# 其他设备定制（按需添加）
# ============================================================
# 示例：修改默认 IP
# sed -i 's/192.168.1.1/192.168.50.1/g' package/base-files/files/bin/config_generate

echo "[OK] 设备定制完成"
