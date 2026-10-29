#!/bin/sh
# Behaviour of shared/scripts/rewrite.sh. Run with tests/run.sh.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

rewrite=$root/shared/scripts/rewrite.sh

# three_commits: on a feature branch, commit A (adds g), B (changes f, adds i) and C (adds h),
# and set base, A, B and C to their hashes.
three_commits() {
    git checkout --quiet -b feature
    lines g1 g2 g3 >g && commit_all 'Add g'
    lines a B c >f && lines i1 >i && commit_all 'Change f'
    lines h1 >h && commit_all 'Add h'
    base=$(git rev-parse HEAD~3) A=$(git rev-parse HEAD~2) B=$(git rev-parse HEAD~1) C=$(git rev-parse HEAD)
}

# plan line...: write the plan file, one argument per line.
plan() { lines "$@" >"$sandbox/plan"; }

# message file subject: write a message file in the sandbox.
message() { lines "$2" >"$sandbox/$1"; }

# build: run the plan on base and print the new HEAD.
build() { sh "$rewrite" run "$base" "$sandbox/plan" | sed -n 's/^HEAD //p'; }

# build_and_apply: run the plan on base and move HEAD to the result.
build_and_apply() {
    new=$(build) && sh "$rewrite" apply "$C" "$new" >/dev/null
}

# subjects: the subjects since the base, oldest first, one line, separated by "|".
subjects() { git log --reverse --format=%s "$base..HEAD" | tr '\n' '|' | sed 's/|$//'; }

# file_at rev path: the file's content at rev, as one space-separated line.
file_at() { git cat-file blob "$1:$2" | tr '\n' ' ' | sed 's/ $//'; }

# state: HEAD, the index and the working tree, to check that nothing changed.
state() { git rev-parse HEAD; git write-tree; git status --porcelain --untracked-files=all; cat f g 2>/dev/null; }

# --- Listing and pieces

test_lists_uncommitted_lines_numbered_against_head_whatever_is_staged() {
    three_commits
    lines g1 G2 g3 >g
    git add g
    assertEquals '    1 -g2
    2 +G2' "$(sh "$rewrite" list - g | grep '^ *[0-9]')"
}

test_lists_a_commit_s_lines_numbered_against_its_parent() {
    three_commits
    assertEquals '    1 -b
    2 +B' "$(sh "$rewrite" list "$B" f | grep '^ *[0-9]')"
}

test_a_piece_holds_only_the_chosen_lines_on_top_of_head() {
    three_commits
    lines g0 g1 g2 g3 G4 >g
    p=$(sh "$rewrite" piece - g 2)
    assertEquals "$C" "$(git rev-parse "$p^")"
    assertEquals 'g1 g2 g3 G4' "$(file_at "$p" g)"
}

test_a_piece_of_a_commit_sits_on_its_parent() {
    three_commits
    p=$(sh "$rewrite" piece "$B" i all)
    assertEquals "$A" "$(git rev-parse "$p^")"
    assertEquals 'a b c' "$(file_at "$p" f)"
    assertEquals 'i1' "$(file_at "$p" i)"
}

test_a_piece_can_take_lines_from_several_files() {
    three_commits
    lines a B C >f
    lines new >k
    p=$(sh "$rewrite" piece - f 1,2 k all)
    assertEquals 'a B C' "$(file_at "$p" f)"
    assertEquals 'new' "$(file_at "$p" k)"
}

test_a_piece_can_delete_a_file() {
    three_commits
    rm h
    p=$(sh "$rewrite" piece - h all)
    assertFalse 'h is gone' "git cat-file -e '$p:h'"
}

test_making_a_piece_changes_nothing() {
    three_commits
    lines g1 G2 g3 >g
    git add g
    lines a b C >f
    before=$(state)
    sh "$rewrite" piece - g all f 1,2 >/dev/null
    assertEquals "$before" "$(state)"
}

test_a_piece_that_changes_nothing_exits_3() {
    three_commits
    assertEquals 3 "$(exit_status sh "$rewrite" piece - g all)"
}

# --- Running a plan

test_a_plan_that_picks_every_commit_in_order_keeps_them() {
    three_commits
    plan "pick $A" "pick $B" "pick $C"
    out=$(sh "$rewrite" run "$base" "$sandbox/plan")
    assertContains "$out" "kept $(git rev-parse --short "$A") Add g"
    assertContains "$out" "HEAD $C"
}

test_running_a_plan_changes_nothing() {
    three_commits
    lines g1 G2 g3 >g
    p=$(sh "$rewrite" piece - g all)
    plan "pick $A" "fixup $p" "pick $B" "pick $C"
    before=$(state)
    build >/dev/null
    assertEquals "$before" "$(state)"
}

test_folding_uncommitted_lines_into_an_earlier_commit_replays_the_later_ones() {
    three_commits
    lines g1 G2 g3 >g
    p=$(sh "$rewrite" piece - g all)
    plan "pick $A" "fixup $p" "pick $B" "pick $C"
    build_and_apply
    assertEquals 'Add g|Change f|Add h' "$(subjects)"
    assertEquals 'g1 G2 g3' "$(file_at HEAD~2 g)"
    assertEquals "$base" "$(git rev-parse HEAD~3)"
    assertEquals '' "$(git status --porcelain)"
}

