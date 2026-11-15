# the files under this directory: ripgrep if it's there, else git, else find
function _files
    if command -q rg
        rg --files --hidden --glob '!.git'
    else if git rev-parse --git-dir >/dev/null 2>&1
        git ls-files --cached --others --exclude-standard
    else
        find . -type d -name .git -prune -o -type f -print | string replace -r '^\./' ''
    end
end
