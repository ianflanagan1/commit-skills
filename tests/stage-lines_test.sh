#!/bin/sh
# Behaviour of shared/scripts/stage-lines.sh. Run with tests/run.sh.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# The working tree used by most tests: b replaced by B2, d added.
#   1 -b   2 +B2   3 +d
edit_f() { lines a B2 c d >f; }

# --- Listing

test_listing_numbers_each_changed_line_in_diff_order() {
    edit_f
    assertEquals "diff --git a/f b/f
@@ -1,3 +1,4 @@
       a
    1 -b
    2 +B2
       c
    3 +d" "$(sh "$stage_lines" f)"
}

test_listing_counts_from_the_index_so_numbers_restart_after_staging() {
    edit_f
    sh "$stage_lines" f 3 >/dev/null
    assertEquals "    1 -b
    2 +B2" "$(sh "$stage_lines" f | grep '^ *[0-9]')"
}

test_listing_against_a_base_commit_ignores_the_index() {
    edit_f
    git add f
    assertEquals 3 "$(sh "$stage_lines" -b HEAD f | grep --count '^ *[0-9]')"
}

test_a_file_without_changes_exits_1() {
    assertEquals 1 "$(exit_status sh "$stage_lines" f)"
}

test_a_path_in_neither_index_nor_working_tree_exits_2() {
    assertEquals 2 "$(exit_status sh "$stage_lines" missing)"
}

# --- Selecting lines

test_selecting_an_added_line_stages_only_that_line() {
    edit_f
    sh "$stage_lines" f 3 >/dev/null
    assertEquals 'a b c d' "$(in_index f)"
}

test_selecting_a_removed_line_with_its_replacement_stages_the_replacement() {
    edit_f
    sh "$stage_lines" f 1,2 >/dev/null
    assertEquals 'a B2 c' "$(in_index f)"
}

test_an_unselected_added_line_is_left_out() {
    edit_f
    sh "$stage_lines" f 1 >/dev/null
    assertEquals 'a c' "$(in_index f)"
}

test_an_unselected_removed_line_is_kept() {
    edit_f
    sh "$stage_lines" f 2 >/dev/null
    assertEquals 'a b B2 c' "$(in_index f)"
}

test_ids_may_be_ranges_lists_or_all() {
    for case in '1-3|a B2 c d' '2 3|a b B2 c d' '1,3|a c d' 'all|a B2 c d'; do
        git reset --quiet
        edit_f
        # shellcheck disable=SC2086
        sh "$stage_lines" f ${case%%|*} >/dev/null
        assertEquals "ids ${case%%|*}" "${case#*|}" "$(in_index f)"
    done
}

test_lines_in_other_hunks_stay_unstaged() {
    seq 1 20 >g
    commit_all g
    sed -e 's/^2$/two/' -e 's/^18$/eighteen/' g >g.new && mv g.new g
    sh "$stage_lines" g 3,4 >/dev/null
    assertEquals "$(seq 1 20 | sed 's/^18$/eighteen/' | tr '\n' ' ' | sed 's/ $//')" "$(in_index g)"
}

test_staging_never_changes_the_working_tree() {
    edit_f
    before=$(cksum <f)
    sh "$stage_lines" f 1,3 >/dev/null
    assertEquals "$before" "$(cksum <f)"
}

test_staging_reports_how_many_lines_were_staged() {
    edit_f
    assertEquals 'Staged 2 of 3 changed lines in f' "$(sh "$stage_lines" f 2,3)"
}

test_dry_run_prints_the_patch_and_stages_nothing() {
    edit_f
    assertEquals '+d' "$(sh "$stage_lines" -n f 3 | tail -1)"
    assertEquals '' "$(git diff --cached)"
}

# --- Rejecting selections

test_an_id_past_the_last_changed_line_exits_3_and_stages_nothing() {
    edit_f
    assertEquals 3 "$(exit_status sh "$stage_lines" f 4)"
    assertEquals '' "$(git diff --cached)"
}

test_malformed_ids_exit_2() {
    edit_f
    for id in x 3-1 0 1-; do
        assertEquals "id $id" 2 "$(exit_status sh "$stage_lines" f "$id")"
    done
}

test_ids_with_a_base_commit_exit_2() {
    edit_f
    assertEquals 2 "$(exit_status sh "$stage_lines" -b HEAD f 1)"
}

# --- Kinds of file

test_part_of_an_untracked_file_can_be_staged() {
    lines x y z >new
    sh "$stage_lines" new 1,3 >/dev/null
    assertEquals 'x z' "$(in_index new)"
}

test_a_whole_deletion_is_staged_with_all() {
    rm f
    sh "$stage_lines" f all >/dev/null
    assertEquals '' "$(git ls-files f)"
}

