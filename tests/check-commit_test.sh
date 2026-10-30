#!/bin/sh
# Behaviour of shared/scripts/check-commit.sh. Run with `devbox run -- task test`.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

test_a_passing_command_prints_one_line_naming_the_commit() {
    assertEquals "passed: $(git log -1 --format='%h %s')" "$(sh "$check_commit" HEAD 'echo noise')"
}

test_a_failing_command_exits_1_with_its_output_and_status() {
    out=$(sh "$check_commit" HEAD 'echo broken; exit 3')
    assertEquals 1 $?
    assertContains "$out" 'broken'
    assertContains "$out" "failed (exit 3): $(git log -1 --format='%h %s')"
}

test_runs_on_the_commit_not_the_working_tree() {
    lines x >f
    assertEquals 0 "$(exit_status sh "$check_commit" HEAD 'grep -q a f')"
    assertEquals 1 "$(exit_status sh "$check_commit" HEAD 'grep -q x f')"
}

test_runs_on_an_earlier_commit() {
    lines x >f
    commit_all second
    assertEquals 0 "$(exit_status sh "$check_commit" HEAD~1 'grep -q a f')"
}

test_shows_only_the_end_of_long_output() {
    out=$(sh "$check_commit" HEAD 'seq 1 500; exit 1')
    assertEquals '[first 400 lines not shown]' "$(lines "$out" | sed -n 1p)"
    assertEquals 401 "$(lines "$out" | sed -n 2p)"
    assertContains "$out" '500'
}

test_removes_its_worktree_whether_the_command_passes_or_fails() {
    sh "$check_commit" HEAD true >/dev/null
    sh "$check_commit" HEAD false >/dev/null
    assertEquals 1 "$(git worktree list | wc -l | tr -d ' ')"
}

test_leaves_the_working_tree_and_index_as_they_were() {
    lines a B c >f
    git add f
    lines a B c d >f
    sh "$check_commit" HEAD 'echo x >f' >/dev/null
    assertEquals 'a B c' "$(in_index f)"
    assertEquals 'a B c d' "$(tr '\n' ' ' <f | sed 's/ $//')"
}

test_prints_its_usage_with_h() {
    assertContains "$(sh "$check_commit" -h)" 'Usage: check-commit.sh rev command'
}

test_a_missing_command_exits_2() {
    assertEquals 2 "$(exit_status sh "$check_commit" HEAD)"
}

test_an_unknown_commit_exits_2() {
    assertEquals 2 "$(exit_status sh "$check_commit" nosuch true)"
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
