#!/bin/sh
# Behaviour of shared/scripts/branch-context.sh. Run with `devbox run -- task test`.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# branch name: create a branch at HEAD and switch to it.
branch() { git checkout --quiet -b "$1"; }

# commit_file path: add or change path and commit it with the path as the subject.
commit_file() { lines x >>"$1" && commit_all "$1"; }

# base_line: the line naming the base, without its hash.
base_line() { sh "$branch_context" "$@" | sed -n '/^## Base$/{n;p;}' | cut -d' ' -f2-; }

# push_to_origin: give the repo a bare origin, push the current branch and track it.
push_to_origin() {
    git init --quiet --bare "$sandbox/origin.git"
    git remote add origin "$sandbox/origin.git"
    git push --quiet --set-upstream origin HEAD 2>/dev/null
    git remote set-head origin --auto >/dev/null
}

# --- Finding the base

test_the_base_is_the_nearest_branch() {
    main=$(git symbolic-ref --short HEAD)
    branch feature && commit_file g
    assertEquals "$main (guessed: nearest branch)" "$(base_line)"
    assertContains "$(sh "$branch_context")" '1 commits since the base'
}

test_a_branch_started_from_another_branch_takes_that_one_as_its_base() {
    branch develop && commit_file d
    branch feature && commit_file g
    assertEquals 'develop (guessed: nearest branch)' "$(base_line)"
}

test_a_given_base_is_used() {
    main=$(git symbolic-ref --short HEAD)
    branch develop && commit_file d
    branch feature && commit_file g
    assertEquals "$main (given)" "$(base_line "$main")"
    assertContains "$(sh "$branch_context" "$main")" '2 commits since the base'
}

test_branches_built_on_this_one_are_not_its_base() {
    main=$(git symbolic-ref --short HEAD)
    branch feature && commit_file g
    branch child && commit_file h
    git checkout --quiet feature
    assertEquals "$main (guessed: nearest branch)" "$(base_line)"
}

test_this_branch_on_a_remote_is_not_its_base() {
    main=$(git symbolic-ref --short HEAD)
    push_to_origin
    branch feature && commit_file g && git push --quiet --set-upstream origin feature 2>/dev/null
    commit_file h
    assertContains "$(base_line)" "$main, origin/$main (guessed: nearest branch"
}

test_commits_already_on_a_remote_are_left_out_unless_the_base_is_given() {
    main=$(git symbolic-ref --short HEAD)
    push_to_origin
    branch feature && commit_file g && git push --quiet --set-upstream origin feature 2>/dev/null
    commit_file h
    assertEquals "$main, origin/$main (guessed: nearest branch; 1 pushed commits left as they are)" "$(base_line)"
    assertEquals "$(git rev-parse --short HEAD~1)" "$(sh "$branch_context" | sed -n '/^## Base$/{n;p;}' | cut -d' ' -f1)"
    assertContains "$(sh "$branch_context")" '1 commits since the base'
    assertContains "$(sh "$branch_context" "$main")" '2 commits since the base'
}

test_a_configured_base_leaves_out_commits_already_on_a_remote() {
    main=$(git symbolic-ref --short HEAD)
    push_to_origin
    branch feature && commit_file g && git push --quiet --set-upstream origin feature 2>/dev/null
    commit_file h
    git config commit-skills.base "$main"
    assertContains "$(sh "$branch_context")" '1 commits since the base'
}

test_a_branch_that_is_all_pushed_and_clean_has_nothing_to_rework() {
    push_to_origin
    branch feature && commit_file g && git push --quiet --set-upstream origin feature 2>/dev/null
    assertEquals 1 "$(exit_status sh "$branch_context")"
}

test_a_branch_that_is_all_pushed_reworks_only_its_uncommitted_work() {
    push_to_origin
    branch feature && commit_file g && git push --quiet --set-upstream origin feature 2>/dev/null
    lines x >new
    assertContains "$(sh "$branch_context")" '0 commits since the base'
}

test_on_the_default_branch_only_unpushed_commits_are_reworked() {
    push_to_origin
    commit_file g
    assertContains "$(base_line)" "(upstream of $(git symbolic-ref --short HEAD): unpushed commits only)"
    assertContains "$(sh "$branch_context")" '1 commits since the base'
}

test_on_the_default_branch_without_an_upstream_exits_2() {
    lines x >new
    assertEquals 2 "$(exit_status sh "$branch_context")"
}

test_a_configured_base_is_used_in_place_of_the_nearest_branch() {
    main=$(git symbolic-ref --short HEAD)
    branch develop && commit_file d
    branch feature && commit_file g
    git config commit-skills.base "$main"
    assertEquals "$main (from git config commit-skills.base)" "$(base_line)"
    assertContains "$(sh "$branch_context")" '2 commits since the base'
}

test_a_given_base_overrides_the_configured_one() {
    main=$(git symbolic-ref --short HEAD)
    branch develop && commit_file d
    branch feature && commit_file g
    git config commit-skills.base "$main"
    assertEquals 'develop (given)' "$(base_line develop)"
}

test_on_the_configured_base_branch_only_unpushed_commits_are_reworked() {
    push_to_origin
    branch develop && git push --quiet --set-upstream origin develop 2>/dev/null
    git config commit-skills.base origin/develop
    commit_file d
    assertEquals 'origin/develop (upstream of develop: unpushed commits only)' "$(base_line)"
}

test_a_configured_base_that_is_not_a_commit_exits_2() {
    branch feature && commit_file g
    git config commit-skills.base nope
    assertEquals 2 "$(exit_status sh "$branch_context")"
}

