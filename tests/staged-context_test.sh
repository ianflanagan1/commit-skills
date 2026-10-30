#!/bin/sh
# Behaviour of shared/scripts/staged-context.sh. Run with `devbox run -- task test`.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

test_nothing_staged_exits_1() {
    lines a b c d >f
    assertEquals 1 "$(exit_status sh "$staged_context")"
}

test_outside_a_repository_exits_2() {
    cd "$sandbox" || return
    assertEquals 2 "$(exit_status sh "$staged_context")"
}

test_shows_recent_commit_subjects() {
    lines a b c d >f && git add f
    assertContains "$(sh "$staged_context")" "## Recent commits
init"
}

test_shows_staged_changes_but_not_unstaged_ones() {
    lines a b c d >f && git add f
    lines a b c d e >f
    out=$(sh "$staged_context")
    assertContains "$out" '+d'
    assertNotContains "$out" '+e'
}

test_names_lockfiles_without_showing_their_diff() {
    lines '{}' >package-lock.json && git add package-lock.json
    out=$(sh "$staged_context")
    assertContains "$out" 'package-lock.json'
    assertNotContains "$out" '+{}'
}

test_truncates_the_diff_after_the_line_limit() {
    lines a b c d >f && git add f
    assertContains "$(sh "$staged_context" -n 3 | tail -1)" '[truncated: 3 of'
}

test_reports_a_merge_in_progress() {
    lines a b c d >f && git add f
    touch .git/MERGE_HEAD
    assertContains "$(sh "$staged_context")" '(a merge is in progress)'
}

test_reports_a_detached_head() {
    git checkout --quiet --detach
    lines a b c d >f && git add f
    assertContains "$(sh "$staged_context")" '(detached HEAD: the commit will be on no branch)'
}

test_says_nothing_of_a_detached_head_on_a_branch() {
    lines a b c d >f && git add f
    assertNotContains "$(sh "$staged_context")" 'detached HEAD'
}

test_marks_the_first_commit() {
    rm -rf .git && new_repo
    git add f
    assertContains "$(sh "$staged_context")" '(none: this will be the first commit)'
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
