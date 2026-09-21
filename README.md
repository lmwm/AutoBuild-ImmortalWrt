# AutoBuild ImmortalWrt

使用 GitHub Actions 自动编译 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 固件

- 仓库：`lmwm/AutoBuild-ImmortalWrt`
- 编译工作流：**编译 ImmortalWrt 固件**（`AutoBuild.yml`）
- 标签同步工作流：**同步版本标签**（`SyncVersions.yml`）

## 项目结构

```
.
├── .github/workflows/
│   ├── AutoBuild.yml          # 编译工作流
│   └── SyncVersions.yml       # 版本标签同步工作流（定期维护下拉选项）
├── Devices/                   # 设备目录（每个设备一个文件夹）
│   └── Cudy TR3000/           # 目录名与 device 下拉选项值完全一致（含空格）
│       ├── Device.yaml        # 设备参数（型号、TARGET）
│       ├── Packages.yaml      # 软件包配置（启用/禁用）
│       ├── Packages.sh        # 自定义软件包脚本（克隆外部仓库）
│       └── Customize.sh       # 设备定制脚本（修改 DTS 等）
├── README.md
└── .gitignore
```

## 使用方法

1. Fork 本仓库（首次使用建议先手动跑一次 **同步版本标签**，把版本列表补全）
2. 进入 **Actions** -> **编译 ImmortalWrt 固件**
3. 从下拉列表选择设备与版本 -> 点击 **Run workflow**
4. 等待编译完成（首次约 2-4 小时，命中缓存后显著缩短）
5. 在 Actions 页面 **Artifacts** 下载固件

## 工作流参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `device` | 目标设备（下拉选择，值与 `Devices/<名>` 目录名一致） | `Cudy TR3000` |
| `tag` | ImmortalWrt 版本标签（下拉选择） | `latest` |
| `cache_enabled` | 启用编译缓存（ccache + 源码下载 dl） | `true` |
| `skip_compile` | 跳过编译（调试模式） | `false` |

### 版本标签（下拉选择，自动同步）

**全部参数都是下拉选择，不需要手动输入任何内容**，因此不会输错版本号。

实现方式说明：GitHub Actions 的 `workflow_dispatch` 下拉选项（`type: choice`）**必须静态写在工作流文件里**，官方不支持运行时动态生成。所以本仓库用 `SyncVersions.yml` 这个定时工作流来维护列表：

| 项目 | 说明 |
|------|------|
| 运行时机 | 每周一 03:00 UTC 自动运行，也可手动触发 |
| 行为 | 从上游拉取全部正式标签（排除 `-rc` 等预发布），取最新 8 个写入 `AutoBuild.yml` 的 `tag.options` |
| 提交 | 仅在有变化时提交，提交信息为 `配置: 同步 ImmortalWrt 版本标签` |
| 无变化 | 不产生任何提交 |

因此上游发布新版本后，下拉列表会在下一周自动更新，无需人工维护。

编译工作流仍会做双重保险：`[2.2]` 实时拉取并打印上游全部可用标签，`[2.3]` 校验所选标签确实存在，不存在则报错并列出可用标签。

> 若发现下拉列表长期未更新：GitHub 对长期无活动的仓库会停用定时工作流，手动触发一次 **同步版本标签** 即可恢复。

### 编译缓存（可选）

`cache_enabled` 控制两类相互独立的缓存，默认开启：

| 缓存 | 路径 | 作用 |
|------|------|------|
| ccache | `immortalwrt/.ccache` | 缓存 C/C++ 编译产物，同版本重复编译大幅提速 |
| dl | `immortalwrt/dl` | 缓存源码包，避免重复下载，降低上游下载失败风险 |

- ccache 按 `系统-平台-版本` 分键，同平台同版本精确命中；跨版本保留 `restore-keys`，因为 ccache 用源码与命令行哈希校验，版本不符只会失效、不会用错
- dl 按 `系统-平台-版本` 分键且**不跨版本复用**：dl 里是未校验的压缩包，跨版本混用可能导致某个包源码与目标版本不匹配而报校验失败。代价是每个版本各存一份
- 两个缓存都带平台维度，将来新增不同平台的设备时不会互相污染
- GitHub 单个缓存上限 10GB，dl 目录通常在数 GB 级；若提示超限，编译不受影响，仅本次不保存 dl 缓存
- 启用缓存时会在 `.config` 写入 `CONFIG_DEVEL=y` + `CONFIG_CCACHE=y`（`CONFIG_CCACHE` 的可见性依赖 `CONFIG_DEVEL`），缓存目录沿用 OpenWrt 默认的 `$(TOPDIR)/.ccache`
- 编译结束后 `[4.2]` 会打印 ccache 命中统计与缓存体积，据此判断缓存是否真的生效
- 关闭该开关则每次都从零编译，用于排查缓存引入的疑难问题

## 编译流程

