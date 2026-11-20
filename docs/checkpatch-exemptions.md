# checkpatch 基线与豁免（方案 C，2026-11-21）

树 fork 用树内 `scripts/checkpatch.pl --no-tree --show-types -g <commit>`
检查 `e2631` 分支相对钉死基底
`a4ba8240d8a1aaef7e8c6f2d65e841a9bfd2b8c5` 的全部提交（merge 不计）。
检查是整提交口径：提交消息、`Signed-off-by` 与 diff 一起检查；解析必须用
默认输出（`#N: FILE: <path>` 上下文行），`--terse` 没有文件路径，不能做
路径豁免。

门禁范围（D1，2026-11-21 Lead 决定）：`target/linux/zx279128/**`
（`patches-6.18/` 与 `*.patch` 除外）+ `package/e2631/**`。范围外的文件
（base 自带、kit 文档、其他 target）不进门禁。

预期结果：范围内 0E/0W；下列四类豁免按"路径 glob × 类型"匹配，不做全局
`--ignore`（全局忽略会漏掉非豁免位置的同类问题）。按新系列最终内容的
预演（2026-11-21），范围内共 28E/22W，全部落入 E1-E4。

| ID | 路径模式 | 类型 | 数量 | 依据（为什么有据） |
| --- | --- | --- | --- | --- |
| E1 | `target/linux/*/base-files/**`（mode 100755 的脚本）+ `package/*/root/usr/libexec/rpcd/*`（100755） | EXECUTE_PERMISSIONS | 28（26+2） | OpenWrt 运行时脚本的执行位是功能的一部分，安装时按 mode 进镜像：RUN3 根文件系统（mtd7 dump）的 mode 与 git 100755 集合逐一吻合；上游同款先例 75 个 100755。该规则来自内核源码树，不适用于 OpenWrt base-files。 |
| E2 | 补丁文件：`**/patches/**`、`*.patch` | 全部类型（当前仅 TRAILING_WHITESPACE） | 26（21+4+1） | diff 上下文空行是"+"后跟一个空格（`+ `），删掉空格会破坏 `git apply`/`patch -p1`；补丁字节是 provenance/sha256 锚点。D3/D7 明文：target 补丁不跑 checkpatch。 |
| E3 | `package/e2631/e2631-fwslot/src/e2631-fwslot.c` | LONG_LINE、LONG_LINE_STRING、SPLIT_STRING | 14（6+8；SPLIT_STRING 0） | 这些行是用户可见的提示/错误消息；"每条消息一行"便于 grep（checkpatch 的 SPLIT_STRING 规则本身也说明跨行会破坏 grep）。折行会回到 SPLIT_STRING 报错，两条规则互斥，只豁免其一。 |
| E4 | `package/e2631/luci-app-e2631/htdocs/.../system/e2631flash.js` | TYPO_SPELLING | 8 | 误报：JS 里四个 RPC 包装函数名以 call + E2631 + Check/Run/Slots/Switch 拼成，被当成 "called" 的拼写错误。 |

不豁免、必须为 0 的类型：COMMIT_LOG_LONG_LINE、BAD_SIGN_OFF、
NO_AUTHOR_SIGN_OFF、SPDX_LICENSE_TAG、非补丁文件的 TRAILING_WHITESPACE、
BLOCK_COMMENT_STYLE、UNSPECIFIED_INT、SPACING、LINE_SPACING 等。新系列
按"构造即干净"重建：文件首次引入就是最终内容（SPDX 在第 2 行、无行尾
空白、无长行、C 注释/整型字面量已清理），因此门禁逐提交均可达标。

## 历史说明

2026-11-21 之前的旧系列（tip `5202d4ca`）保存在 `e2631-legacy`，不作为
新门禁对象；旧系列的清理台账见 kit 仓库
`evidence/c-plan-checkpatch-precheck-20261121.md`。
