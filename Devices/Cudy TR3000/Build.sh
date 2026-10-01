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
#   2) 设备定制：合并 files/ 用户态文件、改 DTS、内核配置等（仅 FullBuild 源码树中生效）
#
# 历史：本文件由原 Packages.sh 与 Customize.sh 合并而来（两段各取其一）。
#

set -e

OPENWRT_DIR="$(pwd)"

# ============================================================
# 1) 外部软件包（版本门控：比 feeds 新才替换，否则用源码自带）
#
# 门控规则（2026-09-28）：
#   - 源码 feeds 没有该包              -> 克隆外部版本
#   - 外部 PKG_VERSION 比 feeds 自带新  -> 删 feeds 链接后克隆替换
#   - 版本相同或外部更旧                -> 不拉取不编译，直接用 feeds 自带
#   - 任一侧版本无法提取                -> 无法证明相同，采用外部版本
# 版本取自包 Makefile 的 PKG_VERSION（去引号与 v 前缀，sort -V 语义比较）。
#
# 本段在 feeds install 之后执行（FullBuild [3.1] / ImageBuilder [IB.2]），
# package/feeds/ 下才有可扫的符号链接；全部走"用自带"时下游直接使用
# feeds 版本，[IB.2] 的差集识别为空即跳过 SDK 编译。
# ============================================================

EXT_TMP_DIR="${TMPDIR:-/tmp}/ext-pkg-src"

# 提取 Makefile 的 PKG_VERSION（归一化：去引号/空白、去 v 前缀）
ext_pkg_version() {
    sed -n 's/^[[:space:]]*PKG_VERSION[[:space:]]*:*=[[:space:]]*//p' "$1" 2>/dev/null \
        | head -1 | tr -d ' "' | sed 's/^[vV]//' | tr -d '[:space:]'
}

# 定位包定义 Makefile（仓库根优先，其次一级子目录里含包定义的）
ext_pkg_makefile() {
    if grep -qE 'BuildPackage|/package\.mk|/luci\.mk' "$1/Makefile" 2>/dev/null; then
        printf '%s\n' "$1/Makefile"
        return 0
    fi
    find "$1" -mindepth 2 -maxdepth 2 -name Makefile -type f 2>/dev/null \
        | while IFS= read -r mk; do
            if grep -qE 'BuildPackage|/package\.mk|/luci\.mk' "$mk" 2>/dev/null; then
                printf '%s\n' "$mk"
                break
            fi
        done
}

# $1 是否比 $2 新（语义化版本比较；相等不算新）
ext_ver_newer() {
    [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] \
        && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]
}

# add_or_keep <feeds 包名> <git URL> <目标目录名>
add_or_keep() {
    local name="$1" url="$2" dest="$3"
    local feed_dir feed_mk feed_ver ext_mk ext_ver clone_dir

    # feeds 自带版本（feeds install 创建的符号链接，目录名即包名）
    feed_ver=""
    feed_dir=$(find "$OPENWRT_DIR/package/feeds" -maxdepth 3 -type l -name "$name" 2>/dev/null | head -1)
    if [ -n "$feed_dir" ]; then
        feed_mk=$(ext_pkg_makefile "$feed_dir")
        if [ -n "$feed_mk" ]; then
            feed_ver=$(ext_pkg_version "$feed_mk")
        fi
    fi

    clone_dir="$EXT_TMP_DIR/$dest"
    rm -rf "$clone_dir"
    if ! git clone --depth 1 "$url" "$clone_dir" >/dev/null 2>&1; then
        echo "[WARN] 克隆失败: $url（保留源码自带: ${feed_ver:-无}）"
        return 0
    fi
    ext_mk=$(ext_pkg_makefile "$clone_dir")
    ext_ver=""
    if [ -n "$ext_mk" ]; then
        ext_ver=$(ext_pkg_version "$ext_mk")
    fi

    if [ -z "$feed_dir" ]; then
        echo "[OK] $name: 源码不自带，采用外部版本 ${ext_ver:-未知}"
    elif [ -z "$feed_ver" ] || [ -z "$ext_ver" ]; then
        echo "[OK] $name: 版本无法比对（自带:${feed_ver:-?} 外部:${ext_ver:-?}），采用外部版本"
    elif ext_ver_newer "$ext_ver" "$feed_ver"; then
        echo "[OK] $name: 外部 $ext_ver 比源码自带 $feed_ver 新，替换"
    else
        echo "[INFO] $name: 外部 $ext_ver 不比源码自带 $feed_ver 新，直接用自带（跳过拉取编译）"
        rm -rf "$clone_dir"
        return 0
    fi

    # 采纳外部版本：删除 feeds 旧符号链接，移入 package/app/
    find "$OPENWRT_DIR/package/feeds/" -name "$name" -exec rm -rf {} + 2>/dev/null || true
    mkdir -p "$OPENWRT_DIR/package/app"
    mv "$clone_dir" "$OPENWRT_DIR/package/app/$dest"
    echo "[OK] 已添加: $dest ($name ${ext_ver:-未知})"
}