```
阶段 1: 系统环境初始化
  [1.1] 系统信息
  [1.2] 克隆配置仓库
  [1.3] 加载设备配置

阶段 2: 源码准备
  [2.1] 安装编译环境
  [2.2] 获取版本标签（实时）
  [2.3] 确定版本标签（解析 + 校验）
  [2.4] 克隆 ImmortalWrt 源码
  [2.5] 更新 feeds
  [2.6] 安装 feeds

阶段 3: 自定义固件
  [3.1] 添加自定义软件包（Packages.sh）
  [3.2] 设备定制（Customize.sh）
  [3.3] 生成编译配置（Packages.yaml）
  [3.4] 恢复 ccache 缓存（可选）
  [3.5] 恢复源码下载缓存（可选）
  [3.6] 同步配置（make defconfig）
  [3.7] 修复 Rust LLVM

阶段 4: 编译固件
  [4.1] 预下载资源
  [4.2] 编译固件（多线程 -> 单线程 -> 详细日志三级重试）
  [4.3] 编译后磁盘使用

阶段 5: 上传固件
  [5.1] 整理固件（重命名 + 定位编译产物目录）
  [5.2] 上传 sysupgrade 固件
  [5.3] 上传 recovery/factory 固件
  [5.4] 上传配置文件
  [5.5] 上传完整编译产物（产物目录内全部文件）
```

## 配置文件说明

### Device.yaml

设备配置文件，定义设备的基本参数（键名首字母大写）：

```yaml
# 设备型号（用于固件命名与 Artifact 命名）
Model: "Cudy TR3000"

# 自定义软件包列表文件
Packages_list: "Packages.yaml"

# 设备 TARGET（用于 make defconfig）
Target: "CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-v1-ubootmod=y"
```

### Packages.yaml

软件包配置文件，管理启用和禁用的包：

```yaml
# 启用的包
enable:
  - luci-i18n-base-zh-cn
  - luci-theme-argon
  - luci-app-mwan3
  - luci-app-ttyd
  - luci-app-openclash
  - luci-app-oaf
  - kmod-mtd-rw
  - kmod-usb-net-rndis
  - usbutils

# 禁用的包（本体）
disable:
  - luci-app-passwall
  - luci-app-rclone

# 禁用的子组件
disable_components:
  luci-app-passwall:
    - INCLUDE_Haproxy
    - INCLUDE_SingBox
    - INCLUDE_Xray
```

> `usbutils` 提供 `lsusb` 命令，用于查看 USB 设备信息（调试 USB 网卡/RNDIS 时常用）。

### Packages.sh

克隆外部仓库的脚本（从 GitHub 获取最新版本），并对外部包打必要补丁：

```bash
#!/bin/bash
set -e

OPENWRT_DIR="$(pwd)"

# 删除 feeds 旧版本，克隆到 package/app/
find "$OPENWRT_DIR/package/feeds/" -name "luci-app-openclash" -exec rm -rf {} + 2>/dev/null
git clone --depth 1 https://github.com/vernesong/OpenClash.git \
    "$OPENWRT_DIR/package/app/OpenClash"
echo "[OK] 已添加: OpenClash"
```

#### OpenAppFilter 内核模块补丁

