# checkpatch 基线与豁免（2026-11-14）

树 fork 用上游内核自带的 `scripts/checkpatch.pl --no-tree` 检查 e2631 分支的
改动：`scripts/checkpatch.pl --no-tree --terse --show-types -g <commit>`。

两类历史保持原样，不因风格改写：4 个 sanechips 移植 commit（其 tree hash
`4f89aa7a…` 是 kit 的钉死锚点）和 3 个 E2631 历史 commit（可审计性）。它们
histor 的 patch 里仍会有 checkpatch 报告，树内容的清理由 `style:` commit
承担。当前基线（2026-11-14, style commit 之后）：

| commit | 内容 | checkpatch | 处理 |
| --- | --- | --- | --- |
| `6710182` | sanechips: H3600 support（移植） | E=2 W=25 | 执行位豁免（见下），其余 warning 保留 |
| `f2d03c4` | E2631 board support | E=45 W=45 | 内容由 style commit 修掉 |
| `8a253ea` | E2631 device packages | E=29 W=34 | 内容由 style commit 修掉 |
| `e96aed3` | image seed and build notes | 0/0 | — |
| `5f85f8e`, `e284f16` | CI-only commits | 重写后 0/0 | 见下"CI commit 重写" |
| `eeccd9d`… | 之后的修复 commit | 逐个 signed-off；内容由后续 commit 修 | — |

## CI commit 重写说明

两个 CI-only commit（`ci: add a static tree gate…`、`ci: use
actions/checkout@v5…`）在分支上是本树自己的产物、没有任何门禁钉它们的
hash，因此补上了 commit description 和 `Signed-off-by`；两者的文件内容与
原 commit 逐字节相同（tree 一致），checkpatch 从 E=1/W=1 变为 0/0。

## 1. EXECUTE_PERMISSIONS（init.d / hotplug / preinit / sbin 脚本）

checkpatch 对新增的可执行文件报：

    ERROR:EXECUTE_PERMISSIONS: do not set execute permissions for source files

这条规则来自内核源码树（内核源码不应带执行位）。本树的这些文件不是内核
源码，而是 OpenWrt 运行时脚本：`/etc/init.d/*`（rc.common 直接执行）、
`/etc/hotplug.d/*`（hotplug 执行）、`/lib/preinit/*`（/etc/preinit source
的钩子）和 `/sbin/*` 用户命令；base-files 按 mode 安装，执行位是功能的一
部分，会进入镜像。**豁免，不修改。** 涉及 `6710182`（2 处）、`f2d03c4`
（24 处）、`8a253ea`（2 处）。

## 2. 以文件形式提交的 *.patch 里的 trailing whitespace

`target/linux/sanechips/patches-6.18/0*.patch` 和
`package/system/fstools/patches/204-*.patch` 里 diff 的上下文空行是
"+" 后跟一个空格（`+ `）；checkpatch 按普通文本扫描会报
TRAILING_WHITESPACE。那是补丁语法本身（空上下文行），删掉空格会破坏
`git apply` / `patch -p1`。**豁免，不修改。**

## 3. style commit 之后仍保留的 warning

- SPLIT_STRING（`e2631-fwslot.c`，17 处）：内核风格的提示；这些是已经
  分段的可读输出字符串，合并会超过 100 列且损害 grep，保留；
- LONG_LINE_STRING（2 处，`e2631-fwslot.c`）：同上，输出格式串；
- TYPO_SPELLING（8 处，`e2631flash.js`）：误报，`call` 前缀与型号拼接的 RPC
  包装函数名被当成 "called" 的拼写错误。

其余 ERROR/WARNING（SPACING、LINE_SPACING、BLOCK_COMMENT_STYLE、
UNSPECIFIED_INT、SPDX_LICENSE_TAG、LONG_LINE）已在 style commit 修掉：
`checkpatch --no-tree` 对该 commit 的 diff 为 0 errors / 0 warnings。
