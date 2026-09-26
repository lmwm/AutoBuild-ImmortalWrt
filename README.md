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
4. 等待编译完成（`full` 模式约 2-3 小时；`imagebuilder` 模式约 10-15 分钟）
5. 在 Actions 页面 **Artifacts** 下载固件

## 工作流参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `device` | 目标设备（下拉选择，值与 `Devices/<名>` 目录名一致） | `Cudy TR3000` |
| `tag` | ImmortalWrt 版本标签（下拉选择） | `latest` |
| `cache_enabled` | 启用编译缓存（ccache + 源码下载 dl） | `true` |
| `skip_compile` | 跳过编译（调试模式） | `false` |
| `build_mode` | 构建方式：`full`=全量编译（可改内核/DTS）；`imagebuilder`=官方 ImageBuilder 快速组装 | `full` |
| `ruby_yjit` | 启用 ruby YJIT（仅 `full` 模式有效；关闭可甩掉整个 Rust/LLVM 工具链，省 60–130 分钟） | `true` |

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
| ccache | `immortalwrt/.ccache` | 缓存 C/C++ 编译产物，重复编译同一版本可大幅提速 |
| dl | `immortalwrt/dl` | 缓存源码包，避免重复下载，降低上游下载失败风险 |

- **已不再缓存构建树**（`build_dir` + `staging_dir`）。此前那份缓存单独就有 **10.24GB**，超出 GitHub 每仓库 10GB 的配额，会把 ccache 与 dl 一起挤掉；保存一次要 6.5 分钟；而且其配套的 `[5.6]` 裁剪用 `-name 'core.*'` 误删了内核源码里的 `core.h`（`include/net/netns/core.h`），使下一次 `full` 编译恢复该缓存后**必然报错失败**。因此构建树缓存连同配套的 `[2.7]` 时间戳重置、`[5.6]` 裁剪、`[5.7]` 保存一并移除
- **`full` 模式现在是纯全量编译**：每次从零编译，不再有「增量命中后 15-30 分钟」这一档。加速完全由 ccache 承担——它按 `系统-平台-版本-compiler_check 版本`（当前末尾为 `-cc2`）分键，同平台同版本精确命中；跨版本保留 `restore-keys`，因为 ccache 用源码与命令行哈希校验，版本不符只会失效、不会用错
- **实测基线**（v25.12.2）：首次全量约 2 小时 51 分，其中 `feeds/packages/lang/ruby`（OpenClash 依赖）独占约 106 分钟——**这类不走 ccache 的巨包无法被 ccache 加速**，是 `full` 模式的主要耗时来源。想缩短 `full` 耗时请用 `ruby_yjit=false`（见下文），需要分钟级出固件请改用 `imagebuilder`
- dl 按 `系统-平台-版本` 分键且**不跨版本复用**：dl 里是未校验的压缩包，跨版本混用可能导致某个包源码与目标版本不匹配而报校验失败。代价是每个版本各存一份
- 两个缓存都带平台维度，将来新增不同平台的设备时不会互相污染
- GitHub 单个缓存上限 10GB（所有缓存条目共享，超出按 LRU 淘汰）；若提示超限，编译不受影响，仅本次不保存对应缓存。`[4.3]` 会打印各构建目录的精确体积
- 启用缓存时会在 `.config` 写入 `CONFIG_DEVEL=y` + `CONFIG_CCACHE=y`（`CONFIG_CCACHE` 的可见性依赖 `CONFIG_DEVEL`），缓存目录沿用 OpenWrt 默认的 `$(TOPDIR)/.ccache`
- **ccache 的编译器校验方式必须显式指定**：ccache 默认以「编译器二进制的 mtime + size」校验，而本工作流每次运行都会重新编译交叉工具链，mtime 必然变化，恢复回来的缓存对 target 侧会全部失效——表现为缓存显示已命中、编译时间却几乎不变。因此 `[3.5.1]` 会在缓存恢复之后写入 `immortalwrt/.ccache/ccache.conf`：

  ```ini
  compiler_check = content
  depend_mode = true
  sloppiness = file_macro,locale,time_macros,include_file_ctime,include_file_mtime
  max_size = 5G
  ```

  上游依据：openwrt/openwrt 提交 `39562875`（`build: do not set CCACHE_COMPILERCHECK`）指出 CI 必须额外写 `compiler_check`，因为 "compiler mtimes would not match after restoring a cache archive"。以上判断已按 **ImmortalWrt v25.12.2** 源码核实：其 `rules.mk` 同样不设置 `CCACHE_COMPILERCHECK`、`CCACHE_DIR` 同样默认回落到 `$(TOPDIR)/.ccache`，打包的 ccache 为 4.12.1。另注意官方 CI 的 `compiler_type=gcc` **不可照搬**——ImmortalWrt 25.12 起内核使用 clang 编译，本工作流交给 ccache 自动识别编译器类型
