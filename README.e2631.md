# ImmortalWrt tree fork for ZTE ZXHN E2631 (branch `e2631`)

本仓库是 `immortalwrt/immortalwrt` 的 fork，`e2631` 分支在 ImmortalWrt
master 基础上加入 ZTE ZXHN E2631（ZX279128S）的板级支持和设备包。它是
`QC3284/zte-e2631-immortalwrt` 打包/发布 kit 的源码树：kit 只保留 host
工具、CI 和 Release 打包，不再用 `git am` + overlay 的方式给上游打补丁。

## 基线

| 项目 | 值 |
| --- | --- |
| 上游 | https://github.com/immortalwrt/immortalwrt |
| 分支基点 | `master` @ `4765b657625ec5bbda74b44400465fe043802b30`（2026-11-05） |
| kernel | 6.18.60（`target/linux/generic/kernel-6.18`） |
| 包格式 | apk（`apk-openssl`，ImmortalWrt 默认） |

基点之后先有 4 个移植 commit（作者 Navid Ghahremani，GPL-2.0，来自
`Zlion-Y/openwrt-sanechips-mirror` 的 `pr-zte-zxhn-h3600` 分支）：

- `kernel: add generic DWC3 platform glue package`
- `mt76: serialize device reads with outer cache maintenance`
- `sanechips: add ZX279128S target`
- `sanechips: add support for ZTE ZXHN H3600`

这 4 个 commit 之后的树哈希是不变量：

    4f89aa7ad0a5132dc047a27a9073b43916f0f957

kit 的 `base/commits.env` 和本仓库都以它作为三方钉死的锚点；kit 的
`make check` 会在本 fork 的历史里查找这个 tree，所以这 4 个 commit 不要
squash 或改写（往上追加 commit 不影响校验）。

## `e2631` 分支上新增的 commit

1. `sanechips: add ZTE ZXHN E2631 board support` —— 板级 DTS、slot 分区解析
   器、FFE/PPE 内核文件、base-files（网络/无线/升级/preinit 等）、镜像配方、
   029/030/031/033/034 内核补丁、target kernel config，以及 generic config
   中 hung-task / softlockup 三处调整。
2. `e2631: add the E2631 device packages` —— 设备包移到
   `package/e2631/`（`e2631-fwslot`、`luci-app-e2631`、
   `luci-app-e2631-wanport`、`luci-app-zte-mesh`、`zte-mesh`），并带上
   mt76 的 caldata 补丁 / 包调整和 fstools 的 overlay RAM fallback 补丁。
3. `e2631: add the image seed and build notes` —— `seed/e2631.config` 与本文件。

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

产物在 `bin/targets/sanechips/generic/`。固件布局以 kit 的几何常量为准：
kernel ��� `0x400000`、rootfs 窗口 `0x1100000`（17 MiB）、镜像头
`0x1500000`；正式产物由 kit 的 GitHub Actions（`firmware.yml`）打包成
`e2631-immortalwrt-*.bin`。

## 约定

- 本 fork 自用，不向上游提 issue/PR。
- 真机刷写有风险；镜像只由 kit 的发布流程产出，刷写前需人工确认。
- `e2631` 分支只做 fast-forward 式更新，不要 force-push：上面那个不变量
  树必须一直可达。
