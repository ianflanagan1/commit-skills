#!/bin/sh
# Behaviour of shared/scripts/reference.sh. Run with `devbox run -- task test`.

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

reference=$root/shared/scripts/reference.sh

# A skill laid out as an installed one is: a link to the skill's folder, whose scripts/ and
# references/ hold links to shared files that live elsewhere.
# shellcheck disable=SC2329  # shunit2 calls it, in place of the one in helpers.sh
setUp() {
    sandbox=$(mktemp --directory "${SHUNIT_TMPDIR:-${TMPDIR:-/tmp}}/test.XXXXXX")
    sandbox=$(cd "$sandbox" && pwd -P)
    mkdir -p "$sandbox/shared" "$sandbox/repo/skill/scripts" "$sandbox/repo/skill/references"
    lines '# Guide' 'Write it well.' >"$sandbox/shared/guide.md"
    ln -s "$reference" "$sandbox/repo/skill/scripts/reference.sh"
    ln -s "$sandbox/shared/guide.md" "$sandbox/repo/skill/references/guide.md"
    ln -s "$sandbox/repo/skill" "$sandbox/installed"
    cd "$sandbox" || return 1
}

test_prints_the_named_reference_from_the_skills_references_folder_through_links() {
    assertEquals "$(lines '# Guide' 'Write it well.')" "$(sh "$sandbox/installed/scripts/reference.sh" guide.md)"
}

test_a_reference_the_skill_lacks_exits_2() {
    assertEquals 2 "$(exit_status sh "$sandbox/installed/scripts/reference.sh" missing.md)"
}

test_a_name_with_a_path_exits_2() {
    assertEquals 2 "$(exit_status sh "$sandbox/installed/scripts/reference.sh" ../references/guide.md)"
}

test_no_name_exits_2() {
    assertEquals 2 "$(exit_status sh "$sandbox/installed/scripts/reference.sh")"
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
