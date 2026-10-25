# branch-base: the base that commits on a branch or a detached HEAD are reworked or amended
# from, and the warnings about them. Sourced by branch-context.sh and amend-context.sh, not run.
#
# The base is where the work started: the merge-base with the given branch or commit; else, on
# the default branch or the configured base's own branch, with its upstream; else with the branch
# set in git config commit-skills.base; else with the nearest other branch, local or
# remote-tracking, leaving the fewest commits since the base. Unless the base was given, it then
# moves past every commit already on a remote, so pushed commits are left as they are.

# base_candidates: every other branch as "commits since the merge-base, merge-base, name",
# skipping this branch, its remote copies and branches built on top of it.
base_candidates() {
    git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/remotes |
        while read -r ref tip; do
            case $ref in
                refs/heads/"$cur" | refs/remotes/*/"$cur" | refs/remotes/*/HEAD) continue ;;
            esac
            mb=$(git merge-base HEAD "$ref" 2>/dev/null) || continue
            [ "$mb" != "$head" ] || [ "$tip" = "$head" ] || continue
            printf '%s %s %s\n' "$(git rev-list --count "$mb..HEAD")" "$mb" "${ref#refs/*/}"
        done
}

# find_base [base]: set base (a full hash) and how (how it was found), or exit 2 with an error.
find_base() {
    head=$(git rev-parse HEAD)
    cur=$(git symbolic-ref -q --short HEAD || true)

    # The default branch: origin's HEAD, else a local main or master.
    default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
    default=${default#origin/}
    if [ -z "$default" ]; then
        for b in main master; do
            if git show-ref -q --verify "refs/heads/$b"; then default=$b; break; fi
        done
    fi

    # The configured base, and the branch it names, without its remote.
    configured=$(git config commit-skills.base || true)
    own=$configured
    ! git show-ref -q --verify "refs/remotes/$configured" || own=${configured#*/}

    if [ $# -eq 1 ]; then
        git rev-parse -q --verify "$1^{commit}" >/dev/null || { echo "Not a commit: $1" >&2; exit 2; }
        base=$(git merge-base HEAD "$1") || { echo "No history in common with $1" >&2; exit 2; }
        how="$1 (given)"
        return
    elif [ -n "$cur" ] && { [ "$cur" = "$default" ] || [ "$cur" = "$own" ]; }; then
        upstream=$(git rev-parse -q --abbrev-ref '@{upstream}' 2>/dev/null) ||
            { echo "On $cur with no upstream; pass the base to rework from" >&2; exit 2; }
        base=$(git merge-base HEAD "$upstream")
        how="$upstream (upstream of $cur: unpushed commits only)"
    elif [ -n "$configured" ]; then
        git rev-parse -q --verify "$configured^{commit}" >/dev/null ||
            { echo "commit-skills.base is $configured, which is not a commit" >&2; exit 2; }
        base=$(git merge-base HEAD "$configured") || { echo "No history in common with $configured" >&2; exit 2; }
        how="$configured (from git config commit-skills.base)"
    else
        cand=$(base_candidates | sort -n)
        [ -n "$cand" ] || { echo 'No other branch to find the base from; pass the base to rework from' >&2; exit 2; }
        n=$(printf '%s\n' "$cand" | head -n 1 | cut -d' ' -f1)
        near=$(printf '%s\n' "$cand" | awk -v n="$n" '$1 == n')
        base=$(printf '%s\n' "$near" | head -n 1 | cut -d' ' -f2)
        if [ "$(printf '%s\n' "$near" | cut -d' ' -f2 | sort -u | wc -l)" -gt 1 ]; then
            echo "Several branches are equally near: $(printf '%s\n' "$near" | cut -d' ' -f3 | tr '\n' ' ')" >&2
            echo 'Pass the base to rework from' >&2
            exit 2
        fi
        how="$(printf '%s\n' "$near" | cut -d' ' -f3 | tr '\n' ',' | sed 's/,$//; s/,/, /g') (guessed: nearest branch)"
    fi

    # Move past commits already on a remote. The branch has no merges for a skill to accept, so
    # they are the oldest ones, and the base becomes the newest of them.
    pushed=$(git rev-list --count "$base..HEAD")
    unpushed=$(git rev-list --reverse HEAD "^$base" --not --remotes)
    [ -z "$unpushed" ] || pushed=$((pushed - $(printf '%s\n' "$unpushed" | wc -l)))
    [ "$pushed" -gt 0 ] || return 0
    if [ -z "$unpushed" ]; then
        base=$head
    else
        base=$(git rev-parse "$(printf '%s\n' "$unpushed" | head -n 1)^")
    fi
    how="${how%)}; $pushed pushed commits left as they are)"
}

# print_warnings base: an operation in progress, a detached HEAD and the branches that also hold
# its commits since the base, merge commits, commits by others, pushed commits and committed
# files that are now ignored, one per line in parentheses, or (none).
print_warnings() {
    {
        git_dir=$(git rev-parse --git-dir)
        [ ! -f "$git_dir/MERGE_HEAD" ] || echo '(a merge is in progress)'
        [ ! -d "$git_dir/rebase-merge" ] && [ ! -d "$git_dir/rebase-apply" ] || echo '(a rebase is in progress)'
        [ ! -f "$git_dir/CHERRY_PICK_HEAD" ] || echo '(a cherry-pick is in progress)'
        [ ! -f "$git_dir/REVERT_HEAD" ] || echo '(a revert is in progress)'
        total=$(git rev-list --count "$1..HEAD")
        # Detached, a rework moves only HEAD, so any branch holding these commits keeps them.
        if ! git symbolic-ref -q HEAD >/dev/null; then
            echo '(detached HEAD: the commits are on no branch, and reworking moves only HEAD)'
            git for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r b; do
                held=$((total - $(git rev-list --count "$1..HEAD" "^refs/heads/$b")))
                [ "$held" -eq 0 ] || echo "(also on branch $b: $held of $total commits)"
            done
        fi
        merges=$(git rev-list --count --merges "$1..HEAD")
        [ "$merges" -eq 0 ] || echo "(merge commits: $merges)"
        me=$(git config user.email || true)
        git log --format=%ae "$1..HEAD" | sort | uniq -c | while read -r count email; do
            [ "$email" = "$me" ] || echo "(not yours: $count commits by $email)"
        done
        unpushed=$(git rev-list --count HEAD "^$1" --not --remotes)
        [ "$unpushed" -eq "$total" ] || echo "(pushed: $((total - unpushed)) of $total commits are on a remote)"
        git diff --name-only --no-renames "$1" HEAD | git check-ignore --no-index --stdin |
            sed 's/^/(ignored but committed: /; s/$/)/' || true
    } | awk '{ print } END { if (NR == 0) print "(none)" }'
}
