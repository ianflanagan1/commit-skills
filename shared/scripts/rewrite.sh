#!/bin/sh
# rewrite: rework the commits since a base from a plan, built in memory, then move HEAD to them.
#
# Only apply touches HEAD, the index or the working tree; list, piece and run just read and write
# objects, so a plan that stops leaves everything as it was.
#
# Usage:
#   rewrite.sh list <from> <path>                           number the changed lines of path in from
#   rewrite.sh piece <from> <path> <ids> [<path> <ids>]...  make a piece of those lines; print its hash
#   rewrite.sh run <base> <plan>                            build the plan on base; print the commits
#   rewrite.sh apply <start> <new>                          move HEAD from start to new
#
#   from   - for uncommitted work, numbered against HEAD; or a commit, numbered against its parent
#   path   from the repository's root
#   ids    as stage-lines.sh takes them, joined with commas (3-7,12), or all for the whole file
#
# A piece is a commit of just those lines on top of what they are numbered against, so run can
# apply it anywhere with a three-way merge. A piece of a commit also records that commit with the
# lines taken out, a second way to apply it that still merges where the first conflicts, such as
# lines of a file the commit creates.
#
# The plan has one operation per line, run top to bottom; blank lines and # comments are ignored.
# Every commit since the base appears exactly once, as pick, fixup or drop.
#   pick <commit>    add a commit with this commit's or piece's change; a commit since the base
#                    keeps its message and author, and its hash while nothing before it changed
#   fixup <commit>   fold this commit's or piece's change into the commit before
#   remove <piece>   take the piece's change back out of the commit before
#   drop <commit>    leave out a commit since the base
#   message <file>   replace the message of the commit before; every picked piece needs one
#
# run prints the resulting commits oldest first, each as "kept" or "new" with its short hash and
# subject, then "HEAD <hash>". apply checks that HEAD is still start, then moves HEAD and the
# index to new without touching the working tree, so what the plan left out of the commits
# (dropped and removed changes, unused work) shows as uncommitted.
#
# Exit status: 0 done, 1 no changes to list, 2 usage error or invalid plan, 3 a conflict, an
# empty commit or a selection that cannot be made.

set -eu

usage() {
    sed -n '7,15p' "$0" | sed 's/^# \{0,1\}//'
}

# die status message: print the message and exit with the status.
die() {
    echo "$2" >&2
    exit "$1"
}

here=$(cd "$(dirname "$0")" && pwd)
caller=$PWD
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 2 'Not a git work tree'
git rev-parse -q --verify HEAD >/dev/null || die 2 'No commits yet'
cd "$(git rev-parse --show-toplevel)"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rewrite.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
piece_message='rewrite.sh piece'

# commit_of rev: the full hash of the commit rev names, or exit 2.
commit_of() {
    git rev-parse -q --verify "$1^{commit}" || die 2 "Not a commit: $1"
}

# tree_of commit: the commit's tree.
tree_of() {
    git rev-parse "$1^{tree}"
}

# from_arg from: - as it is, or the full hash of the commit.
from_arg() {
    if [ "$1" = - ]; then echo -; else commit_of "$1"; fi
}

# numbered_against from: the commit that from's lines are numbered against.
numbered_against() {
    if [ "$1" = - ]; then
        git rev-parse HEAD
    else
        git rev-parse -q --verify "$1^" || die 2 "$1 has no parent"
    fi
}

# use_index_of commit: point git at a fresh index holding the commit's tree.
use_index_of() {
    GIT_INDEX_FILE=$tmp/index
    export GIT_INDEX_FILE
    rm -f "$GIT_INDEX_FILE"
    git read-tree "$1"
}

# --- list and piece

