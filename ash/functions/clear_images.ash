function clear_images -d 'remove images drawn with the kitty graphics protocol'
    # Inside tmux, fastfetch's logo is drawn with placeholder characters
    # (see fastfetch.ash), which tmux scrolls, clears and hides like any
    # text, so there's nothing to remove.
    set -q TMUX; and return
    printf '\e_Ga=d,d=A,q=2\e\\'
end
