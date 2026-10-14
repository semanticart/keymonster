#!/bin/bash
# Live check that scroll mode aims at the tmux pane you pick inside kitty.
#
# Opens a throwaway kitty running a six-pane tmux session (mixed vertical and
# horizontal splits) whose panes report the mouse-wheel events they receive,
# then, for every choice of active pane and every pane label, drives scroll mode
# with the DEBUG keysim runner and checks that ONLY the picked pane got the
# wheel. Needs the dev app built (`make app`) and running (`make run`), the
# Accessibility grant, and an unlocked screen, so it is a manual check, not part
# of `make test`. Run it with `make tmuxtest`.
#
#   APP=...         app bundle to drive (default: .build/Key Monster.app)
#   SCROLL_KEY=...  keysim spec of the scroll shortcut (default: 38:ctrl,shift)
set -u

APP=${APP:-.build/Key Monster.app}
SCROLL_KEY=${SCROLL_KEY:-38:ctrl,shift}
SESSION=kmtest-$$
SOCKET=/tmp/kmk-$$
WORK=$(mktemp -d)
LABEL_KEYS=(0 1 2 3 5 4)   # key codes for a s d f g h, the first six labels

pgrep -x keymonster >/dev/null || { echo "keymonster isn't running; run 'make run' first" >&2; exit 2; }
command -v tmux >/dev/null && command -v kitty >/dev/null || { echo "needs tmux and kitty" >&2; exit 2; }

cat > "$WORK/mouse.sh" <<'SH'
#!/bin/sh
printf '\033[?1000h\033[?1006h'
printf 'pane %s ready\n' "$1"
exec cat -v
SH
cat > "$WORK/start.sh" <<SH
#!/bin/sh
M="$WORK/mouse.sh"
tmux new-session -d -s $SESSION -x 150 -y 40 "\$M P0"
tmux split-window -h -t $SESSION "\$M P1"
tmux split-window -v -t $SESSION.1 "\$M P2"
tmux split-window -v -t $SESSION.0 "\$M P3"
tmux split-window -h -t $SESSION.1 "\$M P4"
tmux split-window -v -t $SESSION.3 "\$M P5"
exec tmux attach -t $SESSION
SH
chmod +x "$WORK/mouse.sh" "$WORK/start.sh"

kitty --config NONE -o listen_on=unix:$SOCKET -o allow_remote_control=socket-only \
    -o remember_window_size=no -o initial_window_width=150c -o initial_window_height=42c \
    "$WORK/start.sh" >"$WORK/kitty.log" 2>&1 &
KITTY=$!
cleanup() {
    tmux kill-session -t $SESSION 2>/dev/null
    kill $KITTY 2>/dev/null
    trash "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 20); do tmux has-session -t $SESSION 2>/dev/null && break; sleep 0.5; done
sleep 2
n=$(tmux list-panes -t $SESSION | wc -l | tr -d ' ')
[ "$n" = 6 ] || { echo "expected 6 panes, got $n" >&2; exit 2; }

failures=0
for active in $(seq 0 $((n - 1))); do
    tmux select-pane -t $SESSION.$active
    # Labels run active pane first, then the rest in tmux's order.
    order=($active)
    for i in $(seq 0 $((n - 1))); do [ "$i" != "$active" ] && order+=("$i"); done
    for pos in $(seq 0 $((n - 1))); do
        target=${order[$pos]}
        for i in $(seq 0 $((n - 1))); do tmux respawn-pane -k -t $SESSION.$i "$WORK/mouse.sh P$i"; done
        sleep 0.6
        open -n "$APP" --args keysim delay:0.4 "key:$SCROLL_KEY" delay:1.2 "key:${LABEL_KEYS[$pos]}" \
            delay:0.4 key:38 key:38 delay:0.4 key:53
        sleep 3
        got=""
        for i in $(seq 0 $((n - 1))); do
            c=$(tmux capture-pane -p -J -t $SESSION.$i | grep -o '\[<65' | wc -l | tr -d ' ')
            [ "$c" -gt 0 ] && got="$got $i"
        done
        if [ "$got" = " $target" ]; then
            echo "ok   active=$active label=$pos -> pane $target"
        else
            echo "FAIL active=$active label=$pos expected pane $target, wheel reached:${got:- nothing}"
            failures=$((failures + 1))
        fi
    done
done

[ "$failures" = 0 ] && echo "all $((n * n)) picks landed on the right pane" || echo "$failures failed"
exit $((failures > 0))
