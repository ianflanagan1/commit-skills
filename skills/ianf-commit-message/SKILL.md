---
name: ianf-commit-message
description: Suggest a commit message for the currently staged changes, matching the repository's existing style. Prints only the message.
disable-model-invocation: true
model: haiku
effort: low
context: fork
agent: ianf-commit-worker
background: false
allowed-tools: Bash(sh *scripts/staged-context.sh*), Bash(echo "exit $?")
---

# Commit message

Write one commit message for what is staged **now**, not for unstaged edits, earlier conversation or what you meant to change.

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
- Truncated diff: run `git diff --cached -- <path>` for files you need to understand. Don't read unstaged or unrelated files.

!`cat "${CLAUDE_SKILL_DIR}/references/commit-message-guide.md"`

## Output

Reply with the message in one fenced `text` code block and nothing else: no preamble, explanation, alternatives, questions or sign-off. Don't run `git commit`.
