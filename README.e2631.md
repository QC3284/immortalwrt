# ImmortalWrt tree fork for ZTE ZXHN E2631 (branch `e2631`)

本仓库是 `immortalwrt/immortalwrt` 的 fork，`e2631` 分支在 ImmortalWrt
master 基础上加入 ZTE ZXHN E2631（ZX279128S，target `zx279128`）的板级
支持和设备包。它是 `QC3284/zte-e2631-immortalwrt` 打包/发布 kit 的源码
树：kit 只保留 host 工具、CI 和 Release 打包。

2026-11-21 的主线化重建（方案 C）把旧系列改写为按主线惯例组织的新系列；
旧历史完整保存在分支 `e2631-legacy`（tip `5202d4ca`，含旧钉点与合并
历史），永久可引用、可回滚。

## 基线

| 项目 | 值 |
| --- | --- |
| 上游 | https://github.com/immortalwrt/immortalwrt |
| 分支基点 | `master` @ `a4ba8240d8a1aaef7e8c6f2d65e841a9bfd2b8c5`（2026-11-14） |
| kernel | 6.18.60（`target/linux/generic/kernel-6.18`） |
| 包格式 | apk（`apk-openssl`，ImmortalWrt 默认） |

基点之后先有 4 个移植 commit（作者 Navid Ghahremani，GPL-2.0，来自
`Zlion-Y/openwrt-sanechips-mirror` 的 `pr-zte-zxhn-h3600` 分支）：

- `zx279128: add generic DWC3 platform glue driver`
- `mt76: serialize device reads with outer cache maintenance`
- `zx279128: add ZX279128S target`
- `zx279128: add support for ZTE ZXHN H3600`

这 4 个 commit 之后的树哈希是不变量：

    6136bd92d5259dbaf22f6bca02c675f05abdf86b

kit 的 `base/commits.env` 与树 CI 都以它作为钉死锚点；这 4 个 commit 不要
squash 或改写（往上追加 commit 不影响校验）。

## `e2631` 分支上新增的 commit

1. `zx279128: add ZTE ZXHN E2631 board support` —— 板级 DTS、slot 分区解析
   器、FFE/PPE 内核文件、base-files（网络/无线/升级/preinit 等）、合并后的
   镜像配方、029/030/031/033/034 内核补丁、target kernel config，以及
   `target/linux/generic/config-6.18` 中 hung-task / softlockup 三处调整。
2. `e2631: add the E2631 device packages` —— 设备包放在
   `package/e2631/`（`e2631-fwslot`、`luci-app-e2631`、
   `luci-app-e2631-wanport`、`luci-app-zte-mesh`、`zte-mesh`），并带上
   mt76 的 caldata 补丁/包调整和 fstools 的 overlay RAM fallback 补丁。
3. `e2631: add the image seed and build notes` —— `seed/e2631.config` 与
   本文件。
4. `ci: check the e2631 tree without building it` —— 静态树门禁。
5. 之后的 `e2631:` / `zx279128:` 修复系列按主题独立提交。

## 构建

```sh
git clone https://github.com/QC3284/immortalwrt -b e2631
cd immortalwrt
./scripts/feeds update -a
./scripts/feeds install -a
cp seed/e2631.config .config
make defconfig
make -j"$(nproc)"
```

产物在 `bin/targets/zx279128/generic/`。固件布局以 kit 的几何常量为准：
kernel 位于 `0x400000`、rootfs 窗口 `0x1100000`（17 MiB）、镜像头
`0x1500000`；正式产物由 kit 的 GitHub Actions（`firmware.yml`）打包成
`e2631-immortalwrt-*.bin`。factory 格式需要一个官方 E2631 升级包作版本头
模板（`CONFIG_E2631_VENDOR_TEMPLATE`），不随仓库分发。

## userdata 分区与 extroot（v1.10）

47 MiB 的 `userdata` 分区可被激活成 `/overlay`（extroot），把可写空间从
内部 overlay 的约 8 MiB 提升到约 35 MiB。ROM 里 fstab 的 `e2631_extroot`
默认 `enabled='0'`，只有下面这条链会把它打开：