- `[3.5.1]` 必须排在 `[3.4]` 之后，否则写好的配置会被恢复出来的缓存覆盖；该改动生效后的**第一次**编译仍是全量（旧缓存条目因校验方式变化而失效），从第二次同版本编译开始才体现加速
- 编译结束后 `[4.2]` 打印 ccache 统计，用的是 OpenWrt 自编译的 `staging_dir/host/bin/ccache`（版本与写入缓存者一致，v25.12.2 为 4.12.1）并显式指定 `CCACHE_DIR`。系统自带的 `ccache -s` 会去读空的 `~/.ccache`，永远显示 `0.00%`，不能用来判断命中率
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
  [3.5.1] 配置 ccache 校验方式（可选）
  [3.5.2] 配置 ruby YJIT（ruby_yjit=false 时禁用，甩掉 Rust 工具链）
  [3.6] 同步配置（make defconfig）
  [3.7] 修复 Rust LLVM

阶段 4: 编译固件（仅 build_mode=full）
  [4.1] 预下载资源
  [4.2] 编译固件（多线程 -> 单线程 -> 详细日志三级重试）
  [4.3] 编译后磁盘使用

阶段 IB: ImageBuilder 快速构建（仅 build_mode=imagebuilder）
  [IB.1] 下载 ImageBuilder 与 SDK（与 tag 严格对应）
  [IB.2] SDK 编译第三方包（范围由 Packages.sh 决定，未克隆则跳过）
  [IB.3] 组装固件（make image，设备信息用 FILES= 覆盖）

阶段 5: 上传固件（两种模式共用）
  [5.1] 整理固件（重命名：编译时间 YYYYMMDD-HHMM 前缀在最前 + 定位编译产物目录）
  [5.2] 上传 sysupgrade 固件
  [5.3] 上传 recovery/factory 固件
  [5.4] 上传配置文件
  [5.5] 上传完整编译产物（整个 bin 目录）