cmd_list() {
    [ $# -eq 2 ] || { usage >&2; exit 2; }
    from=$(from_arg "$1")
    use_index_of "$(numbered_against "$from")"
    if [ "$from" = - ]; then
        sh "$here/stage-lines.sh" "$2"
    else
        sh "$here/stage-lines.sh" -r "$from" "$2"
    fi
}

# take_whole from path: stage the whole file as it is in from, or its deletion.
take_whole() {
    if [ "$1" = - ]; then
        if [ -e "$2" ] || [ -L "$2" ]; then
            git add -- "$2"
        else
            git rm --cached --quiet -- "$2"
        fi
    else
        entry=$(git ls-tree "$1" -- "$2")
        if [ -n "$entry" ]; then
            printf '%s\n' "$entry" | git update-index --add --index-info
        else
            git update-index --force-remove -- "$2"
        fi
    fi
}

# complement count ids: the numbers from 1 to count that the comma-separated ids leave out,
# joined with commas.
complement() {
    awk -v n="$1" -v ids="$2" 'BEGIN {
        k = split(ids, a, ",")
        for (i = 1; i <= k; i++) {
            m = split(a[i], r, "-")
            for (j = r[1]; j <= (m == 2 ? r[2] : r[1]); j++) want[j] = 1
        }
        for (j = 1; j <= n; j++) if (!(j in want)) out = out (out == "" ? "" : ",") j
        print out
    }'
}

