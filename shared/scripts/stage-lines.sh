#!/bin/sh
# stage-lines: list a file's changed lines with numbers, or stage only some of them.
#
# Without IDs, prints the diff of <path> with every changed line numbered.
# With IDs, stages only those changed lines into the index; the working tree is never touched.
# Numbers count changed lines in the file's diff against the index (or -b base) from 1, and stay
# valid until the file's index entry changes. Unselected '+' lines are dropped and unselected
# '-' lines are kept, so any selection gives a consistent file.
#
# Usage: stage-lines.sh [-b base] [-f file | -r rev] [-n] path [id...]
#   -b base  list against a commit instead of the index (listing only)
#   -f file  take the new content from file instead of the working tree copy of path
#   -r rev   take the new content from path as it is in commit rev (absent there: deleted)
#   -n       print the patch instead of staging it
#   id       a number, a range such as 3-7, or all; several may be given, also comma-separated
#
# Exit status: 0 listed or staged, 1 no changes, 2 usage error, 3 cannot stage this selection.

set -o errexit -o nounset

usage() {
    sed -n '10,15p' "$0" | sed 's/^# \{0,1\}//'
}

base=
from=
rev=
dry=
while getopts 'b:f:r:nh' opt; do
    case $opt in
        b) base=$OPTARG ;;
        f) from=$OPTARG ;;
        r) rev=$OPTARG ;;
        n) dry=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { usage >&2; exit 2; }
path=$1
shift
ids=$( [ $# -eq 0 ] || printf '%s ' "$@" | tr ',' ' ')
case $ids in
    *[!0-9\ a-l-]*) usage >&2; exit 2 ;;
esac
[ -z "$base" ] || [ -z "$ids" ] || { echo '-b is for listing only; staging is always against the index' >&2; exit 2; }
[ -z "$from" ] || [ -z "$rev" ] || { usage >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'Not a git work tree' >&2; exit 2; }
case $from in
    '' | /*) ;;
    *) from=$PWD/$from ;;
esac
path=$(git rev-parse --show-prefix)$path
cd "$(git rev-parse --show-toplevel)"

tmp=$(mktemp --directory "${TMPDIR:-/tmp}/stage-lines.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Old side: the index entry, or the file at -b base; /dev/null if there is none.
old=/dev/null
if [ -n "$base" ]; then
    if git cat-file -e "$base:$path" 2>/dev/null; then
        git cat-file blob "$base:$path" >"$tmp/old"
        old=$tmp/old
    fi
elif git cat-file -e ":$path" 2>/dev/null; then
    git cat-file blob ":$path" >"$tmp/old"
    old=$tmp/old
fi

# New side: -f file, -r rev, or the working tree copy; /dev/null if it was deleted.
new=${from:-$path}
mode=
if [ -n "$rev" ]; then
    git rev-parse --quiet --verify "$rev^{commit}" >/dev/null || { echo "Not a commit: $rev" >&2; exit 2; }
    new=/dev/null
    if git cat-file -e "$rev:$path" 2>/dev/null; then
        git cat-file blob "$rev:$path" >"$tmp/new"
        new=$tmp/new
        mode=$(git ls-tree "$rev" -- "$path" | cut -c1-6)
    fi
elif [ ! -e "$new" ]; then
    [ -z "$from" ] || { echo "No such file: $from" >&2; exit 2; }
    new=/dev/null
fi
[ "$old$new" != /dev/null/dev/null ] || { echo "No such file in the index or working tree: $path" >&2; exit 2; }

status=0
git diff --no-index --no-color --no-ext-diff --no-renames -- "$old" "$new" >"$tmp/diff" || status=$?
[ "$status" -le 1 ] || exit 2
[ "$status" -eq 1 ] || { echo "No changes in $path" >&2; exit 1; }

# Rewrite the header to name the real path. Drop index and mode lines: the index keeps its
# mode, and a new file takes the mode of its new content.
# shellcheck disable=SC2016
awk -v p="$path" -v ids="$ids" -v list="$([ -z "$ids" ] && echo 1)" '
    function sel(n) { return all || (n in want) }
    BEGIN {
        k = split(ids, a, " ")
        for (i = 1; i <= k; i++) {
            if (a[i] == "all") { all = 1; continue }
            if (a[i] !~ /^[0-9]+(-[0-9]+)?$/) { print "Bad id: " a[i] > "/dev/stderr"; bad = 2; exit }
            m = split(a[i], r, "-"); lo = r[1]; hi = (m == 2 ? r[2] : r[1])
            if (lo < 1 || hi < lo) { print "Bad id: " a[i] > "/dev/stderr"; bad = 2; exit }
            for (j = lo; j <= hi; j++) { want[j] = 1; if (j > maxid) maxid = j }
        }
    }
    !body {
        if (/^diff --git /) { print "diff --git a/" p " b/" p; next }
        if (/^(index|old mode|new mode) /) next
        if (/^deleted file mode /) deleted = 1
        if (/^Binary files /) { print "Binary file; stage the whole file with git add" > "/dev/stderr"; bad = 3; exit }
        if (/^--- /) { if (!list) print ($0 == "--- /dev/null" ? $0 : "--- a/" p); next }
        if (/^\+\+\+ /) { if (!list) print ($0 == "+++ /dev/null" ? $0 : "+++ b/" p); body = 1; next }
        print; next
    }
    list {
        if (/^[-+]/) printf "%5d %s\n", ++n, $0
        else if (/^@@/) print
        else printf "      %s\n", $0
        next
    }
    /^@@/ { flush(); hunk = $0; nl = 0; any = 0; prevkept = 1; next }
    /^-/ { ++n; if (sel(n)) { add($0); any = 1; ++picked } else add(" " substr($0, 2)); prevkept = 1; next }
    /^\+/ { ++n; if (sel(n)) { add($0); any = 1; ++picked; prevkept = 1 } else prevkept = 0; next }
    /^\\/ { if (prevkept) add($0); next }
    { add($0); prevkept = 1 }
    function add(s) { lines[++nl] = s }
    function flush(   i) {
        if (!any) return
        print hunk
        for (i = 1; i <= nl; i++) print lines[i]
    }
    END {
        if (bad) exit bad
        if (list) exit
        flush()
        if (maxid > n) { printf "No id %d: %s has %d changed lines\n", maxid, p, n > "/dev/stderr"; exit 3 }
        if (deleted && picked < n) { print "Partial deletion; stage the whole deletion with: all" > "/dev/stderr"; exit 3 }
        printf "%d %d\n", picked, n > "/dev/stderr"
    }
' "$tmp/diff" >"$tmp/out" 2>"$tmp/err" || { status=$?; cat "$tmp/err" >&2; exit "$status"; }

if [ -z "$ids" ]; then
    cat "$tmp/out"
elif [ -n "$dry" ]; then
    cat "$tmp/out"
else
    git apply --cached --recount --whitespace=nowarn "$tmp/out" || exit 3
    # A file new to the index takes the mode of the temporary copy; give it the commit's.
    [ "$mode" != 100755 ] || git update-index --chmod=+x -- "$path"
    read -r picked total <"$tmp/err"
    echo "Staged $picked of $total changed lines in $path"
fi