```

## 构建方式：full 与 imagebuilder

工作流支持两种构建方式，通过 `build_mode` 参数切换：

| 方式 | 耗时 | 适用场景 | 局限 |
|------|------|----------|------|
| `full`（默认） | 约 2–3 小时（纯全量，ccache 只能部分加速） | 改内核、改 DTS、改设备定制 | 耗时长；不走 ccache 的巨包（如 ruby）无法加速 |
| `imagebuilder` | **约 10–15 分钟** | 调整软件包列表、改设备型号 | 不能改内核配置/补丁，不能自编 kmod（ABI 须配官方内核） |

### imagebuilder 模式的工作方式

不编译内核/工具链，而是复用官方预编译产物（与 `tag` 严格对应，保证包 ABI 一致）：

1. **[IB.1]** 下载 `immortalwrt-imagebuilder-<版本>-mediatek-filogic` 与对应 SDK
2. **[IB.2]** 用 SDK 编译 `Packages.sh` 实际克隆的第三方包（多为 `PKGARCH:=all` 的脚本/主题包，不涉及内核 ABI），产出安装包放入 ImageBuilder 的 `packages/`。安装包后缀按版本而定（v25.12.x 为 `.apk`，v24.10.x 为 `.ipk`，上游按 `PACKAGE_SUFFIX := $(if $(CONFIG_USE_APK),apk,ipk)` 动态判定），工作流不写死后缀；若某个包未产出安装包会显式报错，不再静默漏装
3. **[IB.3]** `make image PROFILE=... PACKAGES="..." [FILES="..."]` 组装固件，`PACKAGES` 列表由 `[3.3]` 从 `Packages.yaml` 生成；`make image` **之前**修改 IB 内 DTS 源的 `model` 属性（现场编译 dtb，型号改名在 dtb 层生效，见下文「设备型号」），`FILES=` 为可选的用户态文件覆盖

> **`FILES=` 是可选项**：`Devices/<设备>/files` 目录不存在时 `[IB.3]` 直接跳过用户态文件覆盖，不报错。使用时**路径不能含空格。** 设备目录名（如 `Cudy TR3000`）含空格，而上游 `include/rules.mk` 的 `file_copy` 里是未加引号的 `$(CP) $(1) $(2)`（`CP:=cp -fpR`），路径会被 shell 拆成两个参数，报两条 `cp: cannot stat` 并让 `prepare_rootfs` 失败（2026-09-25 实测）。因此 `[IB.3]` 先把 `Devices/<设备>/files` 复制到不含空格的中转目录 `$RUNNER_TEMP/ib-files`，再把该路径传给 `FILES=`。`make image` 完成后还会回到 rootfs 逐个核对文件是否落地——上游 `if [ -d '$(2)' ]` 在目录缺失时静默跳过，这一步把「覆盖悄悄失效」变成显式失败。

> **[IB.2] 的编译范围由 `Packages.sh` 决定，不在工作流里硬编码包名。** 它比对 `Packages.sh` 执行前后 `package/` 下 Makefile 的差集来识别新增的包（只认含 `BuildPackage` 或 `include package.mk`/`luci.mk` 的 Makefile，因此不会误抓仓库附带的纯工具 Makefile），包名优先取 `PKG_NAME:=`、缺失时回退为目录名。
>
> 若 `Packages.sh` 未克隆任何包（例如克隆语句被注释），该步骤直接跳过，对应软件包由 `[IB.3]` 从官方源安装——**此时需保证 `Packages.yaml` 里启用的包在官方源中存在**，否则 `make image` 会因找不到包而失败。增删第三方包只需改 `Devices/<设备>/` 下的配置，不必再动工作流。

### 设备型号（两种模式）

型号显示的真实链路（已按 ImmortalWrt v25.12.2 核实）：

```
dtb 的 model 属性
  → /proc/device-tree/model
    → /tmp/sysinfo/model        （preinit 02_sysinfo 写入）
      → ubus system.board.model （procd 优先读 /tmp/sysinfo/model）
        → LuCI 概览页「型号」
