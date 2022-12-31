alias n="nvim"
alias g="git"
alias gst="git status"
alias gp="git pull"

export PATH="$HOME/.cargo/bin:$PATH"

# Start X at login
if status is-login
    if test -z "$DISPLAY" -a "$XDG_VTNR" = 1
        exec startx -- -keeptty
    end
end