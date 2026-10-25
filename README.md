# commit-skills

Claude Code skills for commit messages. `/ianf-commit-message` suggests a message for whatever is staged when you run it and prints only the message. `/ianf-commit-staged` commits what is staged. `/ianf-commit` splits all uncommitted work into atomic commits, and `/ianf-push` does the same and pushes. `/ianf-re-commit` and `/ianf-re-commit-for-squash` rework a whole branch, committed or not, into atomic commits or into commits ordered for review.

## Why

Asking an agent to "write a commit message" usually gets a message for the whole conversation, the working tree, or a mix of both, wrapped in commentary. This skill looks only at the index, at the moment it runs, and copies the repository's existing style.

## What it does

1. Runs `shared/scripts/staged-context.sh`, which prints recent commit subjects, the staged file list and the staged diff. In Claude Code the script runs as the skill loads and its output goes straight into the prompt, so an empty index gets `➖ Nothing staged.` without any tool calls. Agents without that feature run the script themselves.
2. Matches the style of recent commits: Conventional Commits, ticket prefixes, component tags, subject length. With no clear pattern, it uses an imperative subject of 50 characters or fewer and a body wrapped at 72 only when needed. The first commit in a repo is always `Initialise`.
3. Replies with the message in a single code block. No explanation, no alternatives, no trailers the repo doesn't already use. It never commits.

```
/ianf-commit-message
```

The skills are meant to be run bare. Text typed after the name is treated as a note, for the rare case the diff can't show something, such as a ticket number or the reason for a change. Without one, the skill won't invent a reason that isn't in the diff.

## Committing staged changes

`/ianf-commit-staged` writes the message the same way and then commits the index with it, printing `✅ Committed.` and the new commit's short hash and subject. It commits exactly what is staged: it never stages or unstages files, amends or skips hooks. If the commit fails it prints `❌ Commit failed.`, git's error and the message it tried.

```
/ianf-commit-staged
```

## Committing everything

`/ianf-commit` takes all uncommitted work (staged, unstaged and untracked), splits it into atomic commits ordered so each one works on its own, writes a message for each and commits them. It prints `✅ Committed.` (or `🛑 Stopped.` if a hook or signing failure stops it part way), the new commits and the `git reset <start>` command that undoes the run. In a repo with no commits it makes a single `Initialise` commit instead of splitting.

```
/ianf-commit
```

It builds every commit in the index and never touches the working tree, using two scripts in `shared/scripts/`:
- `stage-lines.sh <path> [ids]` lists a file's changed lines with numbers, or stages only the numbered lines given, down to single lines within a hunk. With `-f <file>` it stages from another copy of the file, such as an earlier version.
- `history-versions.sh <path>` lists the earlier versions of a file saved since its last commit by Claude Code checkpoints and VS Code's local history. Staging one of them first lets a line changed twice go in at its earlier version. Both stores are undocumented, so this is best-effort.

Where it can, it checks each commit by running the repo's quick build or test command in a throwaway `git worktree`.

It leaves out secrets, build output and scratch files and lists them. Its `allowed-tools` pre-approve the git commands it uses while it runs.

## Committing and pushing

`/ianf-push` does exactly what `/ianf-commit` does, then pushes the branch once, and only if every commit was made. With no upstream it sets one with `git push -u`, when the repo has exactly one remote. It never forces, pulls or rebases, and doesn't push a detached `HEAD`. It prints `✅ Pushed.` and where the commits went. If the push is rejected it prints `❌ Push failed.` and git's error, and the commits stay. Only `/ianf-push` pre-approves `git push`. `/ianf-commit` never pushes.

```
/ianf-push
```

## Reworking a branch

`/ianf-re-commit` takes everything on the branch since it started, its commits and any uncommitted work, and rebuilds it as atomic commits the same way `/ianf-commit` does. It's for a branch whose history will be kept: each commit builds and works, so it can be reverted, cherry-picked or bisected. If the commits already fit and nothing is uncommitted, it says so and changes nothing.

`/ianf-re-commit-for-squash` does the same for a branch that will be squash-merged, where the commits are lost on merge and only serve the review. Each mechanical change (a rename with every use of it, a namespace move, a lint-rule pass) gets a commit of its own, ahead of the behaviour changes, so a reviewer can skim it. Commits don't have to build on their own. It also prints a suggested message for the squash merge.

```
/ianf-re-commit
/ianf-re-commit-for-squash
```

The branch's base is where its work started. `shared/scripts/branch-context.sh` takes the first of:
1. The branch or commit you name after the skill (`/ianf-re-commit develop`).
2. On the default branch, or on the branch the setting below names, its upstream, so only unpushed commits are reworked.
3. The setting `commit-skills.base`, for a repo where every feature branch starts from the same branch:

   ```sh
   git config commit-skills.base origin/develop
   ```

4. A guess: the nearest other branch, local or remote-tracking, meaning the one that leaves the fewest commits on this branch. That's usually the branch it was started from. If two branches are equally near but disagree, it asks for the base.