```

**改 dtb 的 model 才是全链路生效的做法。** 用户态补丁（改 `/etc/board.json`、
`/etc/openwrt_release`、`/etc/banner`）不在这条链路上，改了也不会反映到概览页；
且 `/tmp/sysinfo/model` 位于 tmpfs、每次启动由 `02_sysinfo` 重新生成，用户态
一次性补丁无法持久生效。

两种模式都改 dtb，只是位置不同：

| 模式 | 做法 |
|------|------|
| `full` | `Customize.sh` 修改源码树 `target/linux/mediatek/dts/<设备>.dts` 的 `model`，编译时生成 dtb |
| `imagebuilder` | `[IB.3]` 在 `make image` 前把新型号写进 IB 内**预编译的 dtb**（直接改 dtb 二进制的 model 字符串：整串替换 + 短名补 NUL，fdt 总长与 offset 不变），并同步 sed DTS 源保持一致。新名字节数须 ≤ 原名，否则报错请改用 full |

型号字符串由 `Device.yaml` 的 `Model_dts`（DTS 原始值）与 `Model`（目标值）提供，
`imagebuilder` 模式下替换带校验：找不到 DTS 文件、或构建后 dtb 仍含旧型号，
都会让构建显式失败，不会静默出一个没改名的固件。

### 注意事项

- `imagebuilder` 模式下 `cache_enabled` 不生效（无需编译缓存），恢复 ccache/dl 等步骤自动跳过
- 若目标 tag 尚未发布官方 ImageBuilder，`[IB.1]` 会报错退出，此时改用 `full` 模式
- 内核模块类第三方包（`kmod-xxx`）需与官方内核 ABI 严格匹配；当前配置已移除 `kmod-oaf`，若将来加回请自行评估
- **`[IB.1]` 要求归档唯一命中**：同一目录若出现多个 ImageBuilder 或 SDK 归档（多宿主架构、多 gcc 版本等），会列出候选并报错退出，不会静默取第一个；下载后还会做一次归档完整性校验，避免下载被截断后在解压阶段才暴露
- **`[IB.2]` 会核对第三方包产物**：按版本实际后缀收集（`.apk` 或 `.ipk`），并逐个确认 `Packages.sh` 克隆的每个包都产出了安装包；若有包缺失（make 未报错但产物为空）则显式失败，不会静默漏装
- **`[IB.3]` 会核对用户包已装入固件**：`make image` 后用上游生成的 `*.manifest` 逐个比对 `Packages.yaml` 里启用的包；若 `packages_list.txt` 异常为空导致只构建出默认固件，会显式失败，不会静默产出缺包的固件

### ruby YJIT 开关（`ruby_yjit`，仅 full 模式）

`luci-app-openclash` 依赖 `ruby`，而 ruby 的 `RUBY_ENABLE_YJIT` 在 aarch64 上默认开启；YJIT 是用 Rust 实现的 JIT 编译器，其构建依赖 `PKG_BUILD_DEPENDS: RUBY_ENABLE_YJIT:rust/host`，会拉入整个 Rust/LLVM 工具链。实测 **ruby + rust 合计占编译时间约 77%**（ruby 131 分钟 + rust 与其并行）。

OpenClash 只用 ruby 跑订阅规则转换等一次性短脚本，JIT 加速没有收益。把 `ruby_yjit` 设为 `false` 后，`[3.5.2]` 会：

1. 把 `feeds/packages/lang/ruby/Makefile` 中 `RUBY_ENABLE_YJIT` 的 `default y` 改为 `default n`
2. 在 `.config` 显式写入 `# CONFIG_RUBY_ENABLE_YJIT is not set`

两者都必须在 `[3.6]` defconfig **之前**完成——依赖解析发生在 defconfig，晚了就拦不住 `rust/host` 被拉入构建图。`imagebuilder` 模式用官方预编译的 ruby 包，不受此开关影响。

## 配置文件说明

### Device.yaml

设备配置文件，定义设备的基本参数（键名首字母大写）：

```yaml
# 设备型号（用于固件命名与 Artifact 命名）
Model: "Cudy TR3000"

# DTS 中的原始型号名（dtb model 属性）
# imagebuilder 模式在 make image 前把它替换为 Model；full 模式由 Customize.sh 处理
# 可选；缺失或与 Model 相同则跳过型号替换
Model_dts: "Cudy TR3000 v1 (OpenWrt U-Boot layout)"

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
  # LuCI 中文支持（翻译按包分发，各 luci-app 的中文是独立的 luci-i18n-<名>-zh-cn）
  - luci-i18n-base-zh-cn
  - luci-i18n-mwan3-zh-cn
  - luci-i18n-ttyd-zh-cn
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

> **中文翻译的分包规则**：LuCI 翻译按包分发，`luci-i18n-base-zh-cn` 只覆盖
> `luci-base` 的界面文案（核心模块 `luci-mod-status`/`system`/`network` 的字符串
> 也收录在 `base.po`，没有独立语言包）；各 `luci-app-*` 与 `luci-mod-dashboard`
> 的翻译是独立的 `luci-i18n-<名>-zh-cn` 包，不安装对应页面就是英文。`zh-cn` 是
> `zh_Hans` 的别名（`luci.mk` 的 `LUCI_LC_ALIAS`）。启用新 `luci-app` 时记得同步
> 补它的 `luci-i18n-<名>-zh-cn`；这些包必须在官方源中存在，否则 `make image`
> 会因找不到包而失败。
>
> **例外**：`luci-i18n-openclash-zh-cn` 在官方源中不存在，**禁止启用**——
> OpenClash 的 po 目录名是旧式 `zh-cn`，不在 `luci.mk` 的 `LUCI_LANG` 白名单
> （只有 `zh_Hans`），官方构建不生成它的语言包，启用必报
> `no such package` 失败（2026-09-26 实测）。

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
# 可选：DTS 中的原始型号名（imagebuilder 模式替换为 Model 用，无需改型号就不写）
# Model_dts: "..."
Packages_list: "Packages.yaml"
Target: "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s=y"
```

