#!/bin/sh
# Behaviour of shared/scripts/history-versions.sh. Run with tests/run.sh.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# checkpoint path version time content...: a Claude Code checkpoint of path saved at time
# (touch -t format).
checkpoint() {
    abs=$sandbox/repo/$1
    key=$(printf %s "$abs" | { shasum --algorithm 256 2>/dev/null || sha256sum; } | cut -c1-16)
    dir=$HOME/.claude/file-history/session
    mkdir -p "$dir"
    shift
    v=$1 t=$2
    shift 2
    lines "$@" >"$dir/$key@v$v"
    touch -t "$t" "$dir/$key@v$v"
}

# vscode path id epoch content...: a VS Code local history entry for path saved at epoch.
# VS Code writes entries.json without a trailing newline.
vscode() {
    uri=file://$(printf %s "$sandbox/repo/$1" | sed 's/ /%20/g')
    dir=$XDG_CONFIG_HOME/Code/User/History/h$2
    mkdir -p "$dir"
    id=$2 t=$3
    shift 3
    lines "$@" >"$dir/$id"
    printf '{"version":1,"resource":"%s","entries":[{"id":"%s","timestamp":%s000}]}' "$uri" "$id" "$t" >"$dir/entries.json"
}

soon() { date --date '+1 minute' +%Y%m%d%H%M 2>/dev/null || date -v+1M +%Y%m%d%H%M; }
later() { date --date '+2 minutes' +%Y%m%d%H%M 2>/dev/null || date -v+2M +%Y%m%d%H%M; }

test_lists_claude_code_checkpoints_with_their_save_time() {
    checkpoint f 1 202901020304 a B1 c
    lines a B2 c >f
    out=$(sh "$history_versions" f 2>&1)
    assertEquals 1 "$(echo "$out" | wc -l | tr -d ' ')"
    assertContains "$out" '2029-01-02 03:04:00  claude'
    assertContains "$out" '@v1'
}

test_lists_vscode_local_history_with_its_save_time() {
    vscode f AbCd.txt 1861920000 a B1 c
    lines a B2 c >f
    out=$(sh "$history_versions" f 2>&1)
    assertEquals 1 "$(echo "$out" | wc -l | tr -d ' ')"
    assertContains "$out" "$(date --date @1861920000 '+%Y-%m-%d' 2>/dev/null || date -r 1861920000 '+%Y-%m-%d')"
    assertContains "$out" 'AbCd.txt'
}

test_lists_versions_oldest_first_across_sources() {
    checkpoint f 1 "$(later)" a B1 c
    vscode f AbCd.txt $(($(date +%s) + 60)) a B0 c
    lines a B2 c >f
    out=$(sh "$history_versions" f)
    assertContains "$(echo "$out" | head -1)" 'AbCd.txt'
    assertContains "$(echo "$out" | tail -1)" '@v1'
}

test_shows_lines_added_and_removed_against_head() {
    checkpoint f 1 "$(soon)" a B1 c d
    lines a B2 c >f
    assertContains "$(sh "$history_versions" f)" '+2 -1'
}

test_leaves_out_versions_identical_to_head_or_the_working_tree() {
    checkpoint f 1 "$(soon)" a b c
    checkpoint f 2 "$(soon)" a B2 c
    lines a B2 c >f
    assertEquals 1 "$(exit_status sh "$history_versions" f)"
}

test_lists_identical_versions_once() {
    checkpoint f 1 "$(soon)" a B1 c
    checkpoint f 2 "$(later)" a B1 c
    lines a B2 c >f
    assertEquals 1 "$(sh "$history_versions" f | wc -l | tr -d ' ')"
}

test_leaves_out_versions_saved_before_the_file_was_last_committed() {
    checkpoint f 1 202001010000 a B1 c
    lines a B2 c >f
    assertEquals 1 "$(exit_status sh "$history_versions" f)"
}

test_finds_history_for_paths_with_spaces() {
    lines a >'s p'
    commit_all sp
    vscode 's p' Xy.txt $(($(date +%s) + 60)) a b
    lines a c >'s p'
    assertContains "$(sh "$history_versions" 's p')" 'Xy.txt'
}

test_no_versions_exits_1() {
    lines a B2 c >f
    assertEquals 1 "$(exit_status sh "$history_versions" f)"
}

test_no_path_exits_2() {
    assertEquals 2 "$(exit_status sh "$history_versions")"
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
