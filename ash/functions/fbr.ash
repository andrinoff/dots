function fbr -d 'switch to a git branch picked with fzf, newest first'
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo 'fbr: not in a git repository' >&2
        return 1
    end
    set -l branch (git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads refs/remotes \
        | string match -v -r -- '(^|/)HEAD$|^origin$' \
        | fzf --no-sort --preview 'git log --oneline --graph --color=always -30 {}' \
              --preview-window 'right,60%,border-left')
    or return
    git switch (string replace -r '^origin/' '' -- $branch)
end
