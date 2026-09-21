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
# 三者都启用才能工作，Packages.yaml 中只写 luci-app-oaf 即可，
# make defconfig 会通过依赖关系自动选中 appfilter 与 kmod-oaf。
# -----------------------------------------------------------
find "$OPENWRT_DIR/package/feeds/" -name "luci-app-oaf" -exec rm -rf {} + 2>/dev/null
git clone --depth 1 https://github.com/destan19/OpenAppFilter.git \
    "$OPENWRT_DIR/package/app/OpenAppFilter"
echo "[OK] 已添加: OpenAppFilter (luci-app-oaf)"

# -----------------------------------------------------------
# OpenAppFilter 内核模块补丁
#
# 背景：OpenWrt/ImmortalWrt 25.12 起内核为 6.12，编译时把
#       -Wstrict-prototypes 等告警视为错误，而 oaf/src/k_json.c 存在大量
#       `cJSON *func()` 形式的无原型声明，编译时直接报错：
#         error: a function declaration without a prototype is deprecated
#                in all versions of C [-Werror,-Wstrict-prototypes]
#       导致 kmod-oaf 编译失败，进而出现 "kmod-oaf (no such package)"
#       的依赖报错（上游 issue #378，截至 master 仍存在）。
#
# 修复：在 Build/Compile 的 $(MAKE) 命令行末尾追加
#       KCFLAGS="$(KCFLAGS) -Wno-error=strict-prototypes"，确保编译器
#       收到该降级选项。
#
# 重要：必须追加到 $(MAKE) 行而非 Makefile 末尾。$(MAKE) 行从不引用
#       末尾追加的 KCFLAGS +=（它只用块内已有的 $(KCFLAGS)），末尾追加
#       实际上不起作用（前版写法）。
#
# 注意：这是编译期修复。上游该模块在新内核上另有运行时风险
#       （issue #372：6.12 内核下 memcpy 缓冲区溢出触发内核 panic），
#       是否长期启用请自行评估。
# -----------------------------------------------------------
OAF_MAKEFILE="$OPENWRT_DIR/package/app/OpenAppFilter/oaf/Makefile"
if [ -f "$OAF_MAKEFILE" ]; then
    # 检查是否已修补：$(MAKE) 行是否已含降级选项
    if grep -q '\$(MAKE)' "$OAF_MAKEFILE" && \
       sed -n '/\$(MAKE)/p' "$OAF_MAKEFILE" | grep -q 'Wno-error=strict-prototypes'; then
        echo "[OK] oaf 内核模块补丁已存在（在 \$(MAKE) 行），跳过"
    else
        # 旧版遗留：删除无效的末尾追加行（补丁未放到正确位置）
        if grep -q '^KCFLAGS +=' "$OAF_MAKEFILE"; then
            sed -i '/^KCFLAGS +=.*Wno-error=strict-prototypes/d' "$OAF_MAKEFILE"
            echo "[INFO] 清理旧版末尾追加行"
        fi

        # 新补丁：追加到 $(MAKE) 行末尾（确保编译时生效）
        sed -i '/\$(MAKE).*KCFLAGS/{s|$| -Wno-error=strict-prototypes|}' "$OAF_MAKEFILE"

        if grep -q '\$(MAKE)' "$OAF_MAKEFILE" && \
           sed -n '/\$(MAKE)/p' "$OAF_MAKEFILE" | grep -q 'Wno-error=strict-prototypes'; then
            echo "[OK] 已修补 oaf 内核模块: 在 \$(MAKE) 行追加 -Wno-error=strict-prototypes"
            grep '\$(MAKE)' "$OAF_MAKEFILE"
        else
            echo "[ERROR] oaf 内核模块补丁未生效，kmod-oaf 将编译失败"
            echo "        请检查 $OAF_MAKEFILE"
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
