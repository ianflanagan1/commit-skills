# commit-skills

Claude Code skills for commit messages. `/ianf-commit-message` suggests a message for whatever is staged when you run it and prints only the message. `/ianf-commit-staged` commits what is staged. `/ianf-commit` splits all uncommitted work into atomic commits. `/ianf-commit-amend` folds uncommitted work into the unpushed commits it belongs to, or makes the changes you ask for to them, and leaves the rest as they were. `/ianf-commit-rebuild` and `/ianf-commit-rebuild-for-squash` rework a whole branch, committed or not, into atomic commits or into commits ordered for review.

They differ in how much history they may change:

| Skill | Existing commits | Use it when |
|---|---|---|
| `/ianf-commit` | none: new commits go on top | the work is new |
| `/ianf-commit-amend` | only the unpushed ones the plan names; the rest keep their content and message | a decision changed after committing, before pushing |
| `/ianf-commit-rebuild`, `/ianf-commit-rebuild-for-squash` | every unpushed one, regrouped from scratch | the branch's history needs reorganising |

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

It leaves out secrets, build output and scratch files and lists them. Its `allowed-tools` pre-approve the git commands it uses while it runs, in the forms it uses: `git reset` only to clear the index or undo its own last commit, and `git rm` only with `--cached`. Anything else, such as resetting the branch to another commit, asks first.

## Pushing

No skill pushes, and none pre-approves `git push`: pushing needs no judgement, so it's left to git. After `/ianf-commit`, run `git push` (`! git push` in Claude Code), or [repo-fix](https://github.com/ianflanagan1/repo-tools#repo-fix), which pushes each branch to its upstream, or with none to the only remote.

## Amending commits

`/ianf-commit-amend` changes the branch's unpushed commits as little as the work needs. Run bare, it folds uncommitted work into the commits it belongs to, and makes new commits, in the right place, for work that belongs to none. With a note, it does what you ask: reword a commit, insert one, take lines out of a commit or move them to another, split, squash, reorder or drop commits.

```
/ianf-commit-amend
/ianf-commit-amend move the config change into the commit that added the endpoint
```

Commits the plan doesn't touch keep their content, message and author, and those before the first change keep their hashes. Every changed commit still builds and works, as with `/ianf-commit`. If the work would change most commits, or needs them regrouped, it says so and suggests `/ianf-commit-rebuild` instead.

