## Working tree

**Never change the working tree**, except to fix a small mistake a commit hook catches (see Hook rejections). Don't edit, check out, restore, stash or delete files. Every commit is built in the index; the files on disk stay as the user left them. When you finish, the working tree must be byte-for-byte what it was when you started, apart from those fixes.

Leave out what is not work: secrets (`.env`, keys), build output, logs, editor and OS files, scratch files. Don't commit them and don't edit `.gitignore`; report them in the output.

## Stage

Stage with the scripts next to SKILL.md, never by writing patches or blobs by hand. Below, `<scripts>` is that `scripts` directory.

Start each commit from an index that matches `HEAD` (`git reset --quiet` before the first; after each commit it already does). Stage only that commit's changes, all in one Bash call joined with `&&` and ending with the check below:

```sh
git add -- <path> <path> && sh <scripts>/stage-lines.sh <path> 3-7 12 && git diff --cached --stat && git diff --cached -- <path>
```

The ways to stage:

- **Whole file:** `git add -- <path>`, or `git rm --cached --quiet -- <path>` for a deletion.
- **Some changed lines of a file**, down to single lines within a hunk:

  ```sh
  sh <scripts>/stage-lines.sh <path> 3-7 12        # stage changed lines 3 to 7 and 12
  sh <scripts>/stage-lines.sh <path>               # list the file's changed lines, numbered
  ```

  Numbers are the ones the Gather section shows. They count the file's changed lines against the index, so they stay valid until that file's index entry changes; after you stage part of a file, list it again before using its numbers. Pass all of a file's lines for one commit in one call. An unselected `+` line is left out and an unselected `-` line is kept, so pick a removed line and its replacement together. It refuses a partial deletion or a binary file; stage those whole. Never use `git add --patch` or other interactive commands.
- **An earlier version of a file** (a line changed twice, where the first change belongs to an earlier commit):

  ```sh
  sh <scripts>/history-versions.sh <path>                 # saved versions since the last commit
  sh <scripts>/stage-lines.sh -f <snapshot> <path>        # list what it changes, numbered
  sh <scripts>/stage-lines.sh -f <snapshot> <path> all    # stage it whole, or pick lines
  ```

  `history-versions.sh` lists, oldest first, the distinct versions saved by Claude Code checkpoints and VS Code's local history since the file was last committed, each with its save time and lines added and removed against `HEAD`. `-f` stages from that file instead of the working tree; the file keeps its mode in the index. A later commit then stages the final version from the working tree as usual. If no saved version fits, you may write the intermediate file yourself in your scratchpad directory and stage it with `-f`, but only when the change splits cleanly into two coherent steps; otherwise keep both changes in one commit.

End that call with the check: `git diff --cached --stat`, and `git diff --cached -- <path>` for each file you staged part of, should show exactly this commit's changes.

## Hook rejections

If a hook rejects a commit, nothing was committed and the index still holds that commit's changes. Read the hook's output, work out the cause, and:

- **Your split caused it** (a check fails because the commit uses something a later commit adds, or misses a file it needs): unstage with `git reset --quiet`, replan the remaining commits, and try again.
- **A simple mistake in the code** (a lint or format error, a typo, an unused import, a missing semicolon): fix it in the working tree, stage just the fix into this commit, and try again. These edits are the one exception to never changing the working tree; list them in the output.
- **Anything bigger** (a failing test that points at a real bug, a design problem, a fix that would change behaviour or touch more than a few lines): stop. Leave the remaining work uncommitted and report the error, what causes it and the fix you propose. Don't apply it.

If the same commit is rejected again after two attempts, stop and report as for anything bigger. If a commit fails for another reason (signing fails), don't retry or work around it: stop, leave the remaining work uncommitted, and report.

## Finish

After the last commit, run `git status --short` and the Output section's `git log` in one Bash call, joined with `&&`. The status should list only what you deliberately left out. If anything else remains, say so.
