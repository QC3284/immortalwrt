# checkpatch 基线与豁免（方案 C，2026-11-21）

树 fork 用树内 `scripts/checkpatch.pl` 检查 `e2631` 分支相对钉死基底
`a4ba8240d8a1aaef7e8c6f2d65e841a9bfd2b8c5` 的每一个非 merge 提交（C-CI1，
2026-11-21 落地）：

```
E2631_IW_SHA=a4ba8240d8a1aaef7e8c6f2d65e841a9bfd2b8c5 \
  bash scripts/check-e2631-checkpatch.sh
```

执行顺序（`scripts/check-e2631-checkpatch.sh`）：

1. `perl scripts/checkpatch.pl --no-tree --show-types -g <sha>` 逐提交检查；
2. 先按本文件的机器可读豁免表（路径 glob × 类型）过滤；
3. 再按门禁范围过滤：`target/linux/zx279128/**`（`patches-*` 与 `*.patch`
   除外）+ `package/e2631/**`。范围外的发现（上游基底、其他 target、kit 文档）
   只计数、不失败；
4. 提交消息级发现（没有 `FILE:` 上下文，例如 `MISSING_SIGN_OFF`）**始终在
   范围内**，只有显式的 `commit:<sha>` 豁免才能放过（当前表内没有这类条目）。

检查是整提交口径：提交消息、`Signed-off-by` 与 diff 一起检查；解析必须用默认
输出（`#N: FILE: <path>` 上下文行），`--terse` 没有文件路径，不能做路径豁免。
不做全局 `--ignore`：同类型问题在豁免路径之外仍然会被报告。

预期结果：范围内 0E/0W。按新系列最终内容的预演（2026-11-21），范围内共
28E/22W，全部落入 E1-E4；提交消息级检查（含 `Signed-off-by`）也全部通过。

## 机器可读豁免表（脚本直接解析这一段）

格式：`路径 glob | 类型[,类型...]`，`*` 表示全部类型；`commit:<sha>` 只用于
提交消息级豁免（当前未使用）。注释与空行忽略。改这里就是改门禁，无需改脚本。

<!-- checkpatch-exemptions:begin -->
# E1: OpenWrt base-files 运行时脚本与 rpcd 插件按 mode 安装，执行位是功能本身
target/linux/*/base-files/** | EXECUTE_PERMISSIONS
package/*/root/usr/libexec/rpcd/* | EXECUTE_PERMISSIONS
# E2: 补丁文件（diff 上下文空行是 "+ "，删空格会破坏 git apply；字节是 provenance）
**/patches/** | *
*.patch | *
# E3: 用户可见消息每条一行（cd14ffa 的约定），行长与单行消息互斥
package/e2631/e2631-fwslot/src/e2631-fwslot.c | LONG_LINE,LONG_LINE_STRING,SPLIT_STRING
# E4: callE2631* RPC 包装函数名被 TYPO_SPELLING 误报为 "called"
package/e2631/luci-app-e2631/htdocs/luci-static/resources/view/system/e2631flash.js | TYPO_SPELLING
<!-- checkpatch-exemptions:end -->

## 逐条依据

| ID | 规则 | 实测数量 | 依据 |
| --- | --- | --- | --- |
| E1 | `target/linux/*/base-files/**` + `package/*/root/usr/libexec/rpcd/*` 的 EXECUTE_PERMISSIONS | 28（26+2） | OpenWrt 安装时按 git mode 写镜像：RUN3 根文件系统（mtd7 dump）的 mode 与 git 100755 集合逐一吻合（`/etc/init.d/e2631-*`、`/sbin/e2631-*`、`rc.button/lights_toggle`、`rc.wps/00-h3600-ledblink`、`usr/libexec/rpcd/e2631*` 均 `-rwxr-xr-x`；而 `/lib/preinit/79_e2631_userdata`、`/sbin/e2631-preflight`、uci-defaults 是 100644 也与 git 一致）；上游同款先例 75 个 100755。该规则来自内核源码树，不适用于 OpenWrt base-files。 |
| E2 | 补丁文件全部类型 | 26（21+4+1） | `patches-6.18` 21 + fstools 203/204 4 + mt76 002 1，实测只有 TRAILING_WHITESPACE。diff 上下文空行是"+"后跟一个空格（`+ `），删掉空格会破坏 `git apply`/`patch -p1`；补丁字节同时是 provenance/sha256 锚点。D3/D7 明文：target 补丁不跑 checkpatch。 |
| E3 | `e2631-fwslot.c` 的 LONG_LINE、LONG_LINE_STRING、SPLIT_STRING | 14（6+8；SPLIT_STRING 0） | 这些行是用户可见的提示/错误消息；"每条消息一行"便于 grep（checkpatch 的 SPLIT_STRING 规则本身也说明跨行会破坏 grep）。折行会回到 SPLIT_STRING 报错，两条规则互斥，只豁免其一。实测最长 174 列。 |
| E4 | `e2631flash.js` 的 TYPO_SPELLING | 8 | 误报：`callE2631Check`/`callE2631Run`/`callE2631Slots`/`callE2631Switch` 是 RPC 包装函数名，被当成 "called" 的拼写错误。 |

不豁免、必须为 0 的类型：COMMIT_LOG_LONG_LINE、BAD_SIGN_OFF、
NO_AUTHOR_SIGN_OFF、MISSING_SIGN_OFF、SPDX_LICENSE_TAG、
非补丁文件的 TRAILING_WHITESPACE、BLOCK_COMMENT_STYLE、UNSPECIFIED_INT、
SPACING、LINE_SPACING 等。新系列按"构造即干净"重建：文件首次引入就是最终
内容（SPDX 在第 2 行、无行尾空白、无长行、C 注释/整型字面量已清理），因此
门禁逐提交均可达标。

## 维护约定

- 新豁免必须写明"路径 × 类型"与依据，并先证明它不是普遍现象；不要删除
  E1-E4 来"让门禁变绿"。
- 提交消息级问题优先原地修正（author/SOB 可 amend，diff 零变不动内容）：
  2026-11-21 的 `d74ec77a → f85cbea0` 就是这样处理的，因此表里没有历史例外。
  确需豁免时只允许 `commit:<sha>` 形式，必须带日期/原因，并在下一次自然重钉
  时清理。
- 修改本文件后本地复跑：`E2631_IW_SHA=<pin> bash scripts/check-e2631-checkpatch.sh`。

## 历史说明

2026-11-21 之前的旧系列（tip `5202d4ca`）保存在 `e2631-legacy`，不作为
新门禁对象；旧系列的清理台账见 kit 仓库
`evidence/c-plan-checkpatch-precheck-20261121.md`。

2026-11-21 方案 C 树尖曾因缺 `Signed-off-by` 被本门禁拦下；裁决不是加临时豁免，
而是原地 amend（author 改为 `QC3284 <2078725082@qq.com>` 并补 `Signed-off-by`，
diff 与树零变）：内容 tip `d74ec77a` → `f85cbea0`，门禁提交 rebase 后为
`8cdeba9b`。因此豁免表只需要内容类规则 E1-E4。
