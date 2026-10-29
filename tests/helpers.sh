# Shared by the *_test.sh files; sourced, not run.
# shellcheck disable=SC2034  # variables are used by the files that source this
#
# Every test starts in a fresh repository whose one commit holds f = "a b c", with HOME and
# XDG_CONFIG_HOME pointed inside the test's temporary directory, so no real history is read.

root=$(cd "$(dirname "$0")/.." && pwd)
stage_lines=$root/shared/scripts/stage-lines.sh
uncommitted_context=$root/shared/scripts/uncommitted-context.sh
history_versions=$root/shared/scripts/history-versions.sh
staged_context=$root/shared/scripts/staged-context.sh
branch_context=$root/shared/scripts/branch-context.sh
check_commit=$root/shared/scripts/check-commit.sh

setUp() {
    sandbox=$(mktemp --directory "${SHUNIT_TMPDIR:-${TMPDIR:-/tmp}}/test.XXXXXX")
    sandbox=$(cd "$sandbox" && pwd -P)
    HOME=$sandbox/home
    XDG_CONFIG_HOME=$HOME/.config
    export HOME XDG_CONFIG_HOME
    mkdir -p "$HOME" "$sandbox/repo"
    cd "$sandbox/repo" || return 1
    new_repo
    lines a b c >f
    commit_all init
}

tearDown() {
    cd / && rm -rf "$sandbox"
}

new_repo() {
    git init --quiet .
    git config user.name test
    git config user.email test@example.com
    git config commit.gpgsign false
}

commit_all() { git add --all && git commit --quiet --message "$1"; }

# lines a b c: print each argument on its own line.
lines() { printf '%s\n' "$@"; }

# in_index path: the file's content in the index, as one space-separated line.
in_index() { git cat-file blob ":$1" | tr '\n' ' ' | sed 's/ $//'; }

# exit_status command...: print the command's exit status, discarding its output.
exit_status() { "$@" >/dev/null 2>&1; echo $?; }

# Locate shunit2: $SHUNIT2, else on PATH (devbox, Homebrew, apt).
shunit2_path() { echo "${SHUNIT2:-$(command -v shunit2)}"; }
