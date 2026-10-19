#!/bin/bash
#
# Cudy TR3000 构建脚本（外部软件包 + 设备定制）
#
# 执行时机：
#   FullBuild.yml [3.1]：feeds install 之后、make defconfig 之前，
#                        cd 进源码树后以绝对路径调用（工作目录为源码树根）
#
# 段落约定（顺序即执行顺序）：
#   1) 外部软件包：git clone 到 package/app/，必要时对外部包打补丁
#   2) 设备定制：合并 files/ 用户态文件、改 DTS、内核配置等
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
# 本段在 feeds install 之后执行（[2.6] -> [3.1]），package/feeds/ 下才有
# 可扫的符号链接。
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
# 作用域说明：直接并进 base-files 包，随源码树一起编译。
#
# 路径来源（2026-10-20 修复）：本脚本被 `cd immortalwrt` 后以绝对路径调用，
# 当前目录是源码树而不是设备目录，因此不能用相对路径 Devices/<设备>/files。
# 优先取环境变量 DEVICE_FILES / DEVICE_DIR（由工作流显式传入），否则按
# 「本脚本所在目录就是设备目录」推导。此前只写 ${GITHUB_WORKSPACE}/${DEVICE_DIR}
# 而工作流从未设置 DEVICE_DIR，实际展开成 ${GITHUB_WORKSPACE}//files，导致
# 整个 files/ 段被静默跳过（run 39017537068 实证），默认网络与壁纸都没进固件。
# -----------------------------------------------------------
BUILD_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="${DEVICE_DIR:-$BUILD_SH_DIR}"
DEVICE_FILES="${DEVICE_FILES:-$DEVICE_DIR/files}"

if [ -d "$DEVICE_FILES" ]; then
    BASE_FILES_DIR="$OPENWRT_DIR/package/base-files/files"
    if [ -d "$BASE_FILES_DIR" ]; then
        # 逐项 cp -a：files/ 里只放"整份替换"的文件，不删除上游自带内容
        cp -a "$DEVICE_FILES/." "$BASE_FILES_DIR/"
        echo "[OK] 已合并设备文件到 base-files: $DEVICE_FILES"

        # ---- 生效校验：逐个确认文件真的落在 base-files/files 里 ----
        # 上游 Package/base-files/install 是 `$(CP) ./files/* $(1)/`（已按
        # ImmortalWrt v25.12.2 核实），只要文件在 files/ 下就会进固件。
        # 这里多看一眼，把「复制路径写错但静默继续」变成显式失败。
        missing_files=0
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            if [ -e "$BASE_FILES_DIR/$rel" ]; then
                echo "  [FILE] /$rel"
            else
                echo "[ERROR] 设备文件未落地: $BASE_FILES_DIR/$rel"
                missing_files=1
            fi
        done <<EOF
$(cd "$DEVICE_FILES" && find . -type f | sed 's|^\./||')
EOF
        if [ "$missing_files" -ne 0 ]; then
            echo "[ERROR] 设备文件合并不完整，固件内的默认配置可能缺失"
            exit 1
        fi
    else
        # 源码树结构异常：没有 base-files 时设备文件无处合并，必须显式失败，
        # 否则固件会静默缺少默认配置。
        echo "[ERROR] 未找到 $BASE_FILES_DIR，无法合并设备文件"
        exit 1
    fi
else
    echo "[INFO] 无设备文件目录（$DEVICE_FILES），跳过用户态文件覆盖"
fi

# -----------------------------------------------------------
# 修改设备型号名称
#
# 型号字符串从同目录的 Device.yaml 读取（Model / Model_dts），不再在脚本里
# 重复硬编码：改名时只需改 Device.yaml 一处（Model_dts 为 DTS 里的原始名，
# Model 为目标名）。两个字段缺失或相同则跳过，不做任何替换。
# -----------------------------------------------------------
DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"

DEVICE_CONF="$DEVICE_DIR/Device.yaml"
YAML_MODEL=""
YAML_MODEL_DTS=""
if [ -f "$DEVICE_CONF" ]; then
    # 用 sed 而非 awk：型号带空格，awk '{print $2}' 会被截断
    YAML_MODEL=$(grep '^Model:' "$DEVICE_CONF" | sed 's/^Model: *//' | tr -d '"' | tr -d "'")
    YAML_MODEL_DTS=$(grep '^Model_dts:' "$DEVICE_CONF" | sed 's/^Model_dts: *//' | tr -d '"' | tr -d "'")
fi

if [ -z "$YAML_MODEL_DTS" ] || [ "$YAML_MODEL_DTS" = "$YAML_MODEL" ]; then
    echo "[INFO] Device.yaml 未配置可用的 Model_dts（或与 Model 相同），跳过型号修改"
elif [ ! -f "$DTS_FILE" ]; then
    echo "[WARN] DTS 文件不存在: $DTS_FILE，跳过型号修改"
elif grep -qF "$YAML_MODEL_DTS" "$DTS_FILE"; then
    # 转义 sed 替换对里的元字符，避免型号名中的 . * [ ] \ / & 被当正则
    SED_FROM=$(printf '%s' "$YAML_MODEL_DTS" | sed 's/[][\\.*^$\/&]/\\&/g')
    SED_TO=$(printf '%s' "$YAML_MODEL" | sed 's/[&\/]/\\&/g')
    sed -i "s|$SED_FROM|$SED_TO|g" "$DTS_FILE"
    echo "[OK] 设备型号已修改: $YAML_MODEL_DTS -> $YAML_MODEL"
else
    # DTS 里找不到原始名：多半是上游已经改名，显式告警而不是静默继续
    echo "[WARN] DTS 中未找到 \"$YAML_MODEL_DTS\"，型号未修改: $DTS_FILE"
fi

# -----------------------------------------------------------
# 其他设备定制（按需添加）
# -----------------------------------------------------------
# 默认 lan 口 IP 与网口归属不在这里改：两者都通过 files/etc/uci-defaults/
# 99-cudy-tr3000-defaults 在首次启动时设置，见上方"合并本设备的用户态文件"。

echo "[OK] Build.sh 执行完成"
