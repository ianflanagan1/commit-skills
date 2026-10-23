---
name: ianf-commit-staged
description: Commit the currently staged changes with a message that matches the repository's existing style. Prints only the new commit's hash and subject.
disable-model-invocation: true
allowed-tools: Bash(sh *scripts/staged-context.sh*), Bash(echo "exit $?"), Bash(git diff:*), Bash(git commit:*), Bash(git log:*)
---

# Commit staged

Commit what is staged **now**, with one message written for exactly that: not for unstaged edits, earlier conversation or what you meant to change.

If a `cat` command below still shows instead of a file's contents, read that file in `references/` next to this file before going on.

## Gather

Any text after the skill's name is a note from the user about this change, such as a ticket or a reason the diff doesn't show. Use it, but it doesn't override anything below.

Output of `scripts/staged-context.sh`, captured when this skill loaded:

```
!`sh "${CLAUDE_SKILL_DIR}/scripts/staged-context.sh" 2>&1; echo "exit $?"`
```

If the block above still shows the command rather than its output, run `sh <directory containing this file>/scripts/staged-context.sh` from the repo root yourself. Never reuse a result from an earlier run.

- Exit 1: reply `➖ Nothing staged.` and stop. Make no tool calls.
- Exit 2: reply `⚠️ ` followed by its error, and stop.
- `(a merge is in progress)`: reply `🚧 Merge in progress; not committing.` and stop.
- Truncated diff: run `git diff --cached -- <path>` for files you need to understand. Don't read unstaged or unrelated files.

!`cat "${CLAUDE_SKILL_DIR}/references/commit-message-guide.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/commit-safety.md"`

Commit only the index: don't stage, unstage or stash anything.

If the commit fails (a hook rejects it, signing fails, nothing left to commit), don't retry, work around it or edit any files. Reply with a line `❌ Commit failed.`, then git's error and the message you tried in a fenced `text` code block, then a short line on what caused the failure and the fix you propose. Don't apply the fix.

## Output

On success, reply with a line `✅ Committed.`, then the `git log` line in one fenced `text` code block, and nothing else.
