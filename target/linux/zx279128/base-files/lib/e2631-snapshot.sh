#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Snapshot identity helpers for the E2631 userdata extroot.
#
# The 47 MiB "userdata" partition can be used as an extroot: once it carries a
# UBIFS with the overlayfs upper layer and fstab.e2631_extroot.enabled=1,
# fstools mounts it as the live /overlay on the NEXT boot (known-issues.md,
# USERDATA-EXTROOT-TAKEOVER).  That is only correct for a volume provisioned
# by the firmware generation that boots it - an older image's overlay (old
# wireless config, old dropbear host keys, ...) must never silently replace the
# current one.  The 2026-11-14 incident was exactly that: a v1.9.0-era
# snapshot came back after an upgrade.
#
# Every volume adopted by this firmware therefore gets a marker file in its
# overlay root:
#
#	<volume>/upper/etc/e2631-userdata-version	(extroot layout)
#	<volume>/etc/e2631-userdata-version		(plain layout fallback)
#
# holding this firmware's snapshot identity: DISTRIB_ID, DISTRIB_RELEASE and
# DISTRIB_REVISION from /etc/openwrt_release, plus the first line of
# /etc/e2631-version when the build installed one.  /lib/preinit/
# 79_e2631_userdata refuses a volume whose marker is missing or different
# BEFORE mount_root, which is the only point where that decision can still be
# enforced; /etc/init.d/e2631-userdata refuses to (re-)enable such a volume
# and turns the persisted fstab entry back off.
#
# POSIX sh.  Sourced by /lib/preinit/79_e2631_userdata,
# /etc/init.d/e2631-userdata and /sbin/e2631-userdata-init.  The two path
# variables may be overridden by a test harness; nothing else is tunable.

E2631_SNAPSHOT_MARKER=e2631-userdata-version

e2631_snapshot_id() {
	# Identity = DISTRIB_* from /etc/openwrt_release plus the first line of
	# /etc/e2631-version.  It must NEVER be empty: an empty identity is what
	# wrote a marker file holding a single newline on 2026-11-14, and the
	# next boot then refused the volume it had just adopted.  "unknown" plus
	# a failure status means "cannot tell"; callers must not write or accept
	# a marker in that case.
	snap_os_release=$E2631_OS_RELEASE
	[ -n "$snap_os_release" ] || snap_os_release=/etc/openwrt_release
	snap_version_file=$E2631_VERSION_FILE
	[ -n "$snap_version_file" ] || snap_version_file=/etc/e2631-version
	snap_id=""
	snap_release=""
	snap_revision=""
	if [ -r "$snap_os_release" ]; then
		snap_id=$(sed -n "s/^DISTRIB_ID='\(.*\)'$/\1/p" "$snap_os_release" | head -n 1)
		snap_release=$(sed -n "s/^DISTRIB_RELEASE='\(.*\)'$/\1/p" \
			"$snap_os_release" | head -n 1)
		snap_revision=$(sed -n "s/^DISTRIB_REVISION='\(.*\)'$/\1/p" \
			"$snap_os_release" | head -n 1)
	fi
	snap_extra=""
	if [ -r "$snap_version_file" ]; then
		snap_extra=$(head -n 1 "$snap_version_file")
	fi
	if [ -z "$snap_id$snap_release$snap_revision$snap_extra" ]; then
		# never invent an identity: "unknown" must not match a marker
		echo unknown
		return 1
	fi
	[ -n "$snap_id" ] || snap_id='?'
	[ -n "$snap_release" ] || snap_release='?'
	[ -n "$snap_revision" ] || snap_revision='?'
	snap_out=$(printf '%s %s %s' "$snap_id" "$snap_release" "$snap_revision")
	if [ -n "$snap_extra" ]; then
		snap_out="$snap_out $snap_extra"
	fi
	# Belt and braces: a sed/head pipeline can return nothing while the file
	# is readable (unexpected quoting, an empty release file, a future build
	# without one of the keys).  Never let that escape as an empty identity.
	case "$snap_out" in
	*[![:space:]]*) ;;
	*)
		echo unknown
		return 1
		;;
	esac
	printf '%s\n' "$snap_out"
}

e2631_read_marker() {
	read_root=$1
	[ -n "$read_root" ] || return 1
	for read_path in "$read_root/upper/etc/$E2631_SNAPSHOT_MARKER" \
		"$read_root/etc/$E2631_SNAPSHOT_MARKER"; do
		if [ -r "$read_path" ]; then
			head -n 1 "$read_path"
			return 0
		fi
	done
	return 0
}

e2631_write_marker() {
	write_root=$1
	[ -n "$write_root" ] || return 1
	write_want=$(e2631_snapshot_id) || return 1
	# An empty identity is as unusable as "unknown": writing it used to
	# produce a marker file containing one newline (2026-11-14).
	[ -n "$write_want" ] && [ "$write_want" != "unknown" ] || return 1
	write_dir=$write_root/etc
	[ -d "$write_root/upper" ] && write_dir=$write_root/upper/etc
	mkdir -p "$write_dir" || return 1
	printf '%s\n' "$write_want" > "$write_dir/$E2631_SNAPSHOT_MARKER"
}

# shellcheck disable=SC2034  # E2631_MARKER_HAVE/WANT are consumed by callers
e2631_marker_state() {
	marker_root=$1
	# An unavailable identity must never accept a volume: treat it as stale.
	E2631_MARKER_WANT=$(e2631_snapshot_id) || :
	E2631_MARKER_HAVE=$(e2631_read_marker "$marker_root")
	if [ -z "$E2631_MARKER_HAVE" ]; then
		echo missing
	elif [ "$E2631_MARKER_HAVE" = "$E2631_MARKER_WANT" ]; then
		echo ok
	else
		echo stale
	fi
}