test_a_new_branch_with_uncommitted_work_has_its_start_as_the_base() {
    branch feature
    lines x >new
    assertContains "$(sh "$branch_context")" '0 commits since the base'
}

test_a_given_base_that_is_not_a_commit_exits_2() {
    branch feature && commit_file g
    assertEquals 2 "$(exit_status sh "$branch_context" nope)"
}

test_commits_on_no_branch_take_the_nearest_branch_as_their_base() {
    main=$(git symbolic-ref --short HEAD)
    git checkout --quiet --detach && commit_file g
    assertEquals "$main (guessed: nearest branch)" "$(base_line)"
    assertContains "$(sh "$branch_context")" '1 commits since the base'
}

test_a_head_detached_at_a_branch_tip_has_no_commits_of_its_own_to_rework() {
    branch feature && commit_file g
    git checkout --quiet --detach
    assertEquals 1 "$(exit_status sh "$branch_context")"
    lines x >new
    assertContains "$(sh "$branch_context")" '0 commits since the base'
}

# --- Exit status

test_nothing_to_rework_exits_1() {
    branch feature
    assertEquals 1 "$(exit_status sh "$branch_context")"
}

test_outside_a_repository_exits_2() {
    cd "$sandbox" || return
    assertEquals 2 "$(exit_status sh "$branch_context")"
}

test_a_repository_without_commits_exits_2() {
    rm -rf .git && new_repo
    assertEquals 2 "$(exit_status sh "$branch_context")"
}

test_a_bad_option_exits_2() {
    branch feature && commit_file g
    assertEquals 2 "$(exit_status sh "$branch_context" -n x)"
}

# --- Warnings

test_no_warnings_prints_none() {
    branch feature && commit_file g
    assertContains "$(sh "$branch_context")" '## Warnings
(none)'
}

test_warns_of_commits_by_someone_else() {
    branch feature && commit_file g
    lines y >>g && git add g && GIT_AUTHOR_EMAIL=other@example.com git commit --quiet --message other
    assertContains "$(sh "$branch_context")" '(not yours: 1 commits by other@example.com)'
}

test_warns_of_merge_commits() {
    branch feature && commit_file g
    branch side && commit_file h
    git checkout --quiet feature && commit_file i
    git merge --quiet --no-edit side
    assertContains "$(sh "$branch_context" side~1)" '(merge commits: 1)'
}

test_warns_of_pushed_commits() {
    main=$(git symbolic-ref --short HEAD)
    push_to_origin
    branch feature && commit_file g && git push --quiet origin feature 2>/dev/null
    commit_file h
    assertContains "$(sh "$branch_context" "$main")" '(pushed: 1 of 2 commits are on a remote)'
}

test_warns_of_committed_files_that_are_now_ignored() {
    branch feature
    lines secret >.env && git add .env && commit_all env
    lines .env >.gitignore && commit_all ignore
    assertContains "$(sh "$branch_context")" '(ignored but committed: .env)'
}

test_warns_of_a_detached_head() {
    git checkout --quiet --detach && commit_file g
    assertContains "$(sh "$branch_context")" '(detached HEAD: the commits are on no branch, and reworking moves only HEAD)'
}

test_a_head_detached_partway_along_a_branch_takes_that_branch_as_its_base() {
    branch feature && commit_file g && commit_file h
    git checkout --quiet --detach HEAD~1 && commit_file i
    assertEquals 'feature (guessed: nearest branch)' "$(base_line)"
    assertNotContains "$(sh "$branch_context")" 'also on branch'
}

test_warns_of_commits_since_the_base_that_a_branch_also_holds_when_detached() {
    main=$(git symbolic-ref --short HEAD)
    branch feature && commit_file g && commit_file h
    git checkout --quiet --detach HEAD~1 && commit_file i
    assertContains "$(sh "$branch_context" "$main")" '(also on branch feature: 1 of 2 commits)'
}

test_a_branch_built_on_this_one_is_not_named_as_holding_its_commits() {
    branch feature && commit_file g
    branch child && commit_file h
    git checkout --quiet feature
    assertNotContains "$(sh "$branch_context")" 'also on branch'
}

test_reports_a_rebase_in_progress() {
    branch feature && commit_file g
    mkdir .git/rebase-merge
    assertContains "$(sh "$branch_context")" '(a rebase is in progress)'
}

# --- Commits and changes

test_shows_style_subjects_from_before_the_base() {
    branch feature && commit_file g
    assertContains "$(sh "$branch_context")" '## Recent commits before the base
init'
}

test_shows_each_commit_with_its_full_message() {
    branch feature
    lines x >g && git add g && git commit --quiet --message 'Add g' --message 'Because of reasons.'
    out=$(sh "$branch_context")
    assertContains "$out" 'Add g

Because of reasons.'
    assertContains "$out" ' g | 1 +'
}

test_shows_committed_uncommitted_and_untracked_changes_together() {
    branch feature
    lines g1 >g && commit_all g
    lines a B c >f
    lines x >new
    out=$(sh "$branch_context")
    assertContains "$out" '    1 +g1'
    assertContains "$out" '    2 +B'
    assertContains "$out" '    1 +x'
}

test_numbers_match_stage_lines_once_the_index_is_reset_to_the_base() {
    main=$(git symbolic-ref --short HEAD)
    branch feature
    lines a B c >f && commit_all f
    lines a B c d >f
    out=$(sh "$branch_context")
    git reset --quiet "$main"
    assertContains "$out" "$(sh "$stage_lines" f)"
}

test_truncates_the_changes_after_the_line_limit() {
    branch feature && commit_file g
    assertContains "$(sh "$branch_context" -n 3 | tail -1)" '[truncated: 3 of'
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
