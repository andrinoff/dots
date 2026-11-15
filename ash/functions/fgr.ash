function fgr -d 'search file contents as you type and open the match in $EDITOR'
    set -l search 'grep -rnI --color=always --exclude-dir=.git -e'
    if command -q rg
        set search 'rg --line-number --no-heading --color=always --smart-case --'
    else if git rev-parse --git-dir >/dev/null 2>&1
        set search 'git grep -nI --color=always --untracked -e'
    end
    set -l hit (fzf --ansi --disabled --query "$argv" \
        --bind "start:reload:$search {q} 2>/dev/null || true" \
        --bind "change:reload:sleep 0.05; $search {q} 2>/dev/null || true" \
        --delimiter : \
        --preview 'bat --color=always --highlight-line {2} {1}' \
        --preview-window 'right,60%,border-left,+{2}+3/3,~3')
    or return
    set -l f (string split -m 2 : -- $hit)
    switch (path basename -- $EDITOR)
        case nvim vim vi
            $EDITOR +$f[2] $f[1]
        case hx helix
            $EDITOR $f[1]:$f[2]
        case '*'
            $EDITOR $f[1]
    end
end
