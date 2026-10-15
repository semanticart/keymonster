#!/bin/bash
# Live check that hint mode measures kitty's window padding, including padding
# changed at runtime with `kitten @ set-spacing`.
#
# Opens a throwaway kitty, sets several paddings through its remote-control
# socket, triggers hint mode with the DEBUG keysim runner each time, and reads
# the padding keymonster logged (`kitty padding: measured L T R B`). Needs the
# dev app built and running (`make run`), the Accessibility grant, and an
# unlocked screen, so it is a manual check, not part of `make test`. Run it
# with `make paddingtest`.
#
#   APP=...       app bundle to drive (default: .build/Key Monster.app)
#   HINT_KEY=...  keysim spec of the hint shortcut (default: 41:ctrl)
set -u

APP=${APP:-.build/Key Monster.app}
HINT_KEY=${HINT_KEY:-41:ctrl}
SOCKET=/tmp/kmp-$$
PADDINGS=(0 60 120)
# Kitty leaves the part of the window that doesn't fill a whole cell blank after
# the grid, and that remainder can't be told from padding, so each side can read
# up to half a cell (about 9pt tall) high.
TOLERANCE=10

pgrep -x keymonster >/dev/null || { echo "keymonster isn't running; run 'make run' first" >&2; exit 2; }
command -v kitty >/dev/null && command -v kitten >/dev/null || { echo "needs kitty" >&2; exit 2; }

kitty --config NONE -o listen_on=unix:$SOCKET -o allow_remote_control=socket-only \
    -o remember_window_size=no -o initial_window_width=120c -o initial_window_height=40c \
    sleep 600 >/dev/null 2>&1 &
KITTY=$!
cleanup() { kill $KITTY 2>/dev/null; }
trap cleanup EXIT

# kitty appends its pid to a listen_on set through the config.
TO=""
for _ in $(seq 20); do
    for candidate in "unix:$SOCKET" "unix:$SOCKET-$KITTY"; do
        kitten @ --to "$candidate" ls >/dev/null 2>&1 && TO=$candidate
    done
    [ -n "$TO" ] && break
    sleep 0.5
done
[ -n "$TO" ] || { echo "couldn't reach the throwaway kitty's socket" >&2; exit 2; }

failures=0
for padding in "${PADDINGS[@]}"; do
    kitten @ --to "$TO" set-spacing padding=$padding || { echo "set-spacing failed" >&2; exit 2; }
    sleep 0.5
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $KITTY) to true"
    sleep 1
    since=$(date '+%Y-%m-%d %H:%M:%S')
    open -n "$APP" --args keysim delay:0.4 "key:$HINT_KEY" delay:1 key:53
    sleep 3
    line=$(/usr/bin/log show --start "$since" --info --debug \
        --predicate 'subsystem == "keymonster" AND category == "hints.kitty"' 2>/dev/null |
        grep 'kitty padding' | tail -1)
    read -r left top right bottom <<<"$(sed -n 's/.*measured \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\)$/\1 \2 \3 \4/p' <<<"$line")"
    if [ -z "${left:-}" ]; then
        echo "FAIL padding=$padding no measurement logged (${line:-no log line})"
        failures=$((failures + 1))
        continue
    fi
    bad=$(awk -v p="$padding" -v t="$TOLERANCE" -v l="$left" -v tp="$top" -v r="$right" -v b="$bottom" \
        'function d(x) { return x > p ? x - p : p - x }
         BEGIN { print (d(l) > t || d(tp) > t || d(r) > t || d(b) > t) }')
    if [ "$bad" = 0 ]; then
        echo "ok   set-spacing padding=$padding -> measured $left $top $right $bottom"
    else
        echo "FAIL set-spacing padding=$padding but measured $left $top $right $bottom"
        failures=$((failures + 1))
    fi
done

[ "$failures" = 0 ] && echo "padding measured correctly for ${PADDINGS[*]}" || echo "$failures failed"
exit $((failures > 0))
