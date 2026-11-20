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
