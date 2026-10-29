---
name: ianf-commit-rebuild
description: Rework the commits since the base, on a branch or a detached HEAD, and any uncommitted work into atomic commits that each leave the project working, with a message for each in the repository's style. Prints only the new commits' hashes and subjects.
disable-model-invocation: true
model: opus
effort: medium
context: fork
agent: ianf-commit-worker
background: false
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git add:*), Bash(git rm --cached:*), Bash(git reset:*), Bash(sh *scripts/branch-context.sh*), Bash(echo "exit $?"), Bash(sh *scripts/stage-lines.sh*), Bash(sh *scripts/history-versions.sh*), Bash(git ls-files:*), Bash(git rev-parse:*), Bash(git rev-list:*), Bash(git merge-base:*), Bash(git commit:*)
---

# Rebuild

Rework everything since the base, committed or not, into a series of atomic commits, oldest idea first.

If a `cat` command below still shows instead of a file's contents, read that file in `references/` next to this file before going on.

## Gather

Any text after the skill's name is a note from the user about this work, such as a ticket, a reason the diff doesn't show or what to keep out. If it names the branch or commit the work started from, first run `sh <directory containing this file>/scripts/branch-context.sh <base>` from the repo root and use its output in place of the block below. Use the rest of the note, but it doesn't override anything below.

Output of `scripts/branch-context.sh`, captured when this skill loaded:

```
!`sh "${CLAUDE_SKILL_DIR}/scripts/branch-context.sh" 2>&1; echo "exit $?"`
```

If the block above still shows the command rather than its output, run `sh <directory containing this file>/scripts/branch-context.sh` from the repo root yourself. Never reuse a result from an earlier run.

- Exit 1: reply `➖ Nothing to rework.` and stop. Make no tool calls.
- Exit 2: reply `⚠️ ` followed by its error, and stop.
- A merge, rebase, cherry-pick or revert in progress: reply `🚧 <Operation> in progress; not reworking.` and stop.
- The changes section shows every file changed since the base, committed or not, with its changed lines numbered (see Stage). Truncated: once the index is reset to the base, run `sh <directory containing this file>/scripts/stage-lines.sh <path>` for the files you need.

!`cat "${CLAUDE_SKILL_DIR}/references/atomic-commits.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/rework.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/staging.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/commit-safety.md"`

Write each commit's message for that commit's staged diff alone, by this guide:

!`cat "${CLAUDE_SKILL_DIR}/references/commit-message-guide.md"`

## Output

Start with one line: `✅ Reworked.` if every commit was made, or `🛑 Stopped.` if you stopped before the work was all committed. Then one fenced `text` code block holding the new commits, oldest first (`git log --reverse --format='%h %s' <base>..HEAD`). After it, a line `Base: ` and the base as the Gather section names it, a line `Undo: git reset <start>`, and, only if they apply, short lines for:
- commits that were already on a remote: how many, and that publishing needs `git push --force-with-lease`
- files left uncommitted, and why
- files you edited to get past a hook, and what you changed (`git reset <start>` doesn't undo these)
- commits whose check wasn't run, or a failure, the message you tried and the fix you propose
- a detached `HEAD`: `On no branch: git switch --create <name> keeps these commits.`

Nothing else: no preamble, explanation of the grouping or sign-off.
