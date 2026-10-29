#!/bin/sh
# branch-context: print what is needed to rework the commits since the base and uncommitted
# work, on a branch or a detached HEAD.
#
# The base is found as branch-base.sh describes: where the work started, past any commits
# already on a remote unless the base is given.
#
# Usage: branch-context.sh [-n lines] [base]
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
#   - the diff of every file changed since the base, committed or not, with changed lines
#     numbered as stage-lines.sh numbers them once the index is reset to the base, without
#     lockfiles and minified files, truncated after a line limit
#
# Exit status: 0 printed, 1 nothing to rework, 2 usage error, not a git work tree or no base.

set -o errexit -o nounset

usage() {
    sed -n '8,10p' "$0" | sed 's/^# \{0,1\}//'
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
git rev-parse --quiet --verify HEAD >/dev/null || { echo 'No commits yet; use the commit skill' >&2; exit 2; }

find_base "$@"
dirty=$(git status --porcelain --untracked-files=all)
[ "$base" != "$(git rev-parse HEAD)" ] || [ -n "$dirty" ] || { echo 'Nothing to rework' >&2; exit 1; }
total=$(git rev-list --count "$base..HEAD")

echo '## Base'
echo "$(git rev-parse --short "$base") $how"
echo "$total commits since the base"

echo
echo '## Warnings'
print_warnings "$base"

echo
echo '## Recent commits before the base'
git log --max-count 15 --no-merges --format='%s' "$base"

echo
echo '## Commits since the base, oldest first'
if [ "$total" -eq 0 ]; then
    echo '(none)'
else
    git log --reverse --no-color --stat=200 --format='### %h%n%B' "$base..HEAD"
fi

echo
echo '## Status (X = staged, Y = unstaged, ?? = untracked)'
if [ -n "$dirty" ]; then git status --short --untracked-files=all; else echo '(clean)'; fi

echo
echo '## Changes since the base, changed lines numbered (lockfiles and minified files omitted)'
cd "$(git rev-parse --show-toplevel)"
{ git diff "$base" --name-only --no-renames; git ls-files --others --exclude-standard; } | sort --unique |
    while IFS= read -r f; do
        case $f in
            *.lock | *-lock.json | *-lock.yaml | *go.sum | *.min.js | *.min.css | *.map)
                echo "(omitted: $f)"; continue ;;
        esac
        sh "$here/stage-lines.sh" -b "$base" "$f" 2>&1 || true
    done |
    awk -v max="$max" '
        NR <= max
        END { if (NR > max) printf "[truncated: %d of %d lines shown; once the index is reset to the base, run stage-lines.sh <path> for the rest]\n", max, NR }'
