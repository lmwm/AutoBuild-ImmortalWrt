#!/bin/bash
#
# Cudy TR3000 构建脚本：外部软件包 + 设备定制
# 由 FullBuild.yml [3.1] 在 feeds install 之后、cd 进源码树后以绝对路径调用。
#

set -e

OPENWRT_DIR="$(pwd)"

# 1) 外部软件包：feeds 无此包则克隆；外部 PKG_VERSION 更新才删链接替换，否则用自带。

EXT_TMP_DIR="${TMPDIR:-/tmp}/ext-pkg-src"

# 取 Makefile 的 PKG_VERSION（去引号、空白与 v 前缀）
ext_pkg_version() {
    sed -n 's/^[[:space:]]*PKG_VERSION[[:space:]]*:*=[[:space:]]*//p' "$1" 2>/dev/null \
        | head -1 | tr -d ' "' | sed 's/^[vV]//' | tr -d '[:space:]'
}

# 定位包定义 Makefile：优先仓库根，其次一级子目录
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

# $1 是否比 $2 新（相等不算新）
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

    # 采用外部版本：删掉 feeds 旧链接，移入 package/app/
    find "$OPENWRT_DIR/package/feeds/" -name "$name" -exec rm -rf {} + 2>/dev/null || true
    mkdir -p "$OPENWRT_DIR/package/app"
    mv "$clone_dir" "$OPENWRT_DIR/package/app/$dest"
    echo "[OK] 已添加: $dest ($name ${ext_ver:-未知})"
}

mkdir -p "$EXT_TMP_DIR"

# 各外部包
add_or_keep luci-theme-argon \
    https://github.com/jerrykuku/luci-theme-argon.git luci-theme-argon

add_or_keep luci-app-argon-config \
    https://github.com/jerrykuku/luci-app-argon-config.git luci-app-argon-config

add_or_keep luci-app-openclash \
    https://github.com/vernesong/OpenClash.git OpenClash

add_or_keep luci-app-harbor-file \
    https://github.com/destan19/luci-app-harbor-file.git luci-app-harbor-file

# OpenAppFilter（luci-app-oaf）已移除，克隆与 KCFLAGS 补丁一并删除；见 README。

# 2) 设备定制
# files/ 与固件根目录一一对应，合并进 base-files（其 Package/install 会 cp ./files/*），
# 随源码树一起编译。执行时工作目录是源码树，故按脚本位置推导设备目录，
# 并允许 DEVICE_DIR / DEVICE_FILES 覆盖；合并后逐项校验，缺失即失败。
BUILD_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="${DEVICE_DIR:-$BUILD_SH_DIR}"
DEVICE_FILES="${DEVICE_FILES:-$DEVICE_DIR/files}"

if [ -d "$DEVICE_FILES" ]; then
    BASE_FILES_DIR="$OPENWRT_DIR/package/base-files/files"
    if [ -d "$BASE_FILES_DIR" ]; then
        # 逐项复制：files/ 只做整份替换，不删除上游自带内容
        cp -a "$DEVICE_FILES/." "$BASE_FILES_DIR/"
        echo "[OK] 已合并设备文件到 base-files: $DEVICE_FILES"

        # 校验文件真的落进 base-files/files，避免路径写错时静默继续
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
        # 源码树结构异常：没有 base-files 时无处合并，显式失败
        echo "[ERROR] 未找到 $BASE_FILES_DIR，无法合并设备文件"
        exit 1
    fi
else
    echo "[INFO] 无设备文件目录（$DEVICE_FILES），跳过用户态文件覆盖"
fi

# 修改设备型号：读 Device.yaml 的 Model_dts（DTS 原始名）-> Model（目标名）；
# 字段缺失/相同或 DTS 未找到原始名时跳过并提示。
DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"

DEVICE_CONF="$DEVICE_DIR/Device.yaml"
YAML_MODEL=""
YAML_MODEL_DTS=""
if [ -f "$DEVICE_CONF" ]; then
    # 型号可能带空格，用 sed 而非 awk
    YAML_MODEL=$(grep '^Model:' "$DEVICE_CONF" | sed 's/^Model: *//' | tr -d '"' | tr -d "'")
    YAML_MODEL_DTS=$(grep '^Model_dts:' "$DEVICE_CONF" | sed 's/^Model_dts: *//' | tr -d '"' | tr -d "'")
fi

if [ -z "$YAML_MODEL_DTS" ] || [ "$YAML_MODEL_DTS" = "$YAML_MODEL" ]; then
    echo "[INFO] Device.yaml 未配置可用的 Model_dts（或与 Model 相同），跳过型号修改"
elif [ ! -f "$DTS_FILE" ]; then
    echo "[WARN] DTS 文件不存在: $DTS_FILE，跳过型号修改"
elif grep -qF "$YAML_MODEL_DTS" "$DTS_FILE"; then
    # 替换前转义 sed 元字符，避免型号名中的 . * [ ] \ / & 被当正则
    SED_FROM=$(printf '%s' "$YAML_MODEL_DTS" | sed 's/[][\\.*^$\/&]/\\&/g')
    SED_TO=$(printf '%s' "$YAML_MODEL" | sed 's/[&\/]/\\&/g')
    sed -i "s|$SED_FROM|$SED_TO|g" "$DTS_FILE"
    echo "[OK] 设备型号已修改: $YAML_MODEL_DTS -> $YAML_MODEL"
else
    # 多半是上游已改名：显式告警，不静默继续
    echo "[WARN] DTS 中未找到 \"$YAML_MODEL_DTS\"，型号未修改: $DTS_FILE"
fi

# 其他定制按需添加；默认 lan 地址与网口归属见 files/etc/uci-defaults/99-cudy-tr3000-defaults。

echo "[OK] Build.sh 执行完成"
