#!/bin/sh
cd "$HOME/.config" || exit 1
git add -A
git diff --cached --quiet && exit 0
git commit -m "chore: auto-sync $(date +%F)" && git push
