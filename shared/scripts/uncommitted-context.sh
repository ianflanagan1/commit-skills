#!/bin/sh
# uncommitted-context: print what is needed to split uncommitted work into commits.
#
# Prints, in order:
#   - recent commit subjects, so messages can match the repository's style
#   - any merge, rebase, cherry-pick or revert in progress, and a detached HEAD
#   - the status of every changed and untracked file
#   - the diff of every changed and untracked file against HEAD, with changed lines numbered
#     as stage-lines.sh numbers them, without lockfiles and minified files, truncated after a
#     line limit
#
# Usage: uncommitted-context.sh [-n lines]
#   -n lines  maximum diff lines to print (default: 3000)
#
# Exit status: 0 changes printed, 1 nothing to commit, 2 usage error or not a git work tree.

set -o errexit -o nounset

usage() {
    sed -n '12,13p' "$0" | sed 's/^# \{0,1\}//'
}

max=3000
while getopts 'n:h' opt; do
    case $opt in
        n) max=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || { usage >&2; exit 2; }
case $max in
    '' | *[!0-9]*) usage >&2; exit 2 ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'Not a git work tree' >&2; exit 2; }
[ -n "$(git status --porcelain --untracked-files=all)" ] || { echo 'Nothing to commit' >&2; exit 1; }

echo '## Recent commits'
if git rev-parse --verify --quiet HEAD >/dev/null; then
    base=HEAD
    git log --max-count 15 --no-merges --format='%s'
else
    base=$(git hash-object -t tree /dev/null)
    echo '(none: the first commit is still to be made)'
fi
git_dir=$(git rev-parse --git-dir)
[ ! -f "$git_dir/MERGE_HEAD" ] || echo '(a merge is in progress)'
[ ! -d "$git_dir/rebase-merge" ] && [ ! -d "$git_dir/rebase-apply" ] || echo '(a rebase is in progress)'
[ ! -f "$git_dir/CHERRY_PICK_HEAD" ] || echo '(a cherry-pick is in progress)'
[ ! -f "$git_dir/REVERT_HEAD" ] || echo '(a revert is in progress)'
git symbolic-ref --quiet HEAD >/dev/null || echo '(detached HEAD: new commits will be on no branch)'

echo
echo '## Status (X = staged, Y = unstaged, ?? = untracked)'
git status --short --untracked-files=all

echo
echo '## Changes against HEAD, changed lines numbered (lockfiles and minified files omitted)'
here=$(cd "$(dirname "$0")" && pwd)
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
        END { if (NR > max) printf "[truncated: %d of %d lines shown; run stage-lines.sh <path> for the rest]\n", max, NR }'
