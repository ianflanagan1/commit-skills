---
name: ianf-commit-amend
description: Fold uncommitted work into the unpushed commits it belongs to, or make the changes the user asks for to those commits (reword, insert, move lines, split, squash, reorder, drop), leaving every other commit as it was. Prints only the resulting commits' hashes and subjects.
disable-model-invocation: true
allowed-tools: Bash(sh *scripts/amend-context.sh*), Bash(echo "exit $?"), Bash(sh *scripts/rewrite.sh*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git rev-parse:*)
---

# Amend

Change the commits since the base, on a branch or a detached `HEAD`, as little as the work needs: fold uncommitted work into the commits it belongs to, or make the changes the user's note asks for. Commits the plan doesn't touch keep their content, message and author, and those before the first change keep their hashes.

If a `cat` command below still shows instead of a file's contents, read that file in `references/` next to this file before going on.

## Gather

Any text after the skill's name is a note from the user: what to change ("reword the second commit", "move the config change into the commit that added the feature"), a ticket, or what to keep out. If it names the branch or commit the work started from, first run `sh <directory containing this file>/scripts/amend-context.sh <base>` from the repo root and use its output in place of the block below.

Output of `scripts/amend-context.sh`, captured when this skill loaded:

```
!`sh "${CLAUDE_SKILL_DIR}/scripts/amend-context.sh" 2>&1; echo "exit $?"`
```

If the block above still shows the command rather than its output, run `sh <directory containing this file>/scripts/amend-context.sh` from the repo root yourself. Never reuse a result from an earlier run.

- Exit 1: reply `➖ Nothing to amend.` and stop. Make no tool calls.
- Exit 2: reply `⚠️ ` followed by its error, and stop.
- A merge, rebase, cherry-pick or revert in progress: reply `🚧 <Operation> in progress; not amending.` and stop.
- Merge commits: reply `🚫 Not amending: there are merge commits since the base; rebase onto it first.` and stop.
- `(also on branch <name>: …)` in the Warnings: `HEAD` is detached and that branch holds some of the commits, so amending would leave it with the originals. Reply `🚫 Not amending: HEAD is detached and <n> of the commits since the base are also on <name>; switch to <name> and run again, or pass a later base.` and stop.
- No note and nothing uncommitted: reply `➖ Nothing to amend.` and stop.
- The base leaves out commits already on a remote unless the user named it, so only unpushed commits change. Commits by someone else keep their author.

Record the starting commit for the output and for applying the plan: `git rev-parse HEAD`.

## Approach: atomic commits

Every commit holds one reason to change and leaves the project building and working, so any commit can be reverted, cherry-picked or bisected on its own. Amending keeps that true of every commit the plan changes, and of every commit after them.

## Plan