### 3. 创建 Packages.yaml

```yaml
enable:
  - luci-i18n-base-zh-cn
  - luci-i18n-mwan3-zh-cn
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

编译完成后最多上传 4 个 Artifact。Artifact 名称以**编译时间** `YYYYMMDD-HHMM` 开头（时区取 job 的 `TZ`，当前 `Asia/Shanghai`），便于在 Actions 页面按编译先后排序；设备型号中的**空格去掉**（如 `CudyTR3000`），避免下载的 zip 文件名带空格。下载后的压缩包名即 `<Artifact 名称>.zip`。

| Artifact | 下载后文件名 | 内容 |
|----------|--------------|------|
| `...-sysupgrade` | `20260922-1930-ImmortalWrt-CudyTR3000-v25.12.2-sysupgrade.zip` | 系统升级固件（匹配 `*sysupgrade*`） |
| `...-recovery` | `20260922-1930-ImmortalWrt-CudyTR3000-v25.12.2-recovery.zip` | 恢复/工厂固件（匹配 `*recovery*`、`*factory*`），无此产物时跳过 |
| `...-config` | `20260922-1930-ImmortalWrt-CudyTR3000-v25.12.2-config.zip` | 编译配置，文件名为 `编译时间-设备型号-ImmortalWrt-V版本-构建号-config.config` |
| `...-full` | `20260922-1930-ImmortalWrt-CudyTR3000-v25.12.2-full.zip` | **完整编译产物**（见下） |

> **`imagebuilder` 模式通常只有 3 个 Artifact（没有 `-recovery`）。** 这不是工作流缺陷，而是上游 ImageBuilder 的固有行为：`recovery` 镜像由 `KERNEL_INITRAMFS` 产出，而 ImageBuilder 在打包时会显式删除预编译的 initramfs 内核（`target/imagebuilder/Makefile` 中的 `rm -f $(IB_KDIR)/vmlinux-initramfs*`，已按 ImmortalWrt v25.12.2 核实），因此无法生成 `*recovery*`；该设备（`cudy_tr3000-v1-ubootmod`）本身有 `IMAGES := sysupgrade.itb`，`full` 模式则会正常产出 `initramfs-recovery.itb`。此时 `[5.3]` 步骤输出一条 `No files were found ...` 的警告并上传 0 个文件，属预期现象。

其中 `-full` 上传的是**整个 `bin` 输出目录**（`bin/`）内的全部内容，而不是单独的几个固件，包含：

- `bin/targets/<平台>/`：固件镜像（含本设备与同平台其他设备的镜像）、内核与设备树（`*Image`、`*.dtb`）、`profiles.json`、`sha256sums`、`*.manifest`
- `bin/packages/<架构>/`：编译出的全部安装包（v25.12.x 为 `.apk`，v24.10.x 为 `.ipk`）

该步骤显式启用了 `include-hidden-files`（隐藏文件默认不上传）。此参数需要 `actions/upload-artifact` v4.4.0+，`@v4` 已满足；若日志报 `Unexpected input(s) 'include-hidden-files'`，说明所用 v4 版本过旧。

已重命名的固件统一格式为 `编译时间-设备型号-ImmortalWrt-V版本-构建号-类型.扩展名`，例如
`20260922-1930-Cudy TR3000-ImmortalWrt-V25.12.2-r1234-abcd123-squashfs-sysupgrade.itb`。

编译时间前缀为 `YYYYMMDD-HHMM`（取 `[5.1]` 的执行时刻，时区为 job 的 `TZ`），放在文件名最前面便于按编译先后排序；配置文件与各 Artifact 名称使用同一前缀。

设备型号保留原有空格（如 `Cudy TR3000`）；仅在 Artifact 名称中去掉空格（`CudyTR3000`），避免下载的 zip 文件名带空格。

支持的固件格式：`.itb`、`.bin`、`.img.gz`、`.squashfs`

## 许可证

本项目为个人配置仓库，未单独声明开源许可证；所编译的 ImmortalWrt 源码遵循其上游许可证。