test_a_partial_deletion_exits_3() {
    rm f
    assertEquals 3 "$(exit_status sh "$stage_lines" f 1)"
}

test_a_binary_file_exits_3() {
    printf '\000\001' >bin
    commit_all bin
    printf '\000\002' >bin
    assertEquals 3 "$(exit_status sh "$stage_lines" bin all)"
}

test_the_index_keeps_the_file_mode() {
    lines a >x.sh && chmod 755 x.sh
    commit_all x
    lines a b c >x.sh
    sh "$stage_lines" x.sh 1 >/dev/null
    assertEquals 100755 "$(git ls-files --stage x.sh | cut -c1-6)"
}

test_a_mode_change_alone_is_not_listed_as_a_line() {
    lines a >x.sh && chmod 755 x.sh
    commit_all x
    chmod 644 x.sh
    assertEquals 1 "$(exit_status sh "$stage_lines" x.sh)"
}

test_a_file_ending_without_a_newline_is_staged_exactly() {
    printf 'a\nb' >n
    commit_all n
    printf 'a\nb\nc' >n
    sh "$stage_lines" n all >/dev/null
    assertEquals "$(printf 'a\nb\nc' | od -c)" "$(git cat-file blob :n | od -c)"
}

test_replacing_a_last_line_that_had_no_newline_gives_it_one() {
    printf 'a\nb' >n
    commit_all n
    lines a B c >n
    sh "$stage_lines" n 1,2 >/dev/null
    assertEquals "$(printf 'a\nB\n' | od -c)" "$(git cat-file blob :n | od -c)"
}

test_paths_are_relative_to_the_current_directory_and_may_contain_spaces() {
    mkdir 'd i r'
    lines 1 >'d i r/s p.txt'
    commit_all sp
    lines 1 2 3 >'d i r/s p.txt'
    (cd 'd i r' && sh "$stage_lines" 's p.txt' 2 >/dev/null)
    assertEquals '1 3' "$(in_index 'd i r/s p.txt')"
}

# --- Another version of the file (-f)

test_another_version_can_be_staged_in_place_of_the_working_tree() {
    lines a B1 c d >"$sandbox/snap"
    edit_f
    sh "$stage_lines" -f "$sandbox/snap" f all >/dev/null
    assertEquals 'a B1 c d' "$(in_index f)"
    assertEquals 'a B2 c d' "$(tr '\n' ' ' <f | sed 's/ $//')"
}

test_after_staging_another_version_the_rest_of_the_edit_remains() {
    lines a B1 c d >"$sandbox/snap"
    edit_f
    sh "$stage_lines" -f "$sandbox/snap" f all >/dev/null
    assertEquals "    1 -B1
    2 +B2" "$(sh "$stage_lines" f | grep '^ *[0-9]')"
}

test_another_version_identical_to_the_index_exits_1() {
    lines a b c >"$sandbox/snap"
    assertEquals 1 "$(exit_status sh "$stage_lines" -f "$sandbox/snap" f all)"
}

test_another_version_that_does_not_exist_exits_2() {
    assertEquals 2 "$(exit_status sh "$stage_lines" -f "$sandbox/none" f all)"
}

# --- A version from a commit (-r)

test_a_version_from_a_commit_can_be_staged() {
    lines a B1 c >f && commit_all one
    one=$(git rev-parse HEAD)
    lines a B2 c >f && commit_all two
    git reset --quiet HEAD~2
    sh "$stage_lines" -r "$one" f all >/dev/null
    assertEquals 'a B1 c' "$(in_index f)"
    assertEquals 'a B2 c' "$(tr '\n' ' ' <f | sed 's/ $//')"
}

test_a_file_missing_from_the_commit_is_staged_as_a_deletion() {
    git rm --quiet f && commit_all gone
    gone=$(git rev-parse HEAD)
    git reset --quiet HEAD~1
    sh "$stage_lines" -r "$gone" f all >/dev/null
    assertEquals '' "$(git ls-files f)"
}

test_a_new_file_from_a_commit_keeps_its_executable_mode() {
    lines a >x.sh && chmod 755 x.sh && commit_all x
    x=$(git rev-parse HEAD)
    git reset --quiet HEAD~1
    sh "$stage_lines" -r "$x" x.sh all >/dev/null
    assertEquals 100755 "$(git ls-files --stage x.sh | cut -c1-6)"
}

test_a_rev_that_is_not_a_commit_exits_2() {
    assertEquals 2 "$(exit_status sh "$stage_lines" -r nope f all)"
}

test_a_file_and_a_rev_together_exit_2() {
    lines a >"$sandbox/snap"
    assertEquals 2 "$(exit_status sh "$stage_lines" -f "$sandbox/snap" -r HEAD f all)"
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
