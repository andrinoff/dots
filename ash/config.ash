# ----------------------------------------------
# ASH config
# ----------------------------------------------

# --- Paths ───
# first one wins (Homebrew comes first so go is found for the line below)
add_path -m /opt/homebrew/bin /opt/homebrew/sbin
add_path -m ~/.local/bin ~/bin ~/local/bin \
    (cached command go env GOPATH)/bin ~/.cargo/bin \
    /Applications/Postgres.app/Contents/Versions/18/bin

# --- Environment ───
set -gx EDITOR joy
set -gx HYPER_URL https://hyper.charmcli.dev
set -gx BAT_THEME ink
set -gx EZA_CONFIG_DIR ~/.config/eza
set -gx FZF_DEFAULT_OPTS "--height=40% --layout=reverse --border=rounded --info=inline \
--prompt='❯ ' --pointer='▶' --marker='✚' \
--color=fg:#cfcbea,bg:-1,hl:#ff2e97:bold,fg+:#ffffff,bg+:#2a1f4a,hl+:#ff2e97:bold \
--color=border:#c43bff,header:#00e1ff,info:#ffd400,marker:#1fff8a,pointer:#ff2e97 \
--color=prompt:#c43bff,spinner:#00e1ff,separator:#2a2640,scrollbar:#c43bff,label:#ff2e97:bold"
status is-interactive; or return
set -gx GPG_TTY (tty)

# --- Look ───
set -g ash_search_rows 12
set -g ash_pager_rows 10
# set -g ash_cursor line
theme choose voltage
integrate starship
enable_transience
function starship_transient_prompt_func;  starship module directory; end
function starship_transient_rprompt_func; starship module time;      end

# function prompt-lines -d 'use a one- or two-line prompt: prompt-lines 1|2'
#     set -q argv[1]; and set -U ash_prompt_lines $argv[1]
#     if test "$ash_prompt_lines" = 2
#         set -e STARSHIP_CONFIG
#     else
#         set -gx STARSHIP_CONFIG ~/.config/ash/starship.toml
#     end
# end
# prompt-lines

# --- Tools ───
set -g FZF_CTRL_R_COMMAND ''
set -g FZF_CTRL_T_COMMAND 'fd --type f --hidden --exclude .git'
set -g FZF_ALT_C_COMMAND 'fd --type d --hidden --exclude .git'
integrate fzf mise z
integrate yazi lazygit

# --- Better defaults ───
alias ls   'eza --icons --group-directories-first'
alias ll   'eza -l --icons --git --group-directories-first'
alias la   'eza -la --icons --git --group-directories-first'
alias tree 'eza --tree --icons --git-ignore'
alias cat  'bat --paging=never'
alias top  btop

# --- Abbreviations --- 
abbr -a g    git
abbr -a gs   'git status -sb'
abbr -a ga   'git add'
abbr -a gaa  'git add -A'
abbr -a gd   'git diff'
abbr -a gds  'git diff --staged'
abbr -a gl   'git log --oneline --graph -20'
abbr -a gp   'git push'
abbr -a gpl  'git pull --rebase'
abbr -a gsw  'git switch'
abbr -a gco  'git switch -c'
abbr -a --set-cursor gc 'git commit -m "%"'
abbr -a lg   lazygit
abbr -a prc  'gh pr create --fill'
abbr -a prv  'gh pr view --web'
abbr -a prs  'gh pr status'
abbr -a prco 'gh pr checkout'
abbr -a dc   'docker compose'
abbr -a e    '$EDITOR'
abbr -a md   'mkdir -p'
abbr -a --position anywhere L '| less -R'
abbr -a --position anywhere C '| clip'
abbr -a --regex '^\.\.+$' --function _dots dotdot   # ... → ../..
function _dots; string repeat -n (math (string length -- $argv) - 1) ../; end

# --- small helpers ───
function mkcd -d 'make a directory and go into it'
    mkdir -p $argv[1]; and cd $argv[1]
end
function root -d 'go to the top of this git repository'
    cd (git rev-parse --show-toplevel)
end

set -g ash_notify_after 10

# --- Keys ───
bind ctrl-o   'clear_images; tmux-sessionizer; commandline -f repaint'
bind ctrl-g   'clear_images; lazygit; commandline -f repaint'
bind ctrl-x,f 'clear_images; fe; commandline -f repaint'
bind ctrl-x,s 'clear_images; fgr; commandline -f repaint'
bind ctrl-x,b 'clear_images; fbr; commandline -f repaint'
bind ctrl-x,c 'clear_images; __ash_fzf_cd; commandline -f repaint'
bind ctrl-x,w explain-line

function clear
    clear_images
    command clear
end

function _images_off --on-event ash_preexec
    set -l cmd (string split ' ' -- $argv[1])[1]
    if contains -- $cmd nvim vim hx joy lazygit lg yazi y btop top less man fzf tmux
        clear_images
    end
end

if not set -q INK_FETCHED; and not contains -- "$TERM_PROGRAM" vscode zed
    set -gx INK_FETCHED 1
    fastfetch
    begin; fortune -o 2>/dev/null; or fortune; end | cowsay -f (random choice (cowsay -l | tail -n +2 | string split -n ' '))
end
