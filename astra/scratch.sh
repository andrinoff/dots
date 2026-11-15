#!/bin/sh

# --------------------------------------------------------------------
# Scrathpad terminals
# --------------------------------------------------------------------

name=${1-}
case $name in
    '' | *[!A-Za-z0-9_-]*)
        echo "usage: scratch.sh <name> [command...]   (name: letters, digits, '-' and '_')" >&2
        exit 2 ;;
esac
shift

ASTRACTL=${ASTRACTL:-"$HOME/.local/bin/astractl"}
GHOSTTY=${SCRATCH_GHOSTTY:-ghostty}
LEFTOVER_WAIT=5
LAUNCH_WAIT=${SCRATCH_LAUNCH_WAIT:-10}
LOCK_MAX_AGE=60
lock_root=${SCRATCH_LOCK_DIR:-${TMPDIR:-/tmp}}
lock="${lock_root%/}/astra-scratch-$(id -u)-$name.lock"
uid=$(id -u)
title="astra-scratchpad:$name"

note() { [ -n "${SCRATCH_QUIET-}" ] || /usr/bin/logger -t astra-scratch "$name: $*" 2>/dev/null; }
clients() { "$ASTRACTL" -j clients 2>/dev/null; }
on_special() { printf '%s' "$1" | /usr/bin/grep -q "\"name\": \"special:$name\""; }
instances() { /usr/bin/pgrep -u "$uid" -f "$GHOSTTY --title=$title( |\$)" | /usr/bin/tr '\n' ' '; }

find_window() {
    python3 -I -c '
import json, sys
name, title, pids = sys.argv[1], sys.argv[2], {int(p) for p in sys.argv[3:]}
try:
    clients = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
if any(c["workspace"]["name"] == "special:" + name for c in clients):
    print("special")
    sys.exit(0)
for c in sorted(clients, key=lambda c: c.get("focusHistoryID", 0)):
    if (c["pid"] in pids) if pids else (c["class"] == "Ghostty" and c["title"] == title):
        print(c["address"])
        break
' "$name" "$title" "$@"
}

wait_for_window() {
    deadline=$(($(date +%s) + $1 + 1)) pids=$2
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ -n "$pids" ] || pids=$(instances)
        found=$(clients | find_window $pids) || return 1
        if [ -n "$found" ]; then
            printf '%s\n' "$found"
            return 0
        fi
        alive=
        for pid in $pids; do kill -0 "$pid" 2>/dev/null && alive="$alive $pid"; done
        [ -n "$pids" ] && [ -z "$alive" ] && return 1
        sleep 0.1
    done
    return 1
}

show() { "$ASTRACTL" dispatch workspace "special:$name" >/dev/null; }

place() {
    if [ "$1" != special ]; then
        reply=$("$ASTRACTL" dispatch movetoworkspacesilent "special:$name,address:$1" 2>/dev/null)
        if [ "$reply" != ok ]; then
            note "could not move $1 to special:$name: ${reply:-no reply}"
            return 1
        fi
    fi
    if ! on_special "$(clients)"; then
        note "special:$name holds no window: not shown"
        return 1
    fi
    show
}

age() {
    /bin/ps -o etime= -p "$1" 2>/dev/null | /usr/bin/awk '{
        t = $1; d = 0
        if (index(t, "-")) { split(t, x, "-"); d = x[1]; t = x[2] }
        n = split(t, p, ":"); s = 0
        for (i = 1; i <= n; i++) s = s * 60 + p[i]
        print d * 86400 + s
    }'
}

with_terminal() {
    for pid in $1; do /usr/bin/pgrep -P "$pid" >/dev/null 2>&1 && printf '%s ' "$pid"; done
}

kill_instances() {
    for pid in $1; do kill "$pid" 2>/dev/null; done
    i=0
    while [ "$i" -lt 20 ]; do
        alive=
        for pid in $1; do kill -0 "$pid" 2>/dev/null && alive="$alive $pid"; done
        [ -z "$alive" ] && return 0
        sleep 0.1
        i=$((i + 1))
    done
    for pid in $alive; do kill -9 "$pid" 2>/dev/null; done
}

launch() {
    if [ $# -gt 0 ]; then set -- -e "$@"; fi
    open -na Ghostty --args --title="$title" --window-save-state=never --quit-after-last-window-closed=true \
        --keybind=super+n=unbind --keybind=super+t=unbind --keybind=super+enter=unbind --keybind=super+ctrl+f=unbind "$@"
}

take_lock() {
    tries=0
    until mkdir "$lock" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -gt 3 ] && return 1
        holder=$(cat "$lock/pid" 2>/dev/null)
        modified=$(/usr/bin/stat -f %m "$lock" 2>/dev/null) || continue   # released meanwhile: try again
        age=$(($(date +%s) - modified))
        if [ "$age" -le "$LOCK_MAX_AGE" ]; then
            if [ -n "$holder" ]; then
                kill -0 "$holder" 2>/dev/null && return 1   # another press is at work
            elif [ "$age" -le 2 ]; then
                return 1                                    # just created, its pid not written yet
            fi
        fi
        note "taking over a stale lock (holder ${holder:-unknown}, ${age}s old)"
        rm -rf "$lock"
    done
    echo $$ >"$lock/pid"
    trap 'rm -rf "$lock"' EXIT
    trap 'exit 1' HUP INT TERM
}

list=$(clients) || { echo "scratch.sh: astra is not running" >&2; exit 1; }
if on_special "$list"; then
    "$ASTRACTL" dispatch togglespecialworkspace "$name" >/dev/null
    exit 0
fi

take_lock || exit 0
list=$(clients) || exit 1
if on_special "$list"; then
    "$ASTRACTL" dispatch togglespecialworkspace "$name" >/dev/null
    exit 0
fi

running=$(instances)
if [ -n "$running" ]; then
    wait=0
    for pid in $running; do
        a=$(age "$pid")
        [ -n "$a" ] && [ "$a" -lt "$LAUNCH_WAIT" ] && wait=$LEFTOVER_WAIT
    done
    if found=$(wait_for_window "$wait" "$running"); then
        place "$found" || exit 1
        exit 0
    fi
    clients >/dev/null || exit 1
    live=$(with_terminal "$running")
    if [ -n "$live" ]; then
        note "instance(s) $live have a live terminal but astra lists no window of them: nothing done"
        echo "scratch.sh: the $name terminal (pid $live) has no window astra manages; not starting another" >&2
        exit 1
    fi
    note "killing leftover instance(s) without a terminal: $running"
    kill_instances "$running"
fi

launch "$@" || exit 1
if found=$(wait_for_window "$LAUNCH_WAIT" ""); then
    place "$found" || exit 1
    exit 0
fi
fresh=$(instances)
note "no window from the new instance (${fresh:-no process found})"
exit 1
