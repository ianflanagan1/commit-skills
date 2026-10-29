#!/bin/sh
# check-commit: run a command on a commit in a throwaway worktree, to show it works on its own.
#
# The worktree holds the commit alone, without the working tree's later changes, and is removed
# afterwards whatever happens. A pass prints one line; a failure prints the command's output, its
# last 100 lines only, and then a line with its exit status.
#
# Usage: check-commit.sh rev command
#   rev      the commit to check, such as HEAD or a hash
#   command  run with sh -c at the worktree's root
#
# Exit status: 0 passed, 1 the command failed, 2 usage error or not a commit.

set -o errexit -o nounset

usage() {
    sed -n '8,10p' "$0" | sed 's/^# \{0,1\}//'
}

[ "${1:-}" != -h ] || { usage; exit 0; }
[ $# -eq 2 ] || { usage >&2; exit 2; }
rev=$1
command=$2
commit=$(git rev-parse --quiet --verify "$rev^{commit}") || { echo "Not a commit: $rev" >&2; exit 2; }
name=$(git log -1 --format='%h %s' "$commit")

tmp=$(mktemp --directory "${TMPDIR:-/tmp}/check-commit.XXXXXX")
trap 'git worktree remove --force "$tmp/tree" 2>/dev/null; rm -rf "$tmp"' EXIT
out=$tmp/out

git worktree add --quiet --detach "$tmp/tree" "$commit"
status=0
(cd "$tmp/tree" && sh -c "$command") >"$out" 2>&1 || status=$?

if [ "$status" -eq 0 ]; then
    echo "passed: $name"
    exit 0
fi
total=$(wc -l <"$out")
[ "$total" -le 100 ] || echo "[first $((total - 100)) lines not shown]"
tail -n 100 "$out"
echo "failed (exit $status): $name"
exit 1
