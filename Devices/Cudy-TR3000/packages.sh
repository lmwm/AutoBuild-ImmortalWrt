#!/bin/bash
#
# Cudy TR3000 自定义软件包
# 此脚本在 feeds install 之后、make defconfig 之前执行
#
# 用法：在 immortalwrt 源码根目录下执行
#

set -e

OPENWRT_DIR="$(pwd)"

# -----------------------------------------------------------
# luci-theme-argon (最新版)
# 删除 feeds 旧版本，克隆到 package/app/
# -----------------------------------------------------------
find "$OPENWRT_DIR/package/feeds/" -name "luci-theme-argon" -exec rm -rf {} + 2>/dev/null
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git \
    "$OPENWRT_DIR/package/app/luci-theme-argon"
echo "[OK] 已添加: luci-theme-argon"

# -----------------------------------------------------------
# luci-app-argon-config (配套)
# 删除 feeds 旧版本，克隆到 package/app/
# -----------------------------------------------------------
find "$OPENWRT_DIR/package/feeds/" -name "luci-app-argon-config" -exec rm -rf {} + 2>/dev/null
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git \
    "$OPENWRT_DIR/package/app/luci-app-argon-config"
echo "[OK] 已添加: luci-app-argon-config"

# -----------------------------------------------------------
# OpenClash
# 删除 feeds 旧版本，克隆到 package/app/
# -----------------------------------------------------------
find "$OPENWRT_DIR/package/feeds/" -name "luci-app-openclash" -exec rm -rf {} + 2>/dev/null
git clone --depth 1 https://github.com/vernesong/OpenClash.git \
    "$OPENWRT_DIR/package/app/OpenClash"
echo "[OK] 已添加: OpenClash (luci-app-openclash)"

# -----------------------------------------------------------
# OpenAppFilter
# 删除 feeds 旧版本，克隆到 package/app/
#
# 该仓库提供三个包：
#   luci-app-oaf  -> LuCI 界面（依赖 appfilter + kmod-oaf）
#   appfilter     -> oafd 用户态服务程序
#   kmod-oaf      -> oaf 内核模块（Netfilter 扩展，依赖 kmod-ipt-conntrack）
# 三者都启用才能工作，packages.yaml 中只写 luci-app-oaf 即可，
# make defconfig 会通过依赖关系自动选中 appfilter 与 kmod-oaf。
# -----------------------------------------------------------
find "$OPENWRT_DIR/package/feeds/" -name "luci-app-oaf" -exec rm -rf {} + 2>/dev/null
git clone --depth 1 https://github.com/destan19/OpenAppFilter.git \
    "$OPENWRT_DIR/package/app/OpenAppFilter"
echo "[OK] 已添加: OpenAppFilter (luci-app-oaf)"

# -----------------------------------------------------------
# OpenAppFilter 内核模块补丁
#
# 背景：OpenWrt/ImmortalWrt 25.12 起内核为 6.12，使用 clang 编译并把
#       -Wstrict-prototypes 等告警视为错误，而 oaf/src/k_json.c 存在大量
#       `cJSON *func()` 形式的无原型声明，会在编译时直接报错：
#         error: a function declaration without a prototype is deprecated
#                in all versions of C [-Werror,-Wstrict-prototypes]
#       导致 kmod-oaf 编译失败，进而出现 "kmod-oaf (no such package)"
#       的依赖报错（上游 issue #378，截至 master 仍存在）。
#
# 修复：在 oaf/Makefile 末尾追加 KCFLAGS 降级选项。该 Makefile 已降级
#       missing-prototypes、format 等同类告警，此处保持一致做法。
#       使用 += 追加而不是改写原行，避免 sed 多行替换的转义风险。
#
# 注意：这是编译期修复。上游该模块在新内核上另有运行时风险
#       （issue #372：6.12 内核下 memcpy 缓冲区溢出触发内核 panic），
#       是否长期启用请自行评估。
# -----------------------------------------------------------
OAF_MAKEFILE="$OPENWRT_DIR/package/app/OpenAppFilter/oaf/Makefile"
if [ -f "$OAF_MAKEFILE" ]; then
    if grep -q 'Wno-error=strict-prototypes' "$OAF_MAKEFILE"; then
        echo "[OK] oaf 内核模块补丁已存在，跳过"
    else
        printf '\n# 由 packages.sh 追加：降级 6.12 内核 clang 下的 -Wstrict-prototypes\nKCFLAGS += -Wno-error=strict-prototypes\n' >> "$OAF_MAKEFILE"
        if grep -q 'Wno-error=strict-prototypes' "$OAF_MAKEFILE"; then
            echo "[OK] 已修补 oaf 内核模块: 补充 -Wno-error=strict-prototypes"
            tail -3 "$OAF_MAKEFILE"
        else
            echo "[ERROR] oaf 内核模块补丁未生效，kmod-oaf 将编译失败: $OAF_MAKEFILE"
            exit 1
        fi
    fi
else
    echo "[ERROR] 未找到 oaf Makefile，无法修复 kmod-oaf: $OAF_MAKEFILE"
    exit 1
fi

# -----------------------------------------------------------
# luci-app-harbor-file
# 克隆到 package/app/
# -----------------------------------------------------------
git clone --depth 1 https://github.com/destan19/luci-app-harbor-file.git \
    "$OPENWRT_DIR/package/app/luci-app-harbor-file"
echo "[OK] 已添加: luci-app-harbor-file"
