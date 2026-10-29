#!/bin/sh
# staged-context: print what is needed to write a commit message for the staged changes.
#
# Prints, in order:
#   - recent commit subjects, so the message can match the repository's style
#   - a merge in progress, and a detached HEAD
#   - the staged files, with change counts, renames, creations and deletions
#   - the staged diff, without lockfiles and minified files, truncated after a line limit
#
# Usage: staged-context.sh [-n lines]
#   -n lines  maximum diff lines to print (default: 2000)
#
# Exit status: 0 staged changes printed, 1 nothing staged, 2 usage error or not a git work tree.

set -o errexit -o nounset

usage() {
    sed -n '10,11p' "$0" | sed 's/^# \{0,1\}//'
}

max=2000
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
git diff --cached --quiet && { echo 'Nothing staged' >&2; exit 1; }

echo '## Recent commits'
if git rev-parse --verify --quiet HEAD >/dev/null; then
    git log --max-count 15 --no-merges --format='%s'
else
    echo '(none: this will be the first commit)'
fi
git_dir=$(git rev-parse --git-dir)
[ ! -f "$git_dir/MERGE_HEAD" ] || echo '(a merge is in progress)'
git symbolic-ref --quiet HEAD >/dev/null || echo '(detached HEAD: the commit will be on no branch)'

echo
echo '## Staged files'
git diff --cached --no-color --find-renames --stat=200 --summary

echo
echo '## Staged diff (lockfiles and minified files omitted)'
git diff --cached --no-color --no-ext-diff --find-renames -- . \
    ':(exclude)*.lock' ':(exclude)*-lock.json' ':(exclude)*-lock.yaml' ':(exclude)*go.sum' \
    ':(exclude)*.min.js' ':(exclude)*.min.css' ':(exclude)*.map' \
    | awk -v max="$max" '
        NR <= max
        END { if (NR > max) printf "[truncated: %d of %d lines shown; run git diff --cached -- <path> for the rest]\n", max, NR }'
