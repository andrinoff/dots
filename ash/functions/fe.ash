function fe -d 'pick files with fzf and open them in $EDITOR'
    set -l files (_files | fzf --multi \
        --preview 'bat --color=always --style=numbers --line-range=:300 {}' \
        --preview-window 'right,60%,border-left')
    or return
    $EDITOR $files
end