The output names the base and how it was found, with `guessed` for the last.

Both skills refuse a branch with merge commits (rebase it onto its base first) or with commits by someone else, which also catches a base that is too far back. They reset the branch to the base without touching the working tree, then build each commit in the index as `/ianf-commit` does, taking intermediate versions of a file from the original commits with `stage-lines.sh -r <commit>`. They never push. If commits were already pushed, the output says that publishing needs `git push --force-with-lease`. `git reset <start>` undoes a run, leaving any uncommitted work unstaged.

## Tests

The scripts are tested with [shunit2](https://github.com/kward/shunit2), one `tests/<script>_test.sh` per script, each test named for the behaviour it asserts. With [devbox](https://www.jetify.com/devbox), nothing else is needed:

```sh
devbox run test    # shunit2 and shellcheck come from devbox.json
devbox run lint
```

Without devbox, install shunit2 (`brew install shunit2`, `apt install shunit2`) and run `sh tests/run.sh`. It finds shunit2 on `PATH`, or at `$SHUNIT2`. Every test runs in a throwaway repository with `HOME` redirected, so no real history is read.

## Problems

These skills don't report their own problems. If you use [`/ianf-skill-log-problem`](https://github.com/ianflanagan1/skill-authoring), Claude logs problems with any skill, these included, for `/ianf-skill-fix` to fix.

## Approaches

Each skill follows one approach to deciding what goes in a commit:

| Approach | Skills | Rule |
|---|---|---|
| Agnostic | `ianf-commit-message`, `ianf-commit-staged` | The user chose what goes in the commit; only the message is written. |
| Atomic | `ianf-commit`, `ianf-push`, `ianf-re-commit` | Every commit holds one reason to change and leaves the project building and working, so it can be reverted, cherry-picked or bisected on its own. |
| Review-ordered | `ianf-re-commit-for-squash` | The branch will be squash-merged, so commits are grouped for easy review: mechanical changes alone and first, only related work together. They don't have to build. |

## Shared files

Rules and scripts the skills share live once in `shared/`, and each skill links to the files it uses from its own `references/` and `scripts/` folders. Every `references/*.md` file is inlined into the skill when it loads:

- `commit-message-guide.md`: how messages are written (every skill)
- `commit-safety.md`: how to run `git commit`, and never skipping hooks (every skill that commits)
- `staging.md`: building commits in the index without touching the working tree, and handling hook rejections (`ianf-commit`, `ianf-push`, `ianf-re-commit` and `ianf-re-commit-for-squash`)
- `rework.md`: resetting a branch to its base to rebuild it (`ianf-re-commit` and `ianf-re-commit-for-squash`)
- `atomic-commits.md`: the atomic approach: grouping, ordering and checking each commit (`ianf-commit`, `ianf-push`, `ianf-re-commit`)

The review-ordered approach is written into `ianf-re-commit-for-squash/SKILL.md` itself, since nothing else uses it.

The links make a skill's approach visible in its folder, and `tests/skills_test.sh` fails if a skill inlines the files of the wrong approach. When vendoring a skill, copy it with `cp -RL` so the links become real files.

## Scripts

The scripts in `shared/scripts/` are POSIX `sh` and work without an agent. Each prints its usage with `-h`. The three context scripts each gather what one kind of skill needs:

```sh
sh shared/scripts/staged-context.sh            # the staged changes (ianf-commit-message, ianf-commit-staged)
sh shared/scripts/uncommitted-context.sh       # all uncommitted work, lines numbered (ianf-commit, ianf-push)
sh shared/scripts/branch-context.sh [base]     # the branch since its base, lines numbered (both re-commit skills)
```

Each takes `-n <lines>` to truncate the diff after that many lines (default 2000 for `staged-context.sh`, 3000 for the others). Lockfiles and minified files are listed but left out of the diff. They exit with 0 when they print changes, 1 when there is nothing to commit or rework, and 2 on a usage error or outside a git work tree (`branch-context.sh` also when it finds no base).

## Claude Code

Clone to `~/projects/claude/commit-skills`, then link each skill into your skills folder:

```sh
for s in ~/projects/claude/commit-skills/skills/*/; do
    ln -s "${s%/}" ~/.claude/skills/"$(basename "$s")"
done
```

Each is invoked by its folder's name, such as `/ianf-commit`. The `ianf-` prefix keeps them from colliding with other skills of the same name.

You can vendor them instead, so collaborators get them with the repo: `cp -RL skills/<name> .claude/skills/` in your project. Don't install them both ways at once, or Claude will see each skill twice.

## Other agents

`skills/ianf-commit-message/SKILL.md` uses the [Agent Skills](https://agentskills.io) format, so other agents that support skills can load it. Copy it with `cp -RL skills/ianf-commit-message <your agent's skills directory>/` so the linked files become real files alongside `SKILL.md`. Slash-command arguments may behave differently, so just ask in plain language, for example "suggest a commit message for what's staged".
