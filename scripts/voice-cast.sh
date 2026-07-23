#!/bin/bash
# Build the narrated hero screencast, docs/assets/cast/hero-voiced.mp4.
#
# Audio leads, video follows: each line of scripts/cast-narration.txt is
# synthesized first, then the screencast is re-recorded with --min so every
# scene lasts at least as long as its line (plus a lead-in and a breath at the
# end), and finally ffmpeg places each clip at its scene's start — taken from
# the recorder's timings.json — and muxes one file. The silent hero.mp4 the
# website autoplays is untouched.
#
# Overrides: VOICE=<name> picks the say voice, RATE=<wpm> the speaking rate.
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMES=.build/cast-frames-voiced
AUDIO=.build/cast-voice
OUT=docs/assets/cast/hero-voiced.mp4
NARRATION=scripts/cast-narration.txt
RATE="${RATE:-165}"
LEAD=0.45 # narration starts this long after the scene fades in
TAIL=0.6  # the scene keeps breathing this long after its line ends

command -v ffmpeg >/dev/null || { echo "ffmpeg not found: brew install ffmpeg"; exit 1; }

# Best installed voice: Premium beats Enhanced beats the compact default, and
# US English beats other English. Premium/Enhanced voices are one-time
# downloads under System Settings > Accessibility > Spoken Content.
if [ -z "${VOICE:-}" ]; then
  voices=$(say -v '?')
  for want in 'Premium.+ en_US ' 'Premium.+ en_' 'Enhanced.+ en_US ' 'Enhanced.+ en_'; do
    match=$(printf '%s\n' "$voices" | grep -E "$want" | head -1 || true)
    if [ -n "$match" ]; then
      VOICE=$(printf '%s\n' "$match" | sed -E 's/ +[a-z]{2}_[A-Z]{2}.*//')
      break
    fi
  done
  VOICE="${VOICE:-Samantha}"
fi
echo "narrating with: $VOICE (rate $RATE wpm)"

# Synthesize every line and turn its duration into that scene's minimum length.
rm -rf "$AUDIO"
mkdir -p "$AUDIO"
mins=""
scenes=()
while IFS='|' read -r name line; do
  case "$name" in ''|'#'*) continue ;; esac
  say -v "$VOICE" -r "$RATE" -o "$AUDIO/$name.aiff" "$line"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$AUDIO/$name.aiff")
  min=$(awk "BEGIN{printf \"%.2f\", $LEAD + $dur + $TAIL}")
  echo "  $name: ${dur%.*}s of narration -> scene >= ${min}s"
  mins="${mins:+$mins,}$name=$min"
  scenes+=("$name")
done <"$NARRATION"

# Re-record the screencast sized to the narration.
rm -rf "$FRAMES"
swift run keymonster screencast --out "$FRAMES" --min "$mins"

# Place each clip at its scene's start (plus the lead-in) and mux.
timings="$FRAMES/timings.json"
fps=$(plutil -extract fps raw -o - "$timings")
count=$(plutil -extract scenes raw -o - "$timings")
[ "$count" -eq "${#scenes[@]}" ] || {
  echo "narration has ${#scenes[@]} line(s) but the screencast recorded $count scene(s)"
  exit 1
}
inputs=(-framerate "$fps" -i "$FRAMES/frame-%05d.png")
filter=""
mix=""
for i in $(seq 0 $((count - 1))); do
  name=$(plutil -extract "scenes.$i.name" raw -o - "$timings")
  start=$(plutil -extract "scenes.$i.start" raw -o - "$timings")
  [ "$name" = "${scenes[$i]}" ] || {
    echo "scene $i is '$name' on film but '${scenes[$i]}' in $NARRATION"
    exit 1
  }
  delay=$(awk "BEGIN{printf \"%d\", ($start / $fps + $LEAD) * 1000}")
  inputs+=(-i "$AUDIO/$name.aiff")
  filter+="[$((i + 1)):a]adelay=$delay:all=1[a$i];"
  mix+="[a$i]"
done
filter+="${mix}amix=inputs=$count:duration=longest:normalize=0,aresample=44100,apad[aout]"

ffmpeg -y -loglevel error "${inputs[@]}" -filter_complex "$filter" \
  -map 0:v -map "[aout]" \
  -c:v libx264 -pix_fmt yuv420p -crf 24 -preset slow -movflags +faststart \
  -c:a aac -b:a 160k -shortest "$OUT"
echo "Wrote $OUT"
