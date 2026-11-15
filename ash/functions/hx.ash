function hx
    if test (count $argv) -eq 0
        command hx .
    else
        command hx $argv
    end
end
