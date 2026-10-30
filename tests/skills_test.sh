#!/bin/sh
# Structure of skills/: the shared files each skill inlines and links. Run with `devbox run -- task test`.
#
# The shared references a skill inlines fix its approach to splitting work into commits:
#   agnostic        the user chose what goes in the commit   ianf-commit-message, ianf-commit-staged
#   atomic          atomic-commits.md                        ianf-commit, ianf-commit-rebuild
#                   its own Approach section                 ianf-commit-amend, which builds no commit in the index
#   review-ordered  its own Approach section                 ianf-commit-rebuild-for-squash

# shellcheck source=tests/helpers.sh
. "$(dirname "$0")/helpers.sh"

# inlined skill: the references the skill's SKILL.md inlines, sorted, space-separated.
inlined() {
    # shellcheck disable=SC2016
    sed -n 's,^!`cat "${CLAUDE_SKILL_DIR}/references/\([^"]*\)"`$,\1,p' "$root/skills/$1/SKILL.md" |
        sort | tr '\n' ' ' | sed 's/ $//'
}

# skills_inlining file: the skills whose SKILL.md inlines the reference, space-separated.
skills_inlining() {
    for s in "$root"/skills/*/; do
        s=$(basename "$s")
        case " $(inlined "$s") " in *" $1 "*) printf '%s\n' "$s" ;; esac
    done | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

# loading_commands skill: the commands the skill's SKILL.md runs as it loads, other than cat (which
# needs no rule), one per line, split at "; ", without "2>&1" and with CLAUDE_SKILL_DIR filled in.
loading_commands() {
    # shellcheck disable=SC2016
    sed -n 's/^!`\(.*\)`$/\1/p' "$root/skills/$1/SKILL.md" |
        grep --invert-match '^cat ' |
        sed -e "s,\${CLAUDE_SKILL_DIR},/home/u/.claude/skills/$1,g" -e 's/ 2>&1//g' -e 's/; /\
/g'
}

# allows skill command: whether a Bash rule in the skill's allowed-tools matches the command, as
# Claude Code matches it: "*" matches anything, quotes included, and a legacy "prefix:*" matches
# the prefix alone or followed by a space.
allows() {
    command=$2
    rules=$(sed -n 's/^allowed-tools: //p' "$root/skills/$1/SKILL.md" | sed 's/, /\
/g' | sed -n 's/^Bash(\(.*\))$/\1/p')
    while IFS= read -r rule; do
        [ -n "$rule" ] || continue
        case $rule in
            *:\*) prefix=${rule%:\*}; set -- "$prefix" "$prefix *" ;;
            *) set -- "$rule" ;;
        esac
        for glob; do
            # shellcheck disable=SC2254  # the rule is the pattern
            case $command in $glob) return 0 ;; esac
        done
    done <<EOF
$rules
EOF
    return 1
}

test_agnostic_skills_inline_no_approach() {
    assertEquals 'commit-message-guide.md' "$(inlined ianf-commit-message)"
    assertEquals 'commit-message-guide.md commit-safety.md' "$(inlined ianf-commit-staged)"
}

test_atomic_skills_inline_the_atomic_commit_rules() {
    assertEquals 'ianf-commit ianf-commit-rebuild' "$(skills_inlining atomic-commits.md)"
    assertEquals 'atomic-commits.md commit-message-guide.md commit-safety.md staging.md' "$(inlined ianf-commit)"
    assertEquals 'atomic-commits.md commit-message-guide.md commit-safety.md rework.md staging.md' "$(inlined ianf-commit-rebuild)"
}

test_no_skill_is_allowed_to_run_git_push() {
    assertEquals '' "$(grep --files-with-matches '^allowed-tools:.*git push' "$root"/skills/*/SKILL.md)"
}

test_only_the_rework_skills_may_reset_to_another_commit() {
    for skill in "$root"/skills/*/; do
        skill=$(basename "$skill")
        case $skill in ianf-commit-rebuild*) continue ;; esac
        for command in 'git reset abc123' 'git reset --quiet abc123' 'git reset --hard'; do
            if allows "$skill" "$command"; then fail "$skill allows: $command"; fi
        done
    done
}

test_commit_may_unstage_and_undo_its_own_last_commit() {
    for command in 'git reset --quiet' 'git reset --soft HEAD~1'; do
        allows ianf-commit "$command" || fail "ianf-commit does not allow: $command"
    done
}

test_no_skill_may_delete_a_file_with_git_rm() {
    for skill in "$root"/skills/*/; do
        skill=$(basename "$skill")
        if allows "$skill" 'git rm --quiet -- f'; then fail "$skill allows git rm without --cached"; fi
    done
}

