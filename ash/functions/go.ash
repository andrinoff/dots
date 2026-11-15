# `go test` goes through gt (colored, compact: passing tests on one line, failures in full).
# Plain `go test` when output is piped or -json is passed, or when gt isn't installed.
# Everything else goes straight to go. `command go test ...` skips gt.
function go --wraps go --description 'go, with `go test` rendered by gt'
    if test "$argv[1]" = test; and isatty stdout; and not contains -- -json $argv; and command -q gt
        command gt $argv[2..]
        return
    end
    command go $argv
end
