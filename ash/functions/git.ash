# `git tag v1.2.0` without -m/-F uses the tag name as its message instead of opening the
# editor (tags are signed, so they're always annotated). Everything else goes straight to git.
function git --wraps git --description 'git, with tag messages defaulting to the tag name'
    # skip global options (git -C dir -c key=val tag ...)
    set -l i 1
    while test $i -le (count $argv); and string match -q -- '-*' $argv[$i]
        contains -- $argv[$i] -C -c --git-dir --work-tree --namespace; and set i (math $i + 1)
        set i (math $i + 1)
    end
    if test "$argv[$i]" != tag
        command git $argv
        return
    end
    set -l global
    test $i -gt 1; and set global $argv[1..(math $i - 1)]
    set -l rest $argv[(math $i + 1)..]

    set -l name
    set -l skip_next 0
    for arg in $rest
        if test $skip_next -eq 1
            set skip_next 0
            continue
        end
        switch $arg
            # listing, deleting, verifying, or a message/editor given: leave it alone
            case -l --list -d --delete -v --verify -m '-m*' --message '--message=*' -F '-F*' --file '--file=*' \
                -e --edit -n '-n*' --contains '--contains=*' --no-contains '--no-contains=*' --points-at '--points-at=*' \
                --merged '--merged=*' --no-merged '--no-merged=*' --sort '--sort=*' --format '--format=*' --column '--column=*'
                command git $argv
                return
            # options that take a separate value
            case -u --local-user --cleanup
                set skip_next 1
            case '-*'
            case '*'
                set name $arg
                break
        end
    end

    if test -z "$name"
        command git $argv
        return
    end
    command git $global tag -m $name $rest
end