test_the_amend_skill_states_the_atomic_approach_and_commits_only_through_rewrite() {
    assertEquals 'commit-message-guide.md' "$(inlined ianf-commit-amend)"
    assertContains "$(cat "$root/skills/ianf-commit-amend/SKILL.md")" '## Approach: atomic commits'
    for command in 'git commit -F -' 'git reset --quiet' 'git add f' 'git rebase -i HEAD~2'; do
        if allows ianf-commit-amend "$command"; then fail "ianf-commit-amend allows: $command"; fi
    done
    allows ianf-commit-amend "sh /home/u/.claude/skills/ianf-commit-amend/scripts/rewrite.sh apply a b" ||
        fail 'ianf-commit-amend does not allow rewrite.sh'
}

test_the_review_ordered_skill_states_its_own_approach() {
    assertEquals 'commit-message-guide.md commit-safety.md rework.md staging.md' "$(inlined ianf-commit-rebuild-for-squash)"
    assertContains "$(cat "$root/skills/ianf-commit-rebuild-for-squash/SKILL.md")" '## Approach: review-ordered commits'
}

test_no_skill_has_more_than_one_approach() {
    for skill in "$root"/skills/*/; do
        n=$(cat "$skill/SKILL.md" "$skill"/references/*.md | grep --count '^## Approach: ')
        assertTrue "$(basename "$skill") has $n approaches" "[ $n -le 1 ]"
    done
}

test_every_inlined_reference_and_script_exists_in_the_skill() {
    for skill in "$root"/skills/*/; do
        while IFS= read -r f; do
            assertTrue "$(basename "$skill")/$f" "[ -f '$skill/$f' ]"
        done <<EOF
$(sed -n 's,.*CLAUDE_SKILL_DIR}/\([a-z]*/[a-z.-]*\).*,\1,p' "$skill/SKILL.md")
EOF
    done
}

test_every_command_a_skill_runs_as_it_loads_is_in_its_allowed_tools() {
    for skill in "$root"/skills/*/; do
        skill=$(basename "$skill")
        while IFS= read -r command; do
            [ -n "$command" ] || continue
            allows "$skill" "$command" || fail "$skill does not allow: $command"
        done <<EOF
$(loading_commands "$skill")
EOF
    done
}

test_every_skill_runs_in_the_commit_worker_and_is_waited_for() {
    assertTrue 'agents/ianf-commit-worker.md' "[ -f '$root/agents/ianf-commit-worker.md' ]"
    for skill in "$root"/skills/*/; do
        for field in 'context: fork' 'agent: ianf-commit-worker' 'background: false'; do
            grep --quiet --line-regexp "$field" "$skill/SKILL.md" || fail "$(basename "$skill") lacks: $field"
        done
    done
}

test_every_skill_names_its_model_and_effort() {
    for skill in "$root"/skills/*/; do
        grep --quiet '^model: [a-z]' "$skill/SKILL.md" || fail "$(basename "$skill") names no model"
        grep --quiet '^effort: [a-z]' "$skill/SKILL.md" || fail "$(basename "$skill") names no effort"
    done
}

test_every_script_a_skill_tells_claude_to_run_is_in_the_skill() {
    for skill in "$root"/skills/*/; do
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            assertTrue "$(basename "$skill")/scripts/$f" "[ -f '$skill/scripts/$f' ]"
        done <<EOF
$(cat "$skill/SKILL.md" "$skill"/references/*.md | grep --only-matching '<scripts>/[a-z-]*\.sh' | sed 's,<scripts>/,,' | sort --unique)
EOF
    done
}

test_every_link_points_into_shared() {
    while IFS= read -r link; do
        case $(readlink "$link") in
            ../../../shared/*) ;;
            *) fail "$link points outside shared/" ;;
        esac
        assertTrue "$link resolves" "[ -e '$link' ]"
    done <<EOF
$(find "$root/skills" -type l)
EOF
}

test_every_shared_file_is_used_by_a_skill() {
    for f in "$root"/shared/*/*; do
        name=$(basename "$f")
        assertNotEquals "$name unused" '' "$(find "$root/skills" -type l -name "$name")"
    done
}

# shellcheck disable=SC1090
. "$(shunit2_path)"
