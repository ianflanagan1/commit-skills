#!/bin/sh
# history-versions: list earlier saved versions of a file since its last commit.
#
# Looks in Claude Code checkpoints (~/.claude/file-history) and the local history of VS Code,
# VS Code Insiders, VSCodium and Cursor. Lists, oldest first, each distinct version saved after
# the commit that last changed the file, leaving out versions identical to that commit or to the
# working tree. Each line: save time, source, lines added and removed against HEAD, snapshot path.
# Both stores are undocumented internal formats, so this is best-effort.
#
# Usage: history-versions.sh path
#
# Exit status: 0 versions listed, 1 none found, 2 usage error or not a git work tree.

set -o errexit -o nounset

[ $# -eq 1 ] && [ "$1" != -h ] || { sed -n '10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'Not a git work tree' >&2; exit 2; }
rel=$(git rev-parse --show-prefix)$1
top=$(git rev-parse --show-toplevel)
abs=$top/$rel
cd "$top"

# GNU forms first: GNU stat -f and date -r succeed with a different meaning.
mtime() { stat --format %Y "$1" 2>/dev/null || stat -f %m "$1"; }
stamp() { date --date "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$1" '+%Y-%m-%d %H:%M:%S'; }

since=$(git log -1 --format=%ct -- "$rel" 2>/dev/null || true)
since=${since:-0}

tmp=$(mktemp --directory "${TMPDIR:-/tmp}/history-versions.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
head=/dev/null
if git cat-file -e "HEAD:$rel" 2>/dev/null; then
    git cat-file blob "HEAD:$rel" >"$tmp/head"
    head=$tmp/head
fi

# Candidates as "epoch<TAB>source<TAB>snapshot path".
: >"$tmp/cand"

# Claude Code: <session>/<first 16 hex of sha256(absolute path)>@v<n>
key=$(printf %s "$abs" | { shasum --algorithm 256 2>/dev/null || sha256sum; } | cut -c1-16)
for f in "$HOME"/.claude/file-history/*/"$key"@v*; do
    [ -f "$f" ] || continue
    printf '%s\tclaude\t%s\n' "$(mtime "$f")" "$f" >>"$tmp/cand"
done

# VS Code family: <dir>/entries.json names the file; snapshots sit beside it.
uri=file://$(printf %s "$abs" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g')
for root in "$HOME/Library/Application Support" "${XDG_CONFIG_HOME:-$HOME/.config}"; do
    for app in Code 'Code - Insiders' VSCodium Cursor; do
        hist=$root/$app/User/History
        [ -d "$hist" ] || continue
        grep --files-with-matches --fixed-strings "\"resource\":\"$uri\"" "$hist"/*/entries.json 2>/dev/null | while IFS= read -r entries; do
            dir=${entries%/entries.json}
            { tr '{' '\n' <"$entries"; echo; } | sed -n 's/.*"id":"\([^"]*\)".*"timestamp":\([0-9]*\).*/\1 \2/p' |
                while read -r id ms; do
                    [ -f "$dir/$id" ] && printf '%s\t%s\t%s\n' "$((ms / 1000))" "$app" "$dir/$id"
                done
        done >>"$tmp/cand"
    done
done

sort --numeric-sort "$tmp/cand" | while IFS="$(printf '\t')" read -r t src f; do
    [ "$t" -ge "$since" ] || continue
    sum=$(cksum <"$f")
    grep --quiet --line-regexp --fixed-strings "$sum" "$tmp/seen" 2>/dev/null && continue
    echo "$sum" >>"$tmp/seen"
    cmp --silent "$f" "$head" && continue
    [ -f "$rel" ] && cmp --silent "$f" "$rel" && continue
    stat=$(git diff --no-index --numstat -- "$head" "$f" | awk '{ printf "+%s -%s", $1, $2 }')
    printf '%s  %-8s %-10s %s\n' "$(stamp "$t")" "$src" "$stat" "$f"
done >"$tmp/out"

[ -s "$tmp/out" ] || { echo "No earlier versions of $rel since its last commit" >&2; exit 1; }
cat "$tmp/out"