1. With a note, do what it asks, and leave uncommitted work alone unless the note covers it. Without one, fold the uncommitted work in.
2. To fold uncommitted work in, give each hunk to the commit whose reason it serves: a fix to that commit's code, a test or doc it needs, a rename it missed. Each hunk is followed by the commits that last changed its lines (`last changed by:`). Fold it into the newest of those or a later commit; an earlier one conflicts. A hunk whose lines are older than the base, or in a new file, goes wherever its reason fits.
3. Work that serves no commit's reason becomes a new commit, inserted after the commits it depends on, with the same grouping `/ianf-commit` would use.
4. Leave out what is not work: secrets, build output, logs, editor and scratch files. They stay uncommitted; list them in the output.
5. If the work doesn't fit as amendments, because most commits would change or the commits themselves need regrouping, reply `⚠️ Doesn't fit as amendments.`, a short line on why, and `Use /ianf-commit-rebuild instead.` Then stop, having changed nothing.

## Pieces

A piece is a set of changed lines, saved as an object that the plan can apply anywhere. Below, `<scripts>` is the `scripts` directory next to SKILL.md, and paths are from the repository's root.

```sh
sh <scripts>/rewrite.sh piece - <path> <ids> [<path> <ids>]...       # uncommitted lines; prints its hash
sh <scripts>/rewrite.sh list <commit> <path>                         # a commit's changed lines, numbered
sh <scripts>/rewrite.sh piece <commit> <path> <ids> [<path> <ids>]...  # lines of a commit
```

Numbers for uncommitted work are the ones the Gather section shows; they count against `HEAD`, whatever is staged. List a commit's file before picking its lines. Join a file's numbers with commas (`3-7,12`), or pass `all` for the whole file, its deletion or a binary file. Pick a removed line and its replacement together. Making a piece changes nothing in the repository.

## Write the plan

Write the plan to a file in your scratchpad directory, one operation per line, top to bottom. Every commit since the base appears exactly once, as `pick`, `fixup` or `drop`, in its new place. Write each new or changed message to its own file there, by the guide below.

- `pick <commit>`: a commit with this commit's or piece's change. A commit since the base keeps its message and author.
- `fixup <commit>`: fold this commit's or piece's change into the commit before.
- `remove <piece>`: take a piece of a commit back out of the commit before. Its lines stay in the working tree, uncommitted.
- `drop <commit>`: leave a commit since the base out. Its change stays in the working tree, uncommitted.
- `message <file>`: replace the message of the commit before. Every picked piece needs one.

| Change | Plan lines |
|---|---|
| Fold uncommitted lines into C | `pick C`, `fixup <piece>` |
| Reword C | `pick C`, `message <file>` |
| Insert a commit after C | `pick C`, `pick <piece>`, `message <file>` |
| Take lines out of C | `pick C`, `remove <piece of C>` |
| Move lines from C to a later D | `pick C`, `remove <piece of C>`, …, `pick D`, `fixup <piece of C>` |
| Split C | `drop C`, then `pick <piece of C>` and `message <file>` for each part, the parts together all of C |
| Squash D into C | `pick C`, `fixup D`, `message <file>` |
| Reorder | the `pick` lines in the new order |

Carry ticket keys and trailers (`Signed-off-by`, `Co-authored-by`) into a message that replaces or combines them.

## Build

```sh
sh <scripts>/rewrite.sh run <base> <plan>
```

It builds the new commits in memory and changes nothing: not the branch, index or working tree. It prints each resulting commit, oldest first, as `kept` (unchanged) or `new`, then `HEAD <hash>`.

- Exit 2: the plan is invalid; the error names the line. Fix the plan and run again.
- Exit 3: an operation conflicts or would leave a commit empty; the error names the line and the files. Usually a hunk was aimed at a commit older than the one that last changed its lines: move it to a later commit, or make it a new commit, and run again. If it still conflicts after two replans, reply as for a failed check below.

## Check

Commits the script builds don't run commit hooks, just as with `git rebase`, so this check stands in for them. For each `new` commit:

- Read it with `git show <hash>`: it holds one reason to change, every name it uses is defined in it or before it, and nothing refers to a later commit.
- If the repo has a quick build, type-check or test command (from `CLAUDE.md`, `package.json` scripts, a `Makefile` or similar) and it runs without network access or installed dependencies the checkout lacks, run it on the commit in its own Bash call:

  ```sh
  sh <scripts>/check-commit.sh <hash> '<command>'
  ```

  It runs the command in a throwaway worktree holding just the commit, removes the worktree, and prints one line on a pass or the end of the command's output on a failure.

  Skip it if it is slow, needs services or would change anything outside the worktree, and say in the output which commits weren't checked.

If a check fails, replan and build again; don't fix code to make it pass. If you can't make every check pass, reply `❌ Amend failed.`, then the failing command's output or the conflict, unchanged, in a fenced `text` code block. Follow it with a short line on the cause and the fix you propose, and `Nothing was changed.` Don't apply the plan.

## Apply

```sh
sh <scripts>/rewrite.sh apply <start> <HEAD from run>
```

This moves `HEAD` and the index to the new commits, and refuses if `HEAD` has moved since the start. The working tree is never touched: what the plan left out of the commits (dropped and removed changes, work not used) shows as uncommitted. Then `git status --short` should list only that. If anything else remains, say so.

Write each new or changed message for that commit's whole diff, by this guide:

!`cat "${CLAUDE_SKILL_DIR}/references/commit-message-guide.md"`

## Output

Start with the line `✅ Amended.` Then one fenced `text` code block holding the commits since the base, oldest first (`git log --reverse --format='%h %s' <base>..HEAD`). After it, a line `Base: ` and the base as the Gather section names it, a line `Undo: git reset <start>`, and, only if they apply, short lines for:
- commits that were already on a remote: how many, and that publishing needs `git push --force-with-lease`
- what is left uncommitted, and why
- commits whose check wasn't run
- a detached `HEAD`: `On no branch: git switch --create <name> keeps these commits.`

Nothing else: no preamble, explanation of the plan or sign-off.
