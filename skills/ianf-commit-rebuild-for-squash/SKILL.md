---
name: ianf-commit-rebuild-for-squash
description: Rework the commits since the base and any uncommitted work into commits ordered for easy review, for a branch that will be squash-merged, with a message for each and a suggested squash message. Prints only the new commits and the squash message.
disable-model-invocation: true
model: opus
effort: medium
context: fork
agent: ianf-commit-worker
background: false
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git add:*), Bash(git rm --cached:*), Bash(git reset:*), Bash(sh *scripts/branch-context.sh*), Bash(echo "exit $?"), Bash(sh *scripts/stage-lines.sh*), Bash(sh *scripts/history-versions.sh*), Bash(git ls-files:*), Bash(git rev-parse:*), Bash(git rev-list:*), Bash(git merge-base:*), Bash(git commit:*)
---

# Rebuild for squash

Rework everything since the base, committed or not, into a series of commits a reviewer can read one at a time.

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

## Approach: review-ordered commits

The branch will be squash-merged, so its commits are lost on merge and exist only to make review easy. A commit doesn't have to build or pass tests on its own; don't run checks on it.

## Plan

1. Read the whole diff and every untracked file, then group the changes into commits. Each commit holds only related work.
2. Give each mechanical change a commit with nothing else in it: renaming a symbol with every use of it, moving or renaming a namespace, module or files, a formatting or lint-rule pass, a dependency bump. Many changes of one kind (adding a suffix to every controller class, say) go in one commit. If an original message or the user's note names the command that made the change (`sed`, a codemod, `eslint --fix`), put it in the body so the reviewer can rerun it instead of reading the diff. Don't guess one.
3. Keep tests with the code they cover. Split a large change into steps a reviewer can follow in turn, such as an interface and then its implementations, even when a step doesn't build alone. If a hook that builds or tests rejects such a step, merge it with the step that completes it.
4. Order mechanical commits first, so the reviewer can skim them, then refactors that prepare the way, then behaviour changes in the order a reader needs them.
5. If the work is one small coherent change, make one commit.

!`cat "${CLAUDE_SKILL_DIR}/references/rework.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/staging.md"`

!`cat "${CLAUDE_SKILL_DIR}/references/commit-safety.md"`

Write each commit's message for that commit's staged diff alone, for the reviewer, by this guide:

!`cat "${CLAUDE_SKILL_DIR}/references/commit-message-guide.md"`

## Squash message

After the last commit, write one message for the whole branch, the diff from the base to `HEAD`, by the same guide. The squash merge keeps only this message, so it describes the change as a whole, not the review steps. Don't commit it.

## Output

Start with one line: `✅ Reworked.` if every commit was made, or `🛑 Stopped.` if you stopped before the work was all committed. Then one fenced `text` code block holding the new commits, oldest first (`git log --reverse --format='%h %s' <base>..HEAD`). After it, a line `Base: ` and the base as the Gather section names it, a line `Undo: git reset <start>`, and, only if they apply, short lines for:
- commits that were already on a remote: how many, and that publishing needs `git push --force-with-lease`, which replaces the commits reviewers have already seen
- files left uncommitted, and why
- files you edited to get past a hook, and what you changed (`git reset <start>` doesn't undo these)
- a failure, the message you tried and the fix you propose
- a detached `HEAD`: `On no branch: git switch --create <name> keeps these commits.`

If every commit was made, end with a line `Squash message:` and the message in one fenced `text` code block. Nothing else: no preamble, explanation of the grouping or sign-off.
