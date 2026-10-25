#!/bin/sh
# Behaviour of shared/scripts/amend-context.sh. Run with tests/run.sh.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

amend_context=$root/shared/scripts/amend-context.sh
rewrite=$root/shared/scripts/rewrite.sh

# two_commits: on a feature branch, commit A (adds g) and B (changes f's second line).
two_commits() {
    git checkout -qb feature
    lines g1 g2 g3 >g && commit_all 'Add g'
    lines a B c >f && commit_all 'Change f'
    A=$(git rev-parse --short HEAD~1) B=$(git rev-parse --short HEAD)
}

# owners_after line: the "last changed by" line that follows the first hunk containing line.
owners_after() {
    sh "$amend_context" | awk -v l="$1" 'index($0, l) { found = 1 } found && /last changed by/ { print; exit }'
}

test_no_commits_since_the_base_exits_1() {
    git checkout -qb feature
    lines x >new
    assertEquals 1 "$(exit_status sh "$amend_context")"
}

test_outside_a_repository_exits_2() {
    cd "$sandbox" || return
    assertEquals 2 "$(exit_status sh "$amend_context")"
}

test_shows_the_base_warnings_and_commits_since_the_base() {
    two_commits
    out=$(sh "$amend_context")
    assertContains "$out" '## Base'
    assertContains "$out" '2 commits since the base'
    assertContains "$out" '## Warnings
(none)'
    assertContains "$out" "### $A
Add g"
}

test_a_clean_branch_still_shows_its_commits() {
    two_commits
    out=$(sh "$amend_context")
    assertContains "$out" '## Uncommitted changes'
    assertContains "$out" "### $B"
}

test_warns_of_a_detached_head_and_the_branch_that_also_holds_the_commits() {
    two_commits
    git checkout -q --detach
    lines x >>g && commit_all 'Change g'
    out=$(sh "$amend_context" "$(git rev-parse HEAD~3)")
    assertContains "$out" '(detached HEAD: the commits are on no branch, and reworking moves only HEAD)'
    assertContains "$out" '(also on branch feature: 2 of 3 commits)'
}

test_numbers_uncommitted_lines_as_rewrite_list_does() {
    two_commits
    lines g1 G2 g3 >g
    assertContains "$(sh "$amend_context")" "$(sh "$rewrite" list - g)"
}

test_a_changed_line_names_the_commit_that_last_changed_it() {
    two_commits
    lines a BB c >f
    assertEquals "      last changed by: $B" "$(owners_after '+BB')"
}

test_added_lines_name_the_commits_of_the_lines_around_them() {
    two_commits
    lines g1 g2 new g3 >g
    assertEquals "      last changed by: $A" "$(owners_after '+new')"
}

test_lines_from_before_the_base_are_named_as_such() {
    two_commits
    lines A BB c >f
    assertEquals "      last changed by: $B (and lines from before the base)" "$(owners_after '+A')"
}

test_a_new_file_names_no_commit() {
    two_commits
    lines k1 >k
    assertEquals '' "$(owners_after '+k1')"
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