test_commits_before_the_first_change_keep_their_hashes() {
    three_commits
    lines a B C >f
    p=$(sh "$rewrite" piece - f all)
    plan "pick $A" "pick $B" "fixup $p" "pick $C"
    build_and_apply
    assertEquals "$A" "$(git rev-parse HEAD~2)"
    assertNotEquals "$B" "$(git rev-parse HEAD~1)"
}

test_a_replayed_commit_keeps_its_author_date_and_whole_message() {
    git checkout --quiet -b feature
    lines g1 >g && commit_all 'Add g'
    lines a B c >f && git add f
    GIT_AUTHOR_NAME=other GIT_AUTHOR_EMAIL=other@example.com GIT_AUTHOR_DATE='1600000000 +0200' \
        git commit --quiet --message 'Change f' --message 'Because of reasons.'
    base=$(git rev-parse HEAD~2) A=$(git rev-parse HEAD~1) B=$(git rev-parse HEAD) C=$B
    lines g1 g2 >g
    p=$(sh "$rewrite" piece - g all)
    plan "pick $A" "fixup $p" "pick $B"
    build_and_apply
    assertNotEquals "$B" "$(git rev-parse HEAD)"
    assertEquals 'other <other@example.com> 1600000000 +0200' "$(git log -1 --format='%an <%ae> %ad' --date=raw)"
    assertEquals "$(git log -1 --format=%B "$B")" "$(git log -1 --format=%B)"
}

test_message_replaces_the_message_of_the_commit_before() {
    three_commits
    message m 'Add the g file'
    plan "pick $A" "message $sandbox/m" "pick $B" "pick $C"
    build_and_apply
    assertEquals 'Add the g file|Change f|Add h' "$(subjects)"
    assertEquals "$(git rev-parse "$C^{tree}")" "$(git rev-parse 'HEAD^{tree}')"
}

test_a_picked_piece_with_a_message_inserts_a_new_commit() {
    three_commits
    lines k1 >k
    p=$(sh "$rewrite" piece - k all)
    message m 'Add k'
    plan "pick $A" "pick $p" "message $sandbox/m" "pick $B" "pick $C"
    build_and_apply
    assertEquals 'Add g|Add k|Change f|Add h' "$(subjects)"
    assertEquals 'k1' "$(file_at HEAD~2 k)"
}

test_a_dropped_commit_s_change_is_left_uncommitted() {
    three_commits
    plan "pick $A" "drop $B" "pick $C"
    build_and_apply
    assertEquals 'Add g|Add h' "$(subjects)"
    assertEquals 'a b c' "$(file_at HEAD f)"
    assertEquals 'a B c' "$(tr '\n' ' ' <f | sed 's/ $//')"
    assertContains "$(git status --porcelain)" ' M f'
}

test_removing_a_piece_takes_its_lines_out_of_the_commit_before() {
    three_commits
    p=$(sh "$rewrite" piece "$A" g 2)
    plan "pick $A" "remove $p" "pick $B" "pick $C"
    build_and_apply
    assertEquals 'g1 g3' "$(file_at HEAD g)"
    assertContains "$(git status --porcelain)" ' M g'
}

test_lines_move_from_one_commit_to_a_later_one() {
    three_commits
    p=$(sh "$rewrite" piece "$A" g 2)
    plan "pick $A" "remove $p" "pick $B" "pick $C" "fixup $p"
    build_and_apply
    assertEquals 'g1 g3' "$(file_at HEAD~2 g)"
    assertEquals 'g1 g2 g3' "$(file_at HEAD g)"
    assertEquals '' "$(git status --porcelain)"
}

test_a_commit_splits_into_its_pieces() {
    three_commits
    p1=$(sh "$rewrite" piece "$B" f all)
    p2=$(sh "$rewrite" piece "$B" i all)
    message m1 'Change f'
    message m2 'Add i'
    plan "pick $A" "drop $B" "pick $p1" "message $sandbox/m1" "pick $p2" "message $sandbox/m2" "pick $C"
    build_and_apply
    assertEquals 'Add g|Change f|Add i|Add h' "$(subjects)"
    assertFalse 'i is not in the first half' "git cat-file -e HEAD~2:i"
    assertEquals "$(git rev-parse "$C^{tree}")" "$(git rev-parse 'HEAD^{tree}')"
}

test_a_commit_squashes_into_the_one_before() {
    three_commits
    message m 'Add g and change f'
    plan "pick $A" "fixup $B" "message $sandbox/m" "pick $C"
    build_and_apply
    assertEquals 'Add g and change f|Add h' "$(subjects)"
    assertEquals "$(git rev-parse "$C^{tree}")" "$(git rev-parse 'HEAD^{tree}')"
}

test_commits_reorder() {
    three_commits
    plan "pick $A" "pick $C" "pick $B"
    build_and_apply
    assertEquals 'Add g|Add h|Change f' "$(subjects)"
}