1. preinit（`/lib/preinit/79_e2631_userdata`，早于 `mount_root`）挂上 UBI；
   卷上已有 UBIFS 超级块时，短暂只读挂载读取快照标记并与本固件身份比对，
   不匹配就移除 `/dev/ubi0_0`、把原因写进 `/tmp/e2631-userdata-refused`，
   `mount_root` 不会切到该卷。这一步必须放在 preinit：`mount_root` 发生在
   `/etc/init.d/` 之前，只靠 rcS 里的 gate 拦不住旧快照。
2. 激活 gate（`/etc/init.d/e2631-userdata`，START=11）按四个分支处理（见
   下表），只有"卷为空 + autoadopt=1"或"快照匹配 + fstab 已启用"才会把
   `enabled` 写成 1，其余情况一律留在内部 overlay。
3. 下一次启动由 fstools 把该卷挂成 `/overlay`。

| 分支 | 卷状态 | 行为 |
| --- | --- | --- |
| 无卷（或空卷）+ autoadopt=1 | 没有 UBIFS 超级块 | 调 `/sbin/e2631-userdata-init --apply`（六道检查 + 确认字串）格式化、写入快照标记、迁移现有配置、打开 extroot；本次启动仍走内部 overlay |
| 空卷 + autoadopt=0 | 没有超级块 | 什么都不做，留在内部 overlay |
| 已格式化 + autoadopt=0 | 标记与固件匹配 | 留在内部 overlay。v1.10 之前这里会无条件重新启用 extroot，是 2026-11-14 事故的直接原因 |
| 已格式化 + 标记缺失/不匹配 | 旧快照或未标记的卷 | 拒绝：不挂载、不写 fstab（若 enabled=1 则改回 0）、不格式化，卷原样保留 |

快照标记是卷上的 `/etc/e2631-userdata-version`，内容为固件身份（例如
`ImmortalWrt SNAPSHOT r0-bde1448 ImmortalWrt v1.10.0`），由
`/lib/e2631-snapshot.sh` 生成；只有本固件（自动 gate 或手动
`e2631-userdata-init`）格式化的卷才会带标记。

恢复/重置：被拒绝的旧卷不会被自动清除；确认里面配置不再需要后，先
`ubidetach -d 0`，再对 `userdata` 对应的 mtd（在
`/sys/class/mtd/mtd*/name` 里找编号）执行 `mtd erase`，重启后按空卷流程
重新 adopt。设置 `e2631.storage.autoadopt=0` 则完全手动：只有

## 安全提示（首次开机）

- 首次开机**没有 root/管理员密码**，无线是**开放网络**（无 Wi-Fi 密码）：
  这是刷机后的应急配置通道，管理面只在 LAN 侧；WAN 侧默认不放行
  22/80/443（v1.10 起不再生成旧的 `Allow-SSH-WAN-*` / 私网 HTTP(S) 规则）。
- 开机后请立即：浏览器登录 `http://192.168.1.1` 设置 root 密码，并给无线
  加 WPA2 密码（LuCI，或 `sbin/e2631-wifi-ap` 传 key），然后再接入既有网络。
- 不要临时把 SSH/HTTP 开放到 WAN 后忘记关闭；旧镜像（v1.9 及以前）默认对
  192.168.0.0/16、10.0.0.0/8 放行 SSH，并对私网放行 HTTP/HTTPS，升级后
  这些规则不会再出现。

## 代码风格（checkpatch）

树内容按内核 checkpatch 基线清理：`scripts/checkpatch.pl --no-tree
--show-types -g <commit>`。检查是整提交口径（提交消息与 Signed-off-by
也算）；豁免按"路径 glob × 类型"记录在
[`docs/checkpatch-exemptions.md`](docs/checkpatch-exemptions.md)，树 CI 的
checkpatch job 读取同一份文档。4 个移植 commit 保留原作者
author/date/SOB，并追加本 fork 的 Signed-off-by。

## 约定

- 本 fork 自用，不向上游提 issue/PR。
- 真机刷写有风险；镜像只由 kit 的发布流程产出，刷写前需人工确认。
- `e2631` 系列在 2026-11-21 重建后再次改写需要 Lead 批准并使用
  `--force-with-lease`；`e2631-legacy` 保留重建前的完整历史，不要再改。
