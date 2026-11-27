#!/usr/bin/env bash
# files/pacemaker-drbd-wait against a stub drbdsetup: local disk only, every volume, one deadline over every
# resource, a late resource logged with exit 0, the -d filter. Needs no DRBD and no root.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WAIT=$REPO/files/pacemaker-drbd-wait
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin" "$WORK/res"
export PATH="$WORK/bin:$PATH" STUB="$WORK"
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2], want [$3]" >&2; fails=$((fails + 1)); fi; }
check_le() { if [ "$2" -le "$3" ]; then echo "ok   $1 ($2 s)"; else echo "FAIL $1: $2 s, want <= $3" >&2; fails=$((fails + 1)); fi; }

# stub <script body>: drbdsetup status <res>, its argv checked, each call counted per resource in $STUB/calls
stub() {
  {
    cat <<'HEAD'
#!/bin/sh
[ $# = 2 ] && [ "$1" = status ] || { echo "drbdsetup: unexpected argv: $*" >&2; exit 2; }
echo "$2" >>"$STUB/calls"; n=$(grep -cx "$2" "$STUB/calls")
HEAD
    cat
  } >"$WORK/bin/drbdsetup"
  chmod +x "$WORK/bin/drbdsetup"
  rm -f "$WORK/calls"
}
# run <args>: output, then the seconds it took on the last line
run() { local s; s=$(date +%s); "$WAIT" "$@"; echo "rc=$?"; echo $(($(date +%s) - s)); }

stub <<'EOF'
echo "$2 role:Secondary"
if [ "$n" -ge 3 ]; then echo "  disk:UpToDate"; else echo "  disk:Inconsistent"; fi
echo "  peer role:Primary"
echo "    replication:SyncTarget peer-disk:UpToDate"
EOF
out=$(run 10 r0)
check "UpToDate on the 3rd poll: returns then, silent, exit 0" "$(sed -n '1,2p' <<<"$out" | tr '\n' ' ')" "rc=0 2 "
check "polled 3 times" "$(grep -c . "$WORK/calls")" 3

stub <<'EOF'
echo "$2 role:Secondary"
echo "  disk:Inconsistent"
echo "  peer role:Primary"
echo "    replication:Established peer-disk:UpToDate"
EOF
out=$(run 1 r0)
check "a peer's UpToDate disk never ends the wait" "$(head -2 <<<"$out" | tr '\n' ' ')" \
  "pacemaker-drbd-wait: r0: local disk not UpToDate after 1 s, starting pacemaker anyway rc=0 "

stub <<'EOF'
echo "$2 role:Secondary"
echo "  volume:0 disk:UpToDate"
if [ "$n" -ge 2 ]; then echo "  volume:1 disk:UpToDate"; else echo "  volume:1 disk:Inconsistent"; fi
EOF
out=$(run 10 r0)
check "two volumes: waits for the second" "$(head -1 <<<"$out")/$(grep -c . "$WORK/calls")" "rc=0/2"

stub <<'EOF'
echo "$2 role:Secondary"
echo "  disk:Diskless"
EOF
out=$(run 2 r0 r1 r2)
check "never UpToDate: each logged in order, exit 0" "$(head -4 <<<"$out" | sed 's/: local disk.*//' | tr '\n' ' ')" \
  "pacemaker-drbd-wait: r0 pacemaker-drbd-wait: r1 pacemaker-drbd-wait: r2 rc=0 "
check_le "one deadline over the three resources, not one each" "$(tail -1 <<<"$out")" 3

stub <<'EOF'
exit 10
EOF
out=$(run 1 r0)
check "an unknown resource (drbdsetup fails) is late, exit 0" "$(head -2 <<<"$out" | tail -1)" "rc=0"

stub <<'EOF'
echo "  disk:UpToDate"
EOF
touch "$WORK/res/r0.res"
out=$(run -d "$WORK/res" 5 r0 r1)
check "-d: a resource without its .res file is never polled" "$(sort -u "$WORK/calls" | tr '\n' ' ')/$(head -1 <<<"$out")" "r0 /rc=0"

out=$(run)
check "no argument: usage, exit 0" "$(head -2 <<<"$out" | sed 's/:.*//' | tr '\n' ' ')" "pacemaker-drbd-wait rc=0 "
out=$(run 9x r0)
check "a bad deadline: usage, exit 0" "$(sed -n 2p <<<"$out")" "rc=0"
out=$(run 5)
check "no resource: returns at once" "$(head -1 <<<"$out")/$(tail -1 <<<"$out")" "rc=0/0"

if [ "$fails" -gt 0 ]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