cmd_piece() {
    [ $# -ge 3 ] && [ $(($# % 2)) -eq 1 ] || { usage >&2; exit 2; }
    from=$(from_arg "$1")
    shift
    : >"$tmp/selection"
    while [ $# -gt 0 ]; do
        printf '%s\n%s\n' "$1" "$2" >>"$tmp/selection"
        shift 2
    done
    parent=$(numbered_against "$from")

    # The lines on top of what they are numbered against.
    use_index_of "$parent"
    while IFS= read -r path && IFS= read -r ids; do
        if [ "$ids" = all ]; then
            take_whole "$from" "$path"
        elif [ "$from" = - ]; then
            sh "$here/stage-lines.sh" "$path" "$ids" >/dev/null
        else
            sh "$here/stage-lines.sh" -r "$from" "$path" "$ids" >/dev/null
        fi </dev/null
    done <"$tmp/selection"
    tree=$(git write-tree)
    [ "$tree" != "$(tree_of "$parent")" ] || die 3 'The piece changes nothing'
    if [ "$from" = - ]; then
        echo "$piece_message" | git commit-tree "$tree" -p "$parent"
        return
    fi

    # The commit with the lines taken out: each chosen file as it was before, plus the lines of
    # the commit's change that were not chosen.
    use_index_of "$from"
    while IFS= read -r path && IFS= read -r ids; do
        take_whole "$parent" "$path"
        [ "$ids" != all ] || continue
        GIT_INDEX_FILE=$tmp/index.listing
        git read-tree "$parent"
        count=$(sh "$here/stage-lines.sh" -r "$from" "$path" | grep -c '^ *[0-9][0-9]* [-+]')
        GIT_INDEX_FILE=$tmp/index
        rest=$(complement "$count" "$ids")
        [ -z "$rest" ] || sh "$here/stage-lines.sh" -r "$from" "$path" "$rest" >/dev/null
    done <"$tmp/selection"
    after=$(echo 'rewrite.sh piece taken out' | git commit-tree "$(git write-tree)" -p "$from")
    printf '%s\n\nafter %s\n' "$piece_message" "$after" | git commit-tree "$tree" -p "$parent"
}

# --- run

# bad line message: reject the plan.
bad() {
    die 2 "plan line $1: $2"
}

# stop line message: stop building.
stop() {
    die 3 "plan line $1: $2"
}

is_original() {
    grep -qx "$1" "$tmp/originals"
}

# is_piece commit: whether the commit is a piece numbered against HEAD or a commit since the base.
is_piece() {
    [ "$(git cat-file commit "$1" | sed '1,/^$/d' | head -n 1)" = "$piece_message" ] &&
        grep -qx "$(git rev-parse -q --verify "$1^" || echo none)" "$tmp/parents"
}

# after_of piece: the piece's commit with its lines taken out, if it is a piece of a commit.
after_of() {
    git cat-file commit "$1" | sed '1,/^$/d' | sed -n 's/^after //p'
}

# check_plan plan: validate the plan and write it to $tmp/ops as "line op argument", with
# commits as full hashes and message files as absolute paths.
check_plan() {
    n=0 have=0 needs=0
    : >"$tmp/ops"
    : >"$tmp/seen"
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case $line in '' | '#'*) continue ;; esac
        op=${line%%[[:space:]]*}
        arg=$(printf '%s\n' "${line#"$op"}" | sed 's/^[[:space:]]*//')
        [ -n "$arg" ] || bad "$n" "$op needs an argument"
        case $op in
            pick | fixup | remove | drop)
                arg=$(git rev-parse -q --verify "$arg^{commit}") || bad "$n" "not a commit: $arg"
                if is_original "$arg"; then
                    [ "$op" != remove ] || bad "$n" 'remove takes a piece; to leave a whole commit out, drop it'
                    echo "$arg" >>"$tmp/seen"
                else
                    is_piece "$arg" || bad "$n" "$(git rev-parse --short "$arg") is neither a commit since the base nor a piece"
                    [ "$op" != drop ] || bad "$n" 'drop takes a commit since the base; to leave out a piece, leave it out of the plan'
                    [ "$op" != remove ] || [ -n "$(after_of "$arg")" ] ||
                        bad "$n" 'remove takes a piece of a commit; uncommitted work is not in any commit'
                fi
                case $op in
                    pick)
                        [ "$needs" -eq 0 ] || bad "$needs" 'a picked piece needs a message on the next line'
                        have=1
                        is_original "$arg" || needs=$n
                        ;;
                    fixup | remove)
                        [ "$have" -eq 1 ] || bad "$n" "$op needs a commit before it"
                        ;;
                esac
                ;;
            message)
                [ "$have" -eq 1 ] || bad "$n" 'message needs a commit before it'
                case $arg in /*) ;; *) arg=$caller/$arg ;; esac
                [ -s "$arg" ] || bad "$n" "no such message file, or it is empty: $arg"
                needs=0
                ;;
            *) bad "$n" "unknown operation: $op" ;;
        esac
        printf '%s %s %s\n' "$n" "$op" "$arg" >>"$tmp/ops"
    done <"$1"
    [ "$needs" -eq 0 ] || bad "$needs" 'a picked piece needs a message on the next line'
    while read -r c; do
        count=$(grep -cx "$c" "$tmp/seen" || true)
        [ "$count" -eq 1 ] ||
            die 2 "plan: $(git rev-parse --short "$c") appears $count times; every commit since the base appears once, as pick, fixup or drop"
    done <"$tmp/originals"
}

# try_merge base theirs: print the tree of cur merged three ways with theirs, or write the
# conflicting paths to $tmp/conflict and fail.
try_merge() {
    status=0
    out=$(git merge-tree --write-tree --name-only --no-messages --merge-base="$1" "$cur" "$2") || status=$?
    case $status in
        0) printf '%s\n' "$out" | head -n 1 ;;
        1)
            printf '%s\n' "$out" | sed '1d; /^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//' >"$tmp/conflict"
            return 1
            ;;
        *) exit 2 ;;
    esac
}

# with_change line commit: print the tree of cur with the commit's or piece's change added.
with_change() {
    if tree=$(try_merge "$2^" "$2"); then echo "$tree"; return; fi
    mv "$tmp/conflict" "$tmp/conflict.first"
    after=$(after_of "$2")
    if [ -n "$after" ] && tree=$(try_merge "$after" "$after^"); then echo "$tree"; return; fi
    stop "$1" "conflict in: $(cat "$tmp/conflict.first")"
}

# without_piece line piece: print the tree of cur with the piece's change taken out.
without_piece() {
    after=$(after_of "$2")
    if tree=$(try_merge "$after^" "$after"); then echo "$tree"; return; fi
    mv "$tmp/conflict" "$tmp/conflict.first"
    if tree=$(try_merge "$2" "$2^"); then echo "$tree"; return; fi
    stop "$1" "conflict in: $(cat "$tmp/conflict.first")"
}

# commit_as commit tree parent message-file: print a new commit of the tree on the parent, with
# the message in the file, authored as the commit was.
commit_as() {
    GIT_AUTHOR_NAME=$(git log -1 --format=%an "$1") \
        GIT_AUTHOR_EMAIL=$(git log -1 --format=%ae "$1") \
        GIT_AUTHOR_DATE=$(git log -1 --format=%ad --date=raw "$1") \
        git commit-tree "$2" -p "$3" -F "$4"
}

# message_of commit: write the commit's message to a file and print the file's path.
message_of() {
    git cat-file commit "$1" | sed '1,/^$/d' >"$tmp/message"
    echo "$tmp/message"
}

# amend line tree: replace cur with a commit of the tree on cur's parent, keeping cur's message
# and author.
amend() {
    parent=$(git rev-parse "$cur^")
    [ "$2" != "$(tree_of "$parent")" ] || stop "$1" 'the commit before would be empty; drop it instead'
    [ "$2" != "$(tree_of "$cur")" ] || stop "$1" 'changes nothing in the commit before'
    cur=$(commit_as "$cur" "$2" "$parent" "$(message_of "$cur")")
}

cmd_run() {
    [ $# -eq 2 ] || { usage >&2; exit 2; }
    base=$(commit_of "$1")
    case $2 in /*) plan=$2 ;; *) plan=$caller/$2 ;; esac
    [ -f "$plan" ] || die 2 "No such plan: $2"
    start=$(git rev-parse HEAD)
    git merge-base --is-ancestor "$base" "$start" || die 2 "$1 is not an ancestor of HEAD"
    [ "$(git rev-list --count --merges "$base..$start")" -eq 0 ] || die 2 'The commits since the base include merges'
    git rev-list --reverse "$base..$start" >"$tmp/originals"
    { echo "$start"; while read -r c; do git rev-parse "$c^"; done <"$tmp/originals"; } >"$tmp/parents"

    check_plan "$plan"

    cur=$base
    while read -r n op arg; do
        case $op in
            pick)
                if is_original "$arg" && [ "$(git rev-parse "$arg^")" = "$cur" ]; then
                    cur=$arg
                    continue
                fi
                tree=$(with_change "$n" "$arg")
                [ "$tree" != "$(tree_of "$cur")" ] || stop "$n" 'the commit would be empty'
                if is_original "$arg"; then
                    cur=$(commit_as "$arg" "$tree" "$cur" "$(message_of "$arg")")
                else
                    cur=$(echo "$piece_message" | git commit-tree "$tree" -p "$cur")
                fi
                ;;
            fixup)
                tree=$(with_change "$n" "$arg")
                amend "$n" "$tree"
                ;;
            remove)
                tree=$(without_piece "$n" "$arg")
                amend "$n" "$tree"
                ;;
            message) cur=$(commit_as "$cur" "$(tree_of "$cur")" "$(git rev-parse "$cur^")" "$arg") ;;
            drop) ;;
        esac
    done <"$tmp/ops"

    git rev-list --reverse "$base..$cur" | while read -r c; do
        if is_original "$c"; then kind=kept; else kind=new; fi
        echo "$kind $(git log -1 --format='%h %s' "$c")"
    done
    echo "HEAD $cur"
}

# --- apply

cmd_apply() {
    [ $# -eq 2 ] || { usage >&2; exit 2; }
    start=$(commit_of "$1")
    new=$(commit_of "$2")
    [ "$(git rev-parse HEAD)" = "$start" ] || die 2 'HEAD has moved since the plan was built; build it again'
    git_dir=$(git rev-parse --git-dir)
    for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
        [ ! -e "$git_dir/$f" ] || die 2 'A merge, rebase, cherry-pick or revert is in progress'
    done
    git reset --quiet "$new"
    git log -1 --format='HEAD %h %s'
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
command=$1
shift
case $command in
    list) cmd_list "$@" ;;
    piece) cmd_piece "$@" ;;
    run) cmd_run "$@" ;;
    apply) cmd_apply "$@" ;;
    -h) usage ;;
    *) usage >&2; exit 2 ;;
esac
