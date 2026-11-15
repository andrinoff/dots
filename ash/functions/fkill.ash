function fkill -d 'pick processes with fzf and end them (fkill -9 to force)'
    set -l pids (ps -eo pid,user,%cpu,%mem,comm -r | fzf --multi --header-lines=1 \
        | string replace -r '^\s*(\d+).*' '$1')
    or return
    kill $argv $pids
end
