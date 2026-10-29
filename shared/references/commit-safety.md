## Committing

Make each commit in its own Bash call, passing the message on stdin with a quoted heredoc so nothing in it is expanded:

```sh
git commit --quiet --file - <<'EOF'
<message>
EOF
git log -1 --format='%h %s'
```

- Never pass `--no-verify` (or `-n`), and never skip hooks any other way (`core.hooksPath`, `HUSKY=0`, `SKIP=`).
- Don't pass `-a`, paths, `--amend` or `--no-gpg-sign`, and don't push.
