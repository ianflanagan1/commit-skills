#!/bin/sh
# amend-context: print what is needed to amend the commits since the base, on a branch or a
# detached HEAD, and the uncommitted work with each hunk traced to the commits that last changed
# its lines.
#
# The base is found as branch-base.sh describes: where the work started, past any commits
# already on a remote unless the base is given.
#
# Usage: amend-context.sh [-n lines] [base]
#   -n lines  maximum diff lines to print (default: 3000)
#   base      the branch or commit the work started from
#
# Prints, in order:
#   - the base and how it was found
#   - warnings: an operation in progress, a detached HEAD and the branches that also hold its
#     commits, merge commits, commits by others, pushed commits, committed files that are now
#     ignored
#   - recent commit subjects before the base, so messages can match the repository's style
#   - the commits since the base, oldest first, with full messages and file stats
#   - the status of every changed and untracked file
#   - the uncommitted work against HEAD, changed lines numbered as `rewrite.sh list - <path>`
#     numbers them, each hunk followed by the commits since the base that last changed the lines
#     it removes or sits between, without lockfiles and minified files, truncated after a line
#     limit
#
# Exit status: 0 printed, 1 no commits since the base, 2 usage error, not a git work tree or no
# base.

set -eu

usage() {
    sed -n '9,11p' "$0" | sed 's/^# \{0,1\}//'
}

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=shared/scripts/branch-base.sh
. "$here/branch-base.sh"

max=3000
while getopts 'n:h' opt; do
    case $opt in
        n) max=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || { usage >&2; exit 2; }
case $max in
    '' | *[!0-9]*) usage >&2; exit 2 ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'Not a git work tree' >&2; exit 2; }
git rev-parse -q --verify HEAD >/dev/null || { echo 'No commits yet; use the commit skill' >&2; exit 2; }

find_base "$@"
total=$(git rev-list --count "$base..HEAD")
[ "$total" -gt 0 ] || { echo 'No commits since the base to amend' >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/amend-context.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
git rev-list "$base..HEAD" >"$tmp/since"

echo '## Base'
echo "$(git rev-parse --short "$base") $how"
echo "$total commits since the base"

echo
echo '## Warnings'
print_warnings "$base"

echo
echo '## Recent commits before the base'
git log -n 15 --no-merges --format='%s' "$base"

echo
echo '## Commits since the base, oldest first'
git log --reverse --no-color --stat=200 --format='### %h%n%B' "$base..HEAD"

echo
echo '## Status (X = staged, Y = unstaged, ?? = untracked)'
if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
    git status --short --untracked-files=all
else
    echo '(clean)'
fi

# owners path lines: the "last changed by" line for the given lines of path at HEAD, naming the
# commits since the base oldest first; nothing if none of the lines is at HEAD.
owners() {
    path=$1 wanted=$2
    length=$(git cat-file blob "HEAD:$path" 2>/dev/null | awk 'END { print NR }')
    set --
    for l in $wanted; do
        [ "$l" -lt 1 ] || [ "$l" -gt "$length" ] || set -- "$@" -L "$l,$l"
    done
    [ $# -gt 0 ] || return 0
    git blame -s -l "$@" HEAD -- "$path" | cut -d' ' -f1 | tr -d '^' | sort -u >"$tmp/blamed"
    named=$(git rev-list --reverse "$base..HEAD" | grep -Fx -f "$tmp/blamed" |
        while read -r c; do git rev-parse --short "$c"; done | tr '\n' ' ' | sed 's/ $//')
    before=
    ! grep -vqFx -f "$tmp/since" "$tmp/blamed" || before=1
    if [ -z "$named" ]; then
        echo '      last changed by: only commits before the base'
    elif [ -n "$before" ]; then
        echo "      last changed by: $named (and lines from before the base)"
    else
        echo "      last changed by: $named"
    fi
}

echo
echo '## Uncommitted changes against HEAD, changed lines numbered (lockfiles and minified files omitted)'
cd "$(git rev-parse --show-toplevel)"
{ git diff HEAD --name-only --no-renames; git ls-files --others --exclude-standard; } | sort -u |
    while IFS= read -r f; do
        case $f in
            *.lock | *-lock.json | *-lock.yaml | *go.sum | *.min.js | *.min.css | *.map)
                echo "(omitted: $f)"; continue ;;
        esac
        # After each hunk, a marker line "OWNERS <old line numbers>": the lines it removes and,
        # for lines it only adds, the lines on either side.
        sh "$here/rewrite.sh" list - "$f" 2>&1 | awk '
            function done_hunk() { if (inhunk) print "OWNERS" lines; lines = "" }
            /^@@ / {
                done_hunk(); inhunk = 1; removing = 0
                split($2, o, ","); old = substr(o[1], 2) + 0
                if (o[2] == "0") old++
                print; next
            }
            /^ *[0-9]+ -/ { lines = lines " " old; old++; removing = 1; print; next }
            /^ *[0-9]+ \+/ { if (!removing) lines = lines " " (old - 1) " " old; print; next }
            /^      \\/ { print; next }
            /^      / { old++; removing = 0; print; next }
            { print }
            END { done_hunk() }
        ' | while IFS= read -r line; do
            case $line in
                OWNERS*) owners "$f" "${line#OWNERS}" ;;
                *) printf '%s\n' "$line" ;;
            esac
        done || true
    done |
    awk -v max="$max" '
        NR <= max
        END { if (NR > max) printf "[truncated: %d of %d lines shown; run rewrite.sh list - <path> for the rest]\n", max, NR }'