test_works_on_a_detached_head() {
    three_commits
    git checkout --quiet --detach
    lines g1 G2 g3 >g
    p=$(sh "$rewrite" piece - g all)
    plan "pick $A" "fixup $p" "pick $B" "pick $C"
    build_and_apply
    assertEquals 'g1 G2 g3' "$(file_at HEAD~2 g)"
    assertEquals "$C" "$(git rev-parse feature)"
}

# --- Stopping

test_a_fixup_into_a_commit_older_than_its_lines_stops_and_changes_nothing() {
    three_commits
    lines a BB c >f
    p=$(sh "$rewrite" piece - f all)
    plan "pick $A" "fixup $p" "pick $B" "pick $C"
    before=$(state)
    assertEquals 3 "$(exit_status sh "$rewrite" run "$base" "$sandbox/plan")"
    assertContains "$(sh "$rewrite" run "$base" "$sandbox/plan" 2>&1)" 'plan line 2: conflict in: f'
    assertEquals "$before" "$(state)"
}

test_a_change_that_empties_a_commit_stops() {
    three_commits
    p=$(sh "$rewrite" piece "$A" g all)
    plan "pick $A" "remove $p" "pick $B" "pick $C"
    assertEquals 3 "$(exit_status sh "$rewrite" run "$base" "$sandbox/plan")"
}

# --- Invalid plans

# invalid line...: assert the plan exits 2.
invalid() {
    plan "$@"
    assertEquals "plan: $*" 2 "$(exit_status sh "$rewrite" run "$base" "$sandbox/plan")"
}

test_every_commit_since_the_base_must_appear_once() {
    three_commits
    invalid "pick $A" "pick $C"
    invalid "pick $A" "pick $B" "pick $B" "pick $C"
}

test_a_commit_before_the_base_cannot_be_touched() {
    three_commits
    invalid "pick $base" "pick $A" "pick $B" "pick $C"
}

test_a_picked_piece_needs_a_message() {
    three_commits
    lines k1 >k
    p=$(sh "$rewrite" piece - k all)
    invalid "pick $A" "pick $p" "pick $B" "pick $C"
    invalid "pick $A" "pick $B" "pick $C" "pick $p"
}

test_fixup_remove_and_message_need_a_commit_before_them() {
    three_commits
    lines g1 G2 g3 >g
    p=$(sh "$rewrite" piece - g all)
    message m 'Subject'
    invalid "fixup $p" "pick $A" "pick $B" "pick $C"
    invalid "message $sandbox/m" "pick $A" "pick $B" "pick $C"
}

test_remove_takes_a_piece_and_drop_takes_a_commit() {
    three_commits
    p=$(sh "$rewrite" piece "$A" g 2)
    invalid "pick $A" "remove $B" "pick $C"
    invalid "pick $A" "pick $B" "pick $C" "drop $p"
}

test_a_missing_message_file_or_unknown_operation_is_invalid() {
    three_commits
    invalid "pick $A" "message $sandbox/none" "pick $B" "pick $C"
    invalid "pick $A" "edit $B" "pick $C"
}

test_a_plain_commit_that_is_not_a_piece_is_invalid() {
    three_commits
    other=$(echo other | git commit-tree "$(git rev-parse "$A^{tree}")" -p "$C")
    invalid "pick $A" "pick $B" "pick $C" "fixup $other"
}

test_merge_commits_since_the_base_are_refused() {
    three_commits
    git checkout --quiet -b side "$A" && lines s1 >s && commit_all side
    git checkout --quiet feature && git merge --quiet --no-edit side
    C=$(git rev-parse HEAD)
    plan "pick $A" "pick $B" "pick $C"
    assertEquals 2 "$(exit_status sh "$rewrite" run "$base" "$sandbox/plan")"
}

# --- Applying

test_apply_moves_head_and_the_index_and_leaves_the_working_tree() {
    three_commits
    lines g1 G2 g3 >g
    lines a B c d >f
    p=$(sh "$rewrite" piece - g all)
    plan "pick $A" "fixup $p" "pick $B" "pick $C"
    new=$(build)
    sh "$rewrite" apply "$C" "$new" >/dev/null
    assertEquals "$new" "$(git rev-parse HEAD)"
    assertEquals "$(git rev-parse "$new^{tree}")" "$(git write-tree)"
    assertEquals 'a B c d' "$(tr '\n' ' ' <f | sed 's/ $//')"
    assertEquals ' M f' "$(git status --porcelain)"
}

test_apply_refuses_once_head_has_moved() {
    three_commits
    plan "pick $A" "pick $C" "pick $B"
    new=$(build)
    lines k1 >k && commit_all k
    moved=$(git rev-parse HEAD)
    assertEquals 2 "$(exit_status sh "$rewrite" apply "$C" "$new")"
    assertEquals "$moved" "$(git rev-parse HEAD)"
}

test_a_bad_command_exits_2() {
    assertEquals 2 "$(exit_status sh "$rewrite" nope)"
    assertEquals 2 "$(exit_status sh "$rewrite" piece -)"
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