mkdir -p "$EXT_TMP_DIR"

# -----------------------------------------------------------
# 各外部包（feeds 有同名包时按版本门控，无则直接克隆）
# -----------------------------------------------------------
add_or_keep luci-theme-argon \
    https://github.com/jerrykuku/luci-theme-argon.git luci-theme-argon

add_or_keep luci-app-argon-config \
    https://github.com/jerrykuku/luci-app-argon-config.git luci-app-argon-config

add_or_keep luci-app-openclash \
    https://github.com/vernesong/OpenClash.git OpenClash

add_or_keep luci-app-harbor-file \
    https://github.com/destan19/luci-app-harbor-file.git luci-app-harbor-file

# -----------------------------------------------------------
# （已移除）OpenAppFilter
#
# 历史：此前在此克隆 OpenAppFilter（luci-app-oaf/appfilter/kmod-oaf）
#       并给 oaf/Makefile 打 KCFLAGS 补丁（修复 6.12 内核的
#       -Wstrict-prototypes 编译错误）。现已按需求移除 luci-app-oaf，
#       克隆与补丁一并删除。
# -----------------------------------------------------------

# ============================================================
# 2) 设备定制（用户态文件覆盖、DTS、内核配置等）
# ============================================================

# -----------------------------------------------------------
# 合并本设备的用户态文件（files/）
#
# 目录约定：Devices/<设备名>/files/ 的内容与固件根目录一一对应
#   files/www/luci-static/argon/img/bg1.jpg  ->  /www/luci-static/argon/img/bg1.jpg
#   files/etc/uci-defaults/99-xxx            ->  /etc/uci-defaults/99-xxx
#
# FullBuild 没有 FILES= 机制，只能把文件并进源码树的 base-files 包；
# base-files 的 Package/install 用 `cp ./files/* $(1)/` 收集，因此放在这里
# 与上游自带文件同等生效（已按 ImmortalWrt v25.12.2 的
# package/base-files/Makefile 核实）。
#
# 作用域说明：只影响跟随源码树构建的 base-files（FullBuild）。
# ImageBuilder 不重编 base-files，它走工作流 [IB.3] 的 FILES= 机制读同一个
# files/ 目录，两条路径的最终内容一致。
# -----------------------------------------------------------
DEVICE_FILES="${DEVICE_FILES:-${GITHUB_WORKSPACE}/${DEVICE_DIR}/files}"

if [ -d "$DEVICE_FILES" ]; then
    BASE_FILES_DIR="$OPENWRT_DIR/package/base-files/files"
    if [ -d "$BASE_FILES_DIR" ]; then
        # 逐项 cp -a：files/ 里只放"整份替换"的文件，不删除上游自带内容
        cp -a "$DEVICE_FILES/." "$BASE_FILES_DIR/"
        echo "[OK] 已合并设备文件到 base-files: $DEVICE_FILES"
        find "$DEVICE_FILES" -type f | sed "s|^$DEVICE_FILES/|  [FILE] /|"
    else
        echo "[WARN] 未找到 $BASE_FILES_DIR，跳过设备文件合并"
    fi
else
    echo "[INFO] 无设备文件目录（$DEVICE_FILES），跳过用户态文件覆盖"
fi

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
# 默认 lan 口 IP 与网口归属不在这里改：两者都通过 files/etc/uci-defaults/
# 99-cudy-tr3000-defaults 在首次启动时设置（FullBuild 与 ImageBuilder 一致），
# 见上方"合并本设备的用户态文件"。

echo "[OK] Build.sh 执行完成"
