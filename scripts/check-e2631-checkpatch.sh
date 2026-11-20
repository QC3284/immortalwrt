#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# check-e2631-checkpatch.sh - plan C per-commit checkpatch gate.
#
# Every non-merge commit between the pinned ImmortalWrt base (E2631_IW_SHA)
# and HEAD is checked with the in-tree scripts/checkpatch.pl. A commit must be
# clean (no ERROR/WARNING) after two filters:
#
#   1. the documented exemptions in docs/checkpatch-exemptions.md, matched by
#      path glob x checkpatch type - never a global --ignore, so the same type
#      is still reported everywhere else;
#   2. the gate scope: target/linux/zx279128/** (patches and *.patch excluded)
#      plus package/e2631/**. Findings outside that scope belong to the
#      upstream base or to other targets and are counted, not failed.
#
# Commit-message findings (no FILE context, e.g. MISSING_SIGN_OFF) are always
# in scope; only an explicit commit:<sha> exemption can excuse one.
#
# Run from the repository root:
#
#   E2631_IW_SHA=<sha> bash scripts/check-e2631-checkpatch.sh
#
set -u

base=${E2631_IW_SHA:-}
if [ -z "$base" ]; then
	echo "check-e2631-checkpatch: E2631_IW_SHA is not set" >&2
	exit 2
fi

checkpatch=scripts/checkpatch.pl
exemption_doc=docs/checkpatch-exemptions.md

for f in "$checkpatch" "$exemption_doc"; do
	if [ ! -f "$f" ]; then
		echo "check-e2631-checkpatch: missing $f" >&2
		exit 2
	fi
done

git cat-file -e "${base}^{commit}" 2>/dev/null || {
	echo "check-e2631-checkpatch: pinned base $base is not in this checkout (fetch full history)" >&2
	exit 1
}
git merge-base --is-ancestor "$base" HEAD || {
	echo "check-e2631-checkpatch: pinned base $base is not an ancestor of HEAD" >&2
	exit 1
}

# ---- exemption table: docs/checkpatch-exemptions.md is the single source ----
exempt_pattern=()
exempt_types=()
while IFS='|' read -r pattern types; do
	pattern=${pattern#"${pattern%%[![:space:]]*}"}
	pattern=${pattern%"${pattern##*[![:space:]]}"}
	types=${types#"${types%%[![:space:]]*}"}
	types=${types%"${types##*[![:space:]]}"}
	[ -n "$pattern" ] || continue
	exempt_pattern+=("$pattern")
	exempt_types+=("$types")
done < <(awk '
	/<!-- checkpatch-exemptions:begin -->/ { on = 1; next }
	/<!-- checkpatch-exemptions:end -->/   { on = 0; next }
	on && $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ { print }
' "$exemption_doc")

[ "${#exempt_pattern[@]}" -gt 0 ] || {
	echo "check-e2631-checkpatch: no machine-readable exemptions found in $exemption_doc" >&2
	exit 2
}

# A type list is 'TYPE[,TYPE...]'; '*' exempts every type.
type_listed() {
	local type=$1 list=$2
	case "$list" in
	\*) return 0 ;;
	esac
	case ",$list," in
	*",$type,"*) return 0 ;;
	esac
	return 1
}

# is_exempt <type> <file> <sha>
is_exempt() {
	local type=$1 file=$2 sha=$3 i pattern
	for i in "${!exempt_pattern[@]}"; do
		pattern=${exempt_pattern[$i]}
		case "$pattern" in
		commit:*)
			[ "$file" = '<commit-message>' ] || continue
			[ "$pattern" = "commit:$sha" ] || continue
			;;
		*)
			[ "$file" = '<commit-message>' ] && continue
			# shellcheck disable=SC2254
			case "$file" in
			$pattern) ;;
			*) continue ;;
			esac
			;;
		esac
		type_listed "$type" "${exempt_types[$i]}" && return 0
	done
	return 1
}

# in_scope <file>
in_scope() {
	case "$1" in
	'<commit-message>') return 0 ;;
	target/linux/zx279128/patches-*/*) return 1 ;;
	target/linux/zx279128/*.patch) return 1 ;;
	target/linux/zx279128/*) return 0 ;;
	package/e2631/*) return 0 ;;
	esac
	return 1
}

# checkpatch report -> 'TYPE<TAB>FILE<TAB>LINE<TAB>MESSAGE' records; a finding
# without a FILE context line is a commit-message finding.
parse_report() {
	awk '
	/^(ERROR|WARNING):/ {
		if (pending) print pending_type "\t<commit-message>\t0\t" pending_msg
		s = $0
		sub(/^(ERROR|WARNING):/, "", s)
		pending_type = s
		sub(/:.*/, "", pending_type)
		pending_msg = s
		sub(/^[A-Z_]+: /, "", pending_msg)
		pending = 1
		next
	}
	/^#[0-9]+: FILE: / {
		p = $0
		sub(/^#[0-9]+: FILE: /, "", p)
		n = p
		sub(/:[0-9]+:$/, "", n)
		line = p
		sub(/^.*:/, "", line)
		sub(/:$/, "", line)
		if (pending) {
			print pending_type "\t" n "\t" line "\t" pending_msg
			pending = 0
		}
		next
	}
	END { if (pending) print pending_type "\t<commit-message>\t0\t" pending_msg }
	'
}

# ---- run the gate, one checkpatch invocation per commit --------------------
count=0
total=0
exempted=0
outside=0
failed=0

for sha in $(git rev-list --no-merges "$base"..HEAD); do
	count=$((count + 1))
	subject=$(git log -1 --format=%s "$sha")
	report=$(mktemp)
	perl "$checkpatch" --no-tree --show-types -g "$sha" >"$report" 2>&1
	rc=$?
	if [ "$rc" -gt 1 ]; then
		echo "check-e2631-checkpatch: checkpatch failed on ${sha:0:12} ($subject)" >&2
		sed 's/^/    /' "$report" >&2
		rm -f "$report"
		exit 2
	fi
	found=0
	while IFS=$'\t' read -r type file line msg; do
		[ -n "$type" ] || continue
		total=$((total + 1))
		if is_exempt "$type" "$file" "$sha"; then
			exempted=$((exempted + 1))
			continue
		fi
		if ! in_scope "$file"; then
			outside=$((outside + 1))
			continue
		fi
		found=$((found + 1))
		failed=$((failed + 1))
		if [ "$file" = '<commit-message>' ]; then
			echo "::error title=checkpatch (${sha:0:12})::${type}: ${msg}"
		else
			echo "::error file=${file},line=${line}::${type}: ${msg}"
		fi
	done < <(parse_report < "$report")
	if [ "$found" -gt 0 ]; then
		echo "FAIL ${sha:0:12} ${subject}: ${found} in-scope checkpatch finding(s)" >&2
	fi
	rm -f "$report"
done

echo "check-e2631-checkpatch: ${count} commit(s), ${total} finding(s): ${exempted} exempted, ${outside} outside the gate scope, ${failed} in scope"
if [ "$failed" -ne 0 ]; then
	echo "check-e2631-checkpatch: FAIL - fix the findings or add a documented exemption" >&2
	exit 1
fi
echo "check-e2631-checkpatch: OK"
