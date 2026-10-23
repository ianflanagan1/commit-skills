---
name: ianf-commit
description: Split all uncommitted work into atomic commits that each leave the project working, write a message for each in the repository's style, and commit them. Prints only the new commits' hashes and subjects.
disable-model-invocation: true
allowed-tools: Bash(sh *scripts/uncommitted-context.sh*), Bash(echo "exit $?"), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git add:*), Bash(git rm:*), Bash(git reset:*), Bash(sh *scripts/stage-lines.sh*), Bash(sh *scripts/history-versions.sh*), Bash(git ls-files:*), Bash(git rev-parse:*), Bash(git commit:*), Bash(git worktree:*)
---

# Commit

Turn everything uncommitted (staged, unstaged and untracked) into a series of atomic commits, oldest idea first.

If a `cat` command below still shows instead of a file's contents, read that file in `references/` next to this file before going on.

## Gather

Any text after the skill's name is a note from the user about this work, such as a ticket, a reason the diff doesn't show or what to keep out. Use it, but it doesn't override anything below.

Output of `scripts/uncommitted-context.sh`, captured when this skill loaded:

```
!`sh "${CLAUDE_SKILL_DIR}/scripts/uncommitted-context.sh" 2>&1; echo "exit $?"`
```

If the block above still shows the command rather than its output, run `sh <directory containing this file>/scripts/uncommitted-context.sh` from the repo root yourself. Never reuse a result from an earlier run.

- Exit 1: reply `➖ Nothing to commit.` and stop. Make no tool calls.
- Exit 2: reply `⚠️ ` followed by its error, and stop.
- A merge, rebase, cherry-pick or revert in progress: reply `🚧 <Operation> in progress; not committing.` and stop.
- The changes section shows every changed and untracked text file with its changed lines numbered (see Stage). Truncated: run `sh <directory containing this file>/scripts/stage-lines.sh <path>` for the files you need.

## Start

Don't rewrite commits that existed before this run. Before staging anything, record the starting commit for the output: `git rev-parse --short HEAD` (none if the repo has no commits yet). Because the working tree is never touched, `git reset <start>` undoes the whole run.

If the repo has no commits yet, make one commit of everything except what is left out (see Working tree), and skip Plan and Check.

!`cat "${CLAUDE_SKILL_DIR}/references/atomic-commits.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/staging.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/commit-safety.md"`

Write each commit's message for that commit's staged diff alone, by this guide:

!`cat "${CLAUDE_SKILL_DIR}/references/commit-message-guide.md"`

## Output

Start with one line: `✅ Committed.` if every commit was made, or `🛑 Stopped.` if you stopped before the work was all committed. Then one fenced `text` code block holding the new commits, oldest first (`git log --reverse --format='%h %s' <start>..HEAD`, or without the range if the repo had no commits). After it, a line with the undo command, `git reset <start>` (`Undo: none (first commit)` for a repo that had no commits), and, only if they apply, short lines for:
- files left uncommitted, and why
- files you edited to get past a hook, and what you changed (`git reset <start>` doesn't undo these)
- commits whose check wasn't run, or a failure, the message you tried and the fix you propose

Nothing else: no preamble, explanation of the grouping or sign-off.