`Packages.sh` 除了克隆 [OpenAppFilter](https://github.com/destan19/OpenAppFilter)，还会修补其 `oaf/Makefile`。

该仓库提供三个包，三者都启用才能工作：

| 包 | 作用 | 依赖 |
|----|------|------|
| `luci-app-oaf` | LuCI 界面 | `appfilter` + `kmod-oaf` |
| `appfilter` | `oafd` 用户态服务程序 | `libubox`、`libuci`、`libjson-c` 等 |
| `kmod-oaf` | oaf 内核模块 | `kmod-ipt-conntrack` |

因此 `Packages.yaml` 中只需写 `luci-app-oaf`，`make defconfig` 会自动通过依赖链选中另外两个。

**为什么需要补丁**：OpenWrt/ImmortalWrt 25.12 起内核为 6.12，编译时把 `-Wstrict-prototypes` 等告警视为错误，而 `oaf/src/k_json.c` 存在大量 `cJSON *func()` 形式的无原型声明，编译时直接报错：

```
error: a function declaration without a prototype is deprecated
       in all versions of C [-Werror,-Wstrict-prototypes]
```

这会导致 `kmod-oaf` 编译失败，进而出现 `kmod-oaf (no such package)` 的依赖报错（上游 issue #378，截至 master 仍存在）。

补丁用 awk 找到 `Build/Compile` 中 `KCFLAGS="$(KCFLAGS)"` 赋值行，在引号闭合前插入降级选项：

```makefile
KCFLAGS="$(KCFLAGS) -Wno-error=strict-prototypes"
```

注意：`$(MAKE)` 和 `KCFLAGS=` 在 Makefile 中是**不同行**（`KCFLAGS` 是续行），不能用 `$(MAKE).*KCFLAGS` 模式匹配。补丁带有幂等检查与生效校验，未生效则直接报错退出。

> 注意：这仅是**编译期**修复。上游该模块在新内核上另有运行时风险（issue #372：6.12 内核下 `memcpy` 缓冲区溢出可触发内核 panic），是否长期启用请自行评估。

### Customize.sh

设备定制脚本（修改 DTS、内核配置等）：

```bash
#!/bin/bash
set -e

# 修改设备型号名称
DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"
if [ -f "$DTS_FILE" ]; then
    sed -i 's/Cudy TR3000 v1 (OpenWrt U-Boot layout)/Cudy TR3000/g' "$DTS_FILE"
fi
```

## 添加新设备

以 `NanoPi R4S` 为例：

### 1. 创建设备目录

目录名**与下拉选项值完全一致（保留空格）**：

```bash
mkdir -p "Devices/NanoPi R4S"
```

工作流直接用 `device` 下拉值拼路径（`Devices/${DEVICE}`），所以目录名必须与选项值一字不差（含空格）。新增设备时保持一致即可，无需额外注册。

### 2. 创建 Device.yaml

```yaml
Model: "NanoPi R4S"
Packages_list: "Packages.yaml"
Target: "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s=y"
```

### 3. 创建 Packages.yaml

```yaml
enable:
  - luci-i18n-base-zh-cn
  - luci-app-mwan3
  - luci-app-ttyd

disable:
  - luci-app-passwall
```

### 4. 编写 Packages.sh（可选）

```bash
#!/bin/bash
set -e
OPENWRT_DIR="$(pwd)"

git clone --depth 1 https://github.com/vernesong/OpenClash.git \
    "$OPENWRT_DIR/package/app/OpenClash"
```

### 5. 编写 Customize.sh（可选）

```bash
#!/bin/bash
set -e

DTS_FILE="target/linux/rockchip/dts/rk3399-nanopi-r4s.dts"
if [ -f "$DTS_FILE" ]; then
    sed -i 's/FriendlyARM NanoPi R4S/NanoPi R4S/g' "$DTS_FILE"
fi
```

### 6. 注册设备

编辑 `.github/workflows/AutoBuild.yml`，在 `device` 的 `options` 中添加：

```yaml
device:
  type: choice
  options:
    - "Cudy TR3000"
    - "NanoPi R4S"
```

## 已支持设备

| 设备 | TARGET | 状态 |
|------|--------|------|
| Cudy TR3000 | `CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-v1-ubootmod=y` | 支持 |

## 输出文件

编译完成后会上传 4 个 Artifact。Artifact 名称把设备型号中的**空格去掉**（如 `CudyTR3000`），避免下载的 zip 文件名带空格；下载后的压缩包名即 `<Artifact 名称>.zip`。

| Artifact | 下载后文件名 | 内容 |
|----------|--------------|------|
| `...-sysupgrade` | `ImmortalWrt-CudyTR3000-v25.12.1-sysupgrade.zip` | 系统升级固件（匹配 `*sysupgrade*`） |
| `...-recovery` | `ImmortalWrt-CudyTR3000-v25.12.1-recovery.zip` | 恢复/工厂固件（匹配 `*recovery*`、`*factory*`），无此产物时跳过 |
| `...-config` | `ImmortalWrt-CudyTR3000-v25.12.1-config.zip` | 编译配置，文件名为 `设备型号-ImmortalWrt-V版本-构建号-config-日期.config` |
| `...-full` | `ImmortalWrt-CudyTR3000-v25.12.1-full.zip` | **完整编译产物**（见下） |

其中 `-full` 上传的是编译产物目录（`bin/targets/<平台>/`）内的**全部文件**，而不是单独的几个固件，包含：

- 固件镜像（含本设备与同平台其他设备的镜像）
- 内核与设备树（`*Image`、`*.dtb`）
- `profiles.json`、`sha256sums`、`*.manifest`
- `packages/` 下编译出的全部 `.apk` 安装包

该步骤显式启用了 `include-hidden-files`（隐藏文件默认不上传）。此参数需要 `actions/upload-artifact` v4.4.0+，`@v4` 已满足；若日志报 `Unexpected input(s) 'include-hidden-files'`，说明所用 v4 版本过旧。

已重命名的固件统一格式为 `设备型号-ImmortalWrt-V版本-构建号-类型-日期.扩展名`，例如
`Cudy TR3000-ImmortalWrt-V25.12.1-r1234-abcd123-squashfs-sysupgrade-20260101.itb`。

设备型号保留原有空格（如 `Cudy TR3000`）；仅在 Artifact 名称中去掉空格（`CudyTR3000`），避免下载的 zip 文件名带空格。

支持的固件格式：`.itb`、`.bin`、`.img.gz`、`.squashfs`

## 许可证

本项目为个人配置仓库，未单独声明开源许可证；所编译的 ImmortalWrt 源码遵循其上游许可证。
