#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# check-e2631-image-expansion.sh - plan C image-pipeline expansion gate.
#
# RUN6 v2 shipped a broken image because the e2631 device define lost one $:
# "check-size $$(KERNEL_SIZE)" became "check-size $(KERNEL_SIZE)", so the
# merged image/Makefile expanded the kernel pipeline stage to an empty limit.
# The build stayed green; only the device boot showed the damage, so this gate
# parses the image makefiles (make -pn, no build). It fails on:
#
#   1. make cannot parse the image context (or reports an error);
#   2. the expanded global KERNEL pipeline does not carry exactly one
#      "check-size 4096k" stage (catches the lost-$ regression and a wrong or
#      unexpanded limit);
#   3. any check-size invocation in the dump has an empty argument (the shape
#      RUN6 v2 produced: "| check-size" at the end of the pipeline);
#   4. the kernel.bin recipe in define Device/Build/kernel no longer carries
#      exactly two non-empty check-size invocations: the device pipeline
#      (concat_cmd of KERNEL) plus the check image.mk appends after it.
#
# Run from the repository root (TOPDIR defaults to the current directory):
#
#   bash scripts/check-e2631-image-expansion.sh
#
set -u

topdir=$(printenv TOPDIR || true)
[ -n "$topdir" ] || topdir=$(pwd)
out=$(mktemp) || exit 2
err=$(mktemp) || exit 2
block=$(mktemp) || exit 2
trap 'rm -f "$out" "$err" "$block"' EXIT

fail() {
	printf 'check-e2631-image-expansion: FAIL - %s\n' "$*" >&2
	exit 1
}

cd "$topdir" || fail "cannot enter TOPDIR=$topdir"
[ -f target/linux/zx279128/image/Makefile ] ||
	fail "no target/linux/zx279128/image/Makefile under $topdir"

if ! TOPDIR="$topdir" make -C target/linux/zx279128/image -pn SUBTARGET=generic DUMP=1 >"$out" 2>"$err"; then
	sed 's/^/    /' "$err" >&2
	fail "make -pn could not parse the image context"
fi
if grep -q '[*][*][*]' "$out" "$err"; then
	grep -n '[*][*][*]' "$out" "$err" | head -5 | sed 's/^/    /' >&2
	fail "make reported parse errors"
fi

kcount=$(grep -cE '^KERNEL :=' "$out" || true)
[ "$kcount" -eq 1 ] || fail "expected exactly one expanded '^KERNEL :=' line, found $kcount"
kline=$(grep -E '^KERNEL :=' "$out")
case "$kline" in
*'check-size 4096k'*) ;;
*) fail "global KERNEL pipeline lacks 'check-size 4096k': $kline" ;;
esac
ccount=$(grep -oF 'check-size' <<<"$kline" | wc -l)
[ "$ccount" -eq 1 ] || fail "global KERNEL pipeline has more than one check-size stage: $kline"
qcount=$(grep -cF '$(KERNEL_SIZE)' <<<"$kline" || true)
[ "$qcount" -eq 0 ] || fail "global KERNEL still carries an unexpanded KERNEL_SIZE: $kline"

empty=$(grep -nE '(^|[|[:space:]])check-size[[:space:]]*([|]|$)' "$out" || true)
[ -z "$empty" ] || {
	printf '%s\n' "$empty" | sed 's/^/    /' >&2
	fail "check-size invocation with an empty argument"
}

awk '/^define Device.Build.kernel$/ { on = 1 } on { print } on && /^endef$/ { exit }' "$out" >"$block"
[ -s "$block" ] || fail "no define Device/Build/kernel block in the dump"

cnt_rule=$(grep -cF '$$(KDIR_KERNEL_IMAGE):' "$block" || true)
cnt_concat=$(grep -cF '$$(call concat_cmd,$$(KERNEL))' "$block" || true)
cnt_appended=$(grep -cF '$$(call Build/check-size,$$(KERNEL_SIZE))' "$block" || true)
cnt_emptyapp=$(grep -cF 'check-size,$$()' "$block" || true)
[ "$cnt_rule" -eq 1 ] ||
	fail "kernel.bin rule count = $cnt_rule (want 1) in Device/Build/kernel"
[ "$cnt_concat" -eq 1 ] ||
	fail "pipeline concat_cmd call count = $cnt_concat (want 1) in Device/Build/kernel"
[ "$cnt_appended" -eq 1 ] ||
	fail "appended check-size call count = $cnt_appended (want 1) in Device/Build/kernel"
[ "$cnt_emptyapp" -eq 0 ] ||
	fail "appended check-size call has an empty argument"

printf 'check-e2631-image-expansion: OK - pipeline check-size 4096k, %s non-empty invocations in the kernel.bin recipe, make parsed cleanly\n' \
	"$((cnt_concat + cnt_appended))"
