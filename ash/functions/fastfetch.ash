function fastfetch --wraps fastfetch -d 'fastfetch, with its logo drawn so tmux can follow it'
    # Inside tmux, fastfetch's kitty image is drawn behind tmux's back:
    # tmux doesn't move its cursor past it, so the text lands above the
    # picture, and near the bottom the picture scrolls the whole window.
    # Instead the image is sent once and drawn with kitty's Unicode
    # placeholders, ordinary characters to tmux: it scrolls and lines up.
    set -l png ~/.config/fastfetch/sketch-tree.png
    set -l cells ~/.config/fastfetch/crewmate.placeholders  # image 211, 24×19
    if set -q TMUX; and test -t 1; and test -f $cells; and not contains -- --logo $argv
        printf '\ePtmux;\e\e_Ga=T,U=1,i=211,f=100,t=f,c=24,r=19,q=2;%s\e\e\\\e\\' (printf %s $png | base64)
        command fastfetch --logo $cells --logo-type file-raw --logo-width 24 --logo-height 19 $argv
    else
        command fastfetch $argv
    end
end
