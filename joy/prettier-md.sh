#!/bin/sh
# Wrap markdown with Prettier, then put GitHub admonition markers
# (> [!NOTE] etc.) back on their own line, since Prettier joins them.
out=$(prettier --prose-wrap always --stdin-filepath "$1") || exit
printf '%s\n' "$out" |
	sed -E 's/^((> ?)+)\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][[:space:]]+(.+)$/\1[!\3]\n\1\4/'
