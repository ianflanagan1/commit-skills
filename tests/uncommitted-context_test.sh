#!/bin/sh
# Behaviour of shared/scripts/uncommitted-context.sh. Run with tests/run.sh.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

test_a_clean_working_tree_exits_1() {
    assertEquals 1 "$(exit_status sh "$uncommitted_context")"
}

test_outside_a_repository_exits_2() {
    cd "$sandbox" || return
    assertEquals 2 "$(exit_status sh "$uncommitted_context")"
}

test_a_bad_option_exits_2() {
    lines x >new
    assertEquals 2 "$(exit_status sh "$uncommitted_context" -n x)"
}

test_shows_recent_commit_subjects() {
    lines x >new
    assertContains "$(sh "$uncommitted_context")" "## Recent commits
init"
}

test_shows_staged_and_unstaged_changes_together_against_head() {
    lines a B c >f
    git add f
    lines a B c d >f
    out=$(sh "$uncommitted_context")
    assertContains "$out" '    2 +B'
    assertContains "$out" '    3 +d'
}

test_shows_untracked_files_with_their_lines_numbered() {
    lines x y >new
    assertContains "$(sh "$uncommitted_context")" "    2 +y"
}

test_names_lockfiles_without_showing_their_diff() {
    lines '{}' >package-lock.json
    out=$(sh "$uncommitted_context")
    assertContains "$out" '(omitted: package-lock.json)'
    assertNotContains "$out" '+{}'
}

test_numbers_match_stage_lines_once_the_index_is_reset() {
    lines a B c >f
    git add f
    lines a B c d >f
    out=$(sh "$uncommitted_context")
    git reset -q
    assertContains "$out" "$(sh "$stage_lines" f)"
}

test_truncates_the_changes_after_the_line_limit() {
    lines a B c d >f
    assertContains "$(sh "$uncommitted_context" -n 3 | tail -1)" '[truncated: 3 of'
}

test_reports_a_merge_in_progress() {
    lines x >new
    touch .git/MERGE_HEAD
    assertContains "$(sh "$uncommitted_context")" '(a merge is in progress)'
}

test_reports_a_rebase_in_progress() {
    lines x >new
    mkdir .git/rebase-merge
    assertContains "$(sh "$uncommitted_context")" '(a rebase is in progress)'
}

test_reports_a_detached_head() {
    git checkout -q --detach
    lines x >new
    assertContains "$(sh "$uncommitted_context")" '(detached HEAD: new commits will be on no branch)'
}

test_says_nothing_of_a_detached_head_on_a_branch() {
    lines x >new
    assertNotContains "$(sh "$uncommitted_context")" 'detached HEAD'
}

test_works_before_the_first_commit() {
    rm -rf .git && new_repo
    out=$(sh "$uncommitted_context")
    assertContains "$out" '(none: the first commit is still to be made)'
    assertContains "$out" '    1 +a'
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