Claude decides what goes where. Two scripts in `shared/scripts/` do the rest, deterministically:
- `amend-context.sh` follows each uncommitted hunk with the commits that last changed its lines, found with `git blame`. A hunk can fold into the newest of those or a later commit without conflict, the rule [git-absorb](https://github.com/tummychow/git-absorb) uses.
- `rewrite.sh` carries out the plan. `piece` saves chosen lines, of uncommitted work or of a commit, as an object, without touching anything. `run` builds the plan's commits in memory with `git merge-tree` and `git commit-tree`. `apply` moves `HEAD` to them once Claude has checked each new commit, refusing if `HEAD` has moved since the start.

So a plan that conflicts stops with nothing changed: no rebase is left half done, and the branch, index and working tree are as they were. `git reset <start>` undoes an applied run. Like `git rebase`, the rewritten commits don't run commit hooks; the skill runs the repo's quick check on each new commit instead.

## Rebuilding a branch

`/ianf-commit-rebuild` takes everything on the branch since it started, its commits and any uncommitted work, and rebuilds it as atomic commits the same way `/ianf-commit` does. It's for a branch whose history will be kept: each commit builds and works, so it can be reverted, cherry-picked or bisected. If the commits already fit and nothing is uncommitted, it says so and changes nothing.

`/ianf-commit-rebuild-for-squash` does the same for a branch that will be squash-merged, where the commits are lost on merge and only serve the review. Each mechanical change (a rename with every use of it, a namespace move, a lint-rule pass) gets a commit of its own, ahead of the behaviour changes, so a reviewer can skim it. Commits don't have to build on their own. It also prints a suggested message for the squash merge.

```
/ianf-commit-rebuild
/ianf-commit-rebuild-for-squash
```

Both skills refuse merge commits since the base (rebase onto it first) or commits by someone else, which also catches a base that is too far back. They reset the branch (or a detached `HEAD`) to the base without touching the working tree, then build each commit in the index as `/ianf-commit` does, taking intermediate versions of a file from the original commits with `stage-lines.sh -r <commit>`. They never push. `git reset <start>` undoes a run, leaving any uncommitted work unstaged.

## The base

The amend and rebuild skills change only the commits since the base, which is where the work started. `shared/scripts/branch-base.sh`, which both skills' context scripts share, takes the first of:
1. The branch or commit you name after the skill (`/ianf-commit-rebuild develop`).
2. On the default branch, or on the branch the setting below names, its upstream, so only unpushed commits are reworked.
3. The setting `commit-skills.base`, for a repo where every feature branch starts from the same branch:

   ```sh
   git config commit-skills.base origin/develop
   ```

4. A guess: the nearest other branch, local or remote-tracking, meaning the one that leaves the fewest commits on this branch. That's usually the branch it was started from. If two branches are equally near but disagree, it asks for the base.

Unless you named the base, it then moves past every commit already on a remote, so pushed commits are never changed by default. To change them anyway, name the base; the output then says how many were already pushed, and that publishing needs `git push --force-with-lease`.

The output names the base and how it was found, with `guessed` for the last.

## A detached HEAD

Every skill works on commits that are on no branch, as `git commit` and `git reset` do: they move `HEAD` itself, and no branch moves. Each says so in its output, with `git switch --create <name>` to keep the new commits before you switch away from them.

On a detached `HEAD` there is no current branch, so the base comes from step 1, 3 or 4 above, never from an upstream. The guess still works: detached partway along a branch with new commits on top, that branch is the nearest, so only the new commits are reworked. A rework that would leave a branch holding the originals of the commits it rewrites (a base named further back, say) is refused, since that branch would keep them; switch to the branch and run there instead.

A rebase stopped at an `edit` step also detaches `HEAD`. `/ianf-commit` and the amend and rebuild skills refuse to run while a rebase is in progress; `/ianf-commit-staged` commits, as `git commit` would.

## Tests

The scripts are tested with [shunit2](https://github.com/kward/shunit2), one `tests/<script>_test.sh` per script, each test named for the behaviour it asserts. With [devbox](https://www.jetify.com/devbox), nothing else is needed:

```sh
devbox run -- task test    # shunit2, shellcheck and Task come from devbox.json
devbox run -- task lint
```

Without devbox, install shunit2 (`brew install shunit2`, `apt install shunit2`) and [Task](https://taskfile.dev), and run `task test`. The tests find shunit2 on `PATH`, or at `$SHUNIT2`. Every test runs in a throwaway repository with `HOME` redirected, so no real history is read.

## Problems

These skills don't report their own problems. If you use [`/ianf-skill-log-problem`](https://github.com/ianflanagan1/skill-authoring), Claude logs problems with any skill, these included, for `/ianf-skill-fix` to fix.

## Approaches

Each skill follows one approach to deciding what goes in a commit:

| Approach | Skills | Rule |
|---|---|---|
| Agnostic | `ianf-commit-message`, `ianf-commit-staged` | The user chose what goes in the commit; only the message is written. |
| Atomic | `ianf-commit`, `ianf-commit-amend`, `ianf-commit-rebuild` | Every commit holds one reason to change and leaves the project building and working, so it can be reverted, cherry-picked or bisected on its own. |
| Review-ordered | `ianf-commit-rebuild-for-squash` | The branch will be squash-merged, so commits are grouped for easy review: mechanical changes alone and first, only related work together. They don't have to build. |

## Shared files

Rules and scripts the skills share live once in `shared/`, and each skill links to the files it uses from its own `references/` and `scripts/` folders. Every `references/*.md` file is inlined into the skill when it loads:

- `commit-message-guide.md`: how messages are written (every skill)
- `commit-safety.md`: how to run `git commit`, and never skipping hooks (every skill that commits)
- `staging.md`: building commits in the index without touching the working tree, and handling hook rejections (`ianf-commit`, `ianf-commit-rebuild` and `ianf-commit-rebuild-for-squash`)
- `rework.md`: resetting a branch to its base to rebuild it (`ianf-commit-rebuild` and `ianf-commit-rebuild-for-squash`)
- `atomic-commits.md`: the atomic approach: grouping, ordering and checking each commit (`ianf-commit`, `ianf-commit-rebuild`)

The review-ordered approach is written into `ianf-commit-rebuild-for-squash/SKILL.md` itself, since nothing else uses it. `ianf-commit-amend` states the atomic approach in its own `SKILL.md`, since it builds no commit in the index and checks commits before applying them rather than undoing them.

The links make a skill's approach visible in its folder, and `tests/skills_test.sh` fails if a skill inlines the files of the wrong approach. When vendoring a skill, copy it with `cp -RL` so the links become real files.

## Scripts

The scripts in `shared/scripts/` are POSIX `sh` and work without an agent. Each prints its usage with `-h`. The four context scripts each gather what one kind of skill needs:

```sh
sh shared/scripts/staged-context.sh            # the staged changes (ianf-commit-message, ianf-commit-staged)
sh shared/scripts/uncommitted-context.sh       # all uncommitted work, lines numbered (ianf-commit)
sh shared/scripts/amend-context.sh [base]      # the commits since the base, and uncommitted work traced to them (ianf-commit-amend)
sh shared/scripts/branch-context.sh [base]     # the branch since its base, lines numbered (both rebuild skills)
```

Each takes `-n <lines>` to truncate the diff after that many lines (default 2000 for `staged-context.sh`, 3000 for the others). Lockfiles and minified files are listed but left out of the diff. They exit with 0 when they print changes, 1 when there is nothing to commit, amend or rework, and 2 on a usage error or outside a git work tree (`amend-context.sh` and `branch-context.sh` also when they find no base). Those two find the base with `branch-base.sh`, which they source.

`check-commit.sh <rev> '<command>'` runs a command on one commit in a throwaway worktree, then removes the worktree. It prints one line on a pass and the end of the command's output on a failure, and exits 1 on a failure. The skills that check each commit run it once per commit.

`rewrite.sh` needs git 2.40 or later, for `git merge-tree --merge-base`.

`reference.sh <name>` prints one of the skill's `references/` files, which is how each `SKILL.md` inlines them as it loads. Claude Code blocks a load-time `cat` of a file outside the session's working directories, whatever the skill's `allowed-tools` say, and a linked skill's references resolve into this repository; a script the skill's `allowed-tools` permit isn't blocked.

## Claude Code

Clone to `~/projects/claude/commit-skills`, then link each skill into your skills folder, and the agent they run in into your agents folder:

```sh
for s in ~/projects/claude/commit-skills/skills/*/; do
    ln -s "${s%/}" ~/.claude/skills/"$(basename "$s")"
done
mkdir -p ~/.claude/agents
ln -s ~/projects/claude/commit-skills/agents/ianf-commit-worker.md ~/.claude/agents/
```

Each skill runs as a subagent, `ianf-commit-worker` (`context: fork` in its frontmatter), so it starts without your conversation's history and only its output comes back. The agent has only the file and Bash tools, so each turn carries no other tool definitions. The skills wait for it (`background: false`), as a script calling `claude --print` needs. Each skill names its model: Haiku at low effort for `/ianf-commit-message` and `/ianf-commit-staged`, Sonnet at medium effort for `/ianf-commit`, and Opus at medium effort, Claude Code's own default for it, for amending and rebuilding, where the planning is hardest.

Each is invoked by its folder's name, such as `/ianf-commit`. The `ianf-` prefix keeps them from colliding with other skills of the same name.

You can vendor them instead, so collaborators get them with the repo: `cp -RL skills/<name> .claude/skills/` and `cp agents/ianf-commit-worker.md .claude/agents/` in your project. Don't install them both ways at once, or Claude will see each skill twice.

## Other agents

`skills/ianf-commit-message/SKILL.md` uses the [Agent Skills](https://agentskills.io) format, so other agents that support skills can load it. Copy it with `cp -RL skills/ianf-commit-message <your agent's skills directory>/` so the linked files become real files alongside `SKILL.md`. Slash-command arguments may behave differently, so just ask in plain language, for example "suggest a commit message for what's staged".
