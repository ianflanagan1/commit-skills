## Approach: atomic commits

Every commit holds one reason to change and leaves the project building and working, so any commit can be reverted, cherry-picked or bisected on its own.

## Plan

1. Read the whole diff and every untracked file, then group the changes into commits. One commit is one reason to change: a feature, a fix, a refactor, a rename, a dependency bump, a formatting pass. Keep a change and the tests, docs and config it needs in the same commit, and nothing unrelated.
2. Order the commits so each one works on its own: definitions before their callers, migrations before the code that reads the new schema, a renamed symbol together with every use of it. If two groups can't be separated without breaking the build, merge them.
3. If the work is one coherent change, make one commit. Don't split for the sake of it.

## Check

A commit has to work on its own, but the working tree holds the final state, so tests run there prove nothing about earlier commits. For each commit:

- Read the staged result as a whole: every name it uses is defined in that commit or before it, imports resolve, and nothing refers to a later commit.
- If the repo has a quick build, type-check or test command (from `CLAUDE.md`, `package.json` scripts, a `Makefile` or similar) and it runs without network access or installed dependencies the checkout lacks, run it on the commit in its own Bash call, with the `scripts` directory next to SKILL.md as `<scripts>`:

  ```sh
  sh <scripts>/check-commit.sh HEAD '<command>'
  ```

  It runs the command in a throwaway worktree holding just the commit, removes the worktree, and prints one line on a pass or the end of the command's output on a failure. If it fails, `git reset --soft HEAD~1` to undo that commit (the changes return to the index) and replan. Don't fix code to make it pass.
- Skip the command if it is slow, needs services or would change anything outside the worktree, and say in the output which commits weren't run.
