#!/usr/bin/env bash
# SessionStart hook of the plugin repository: prints one line when a skill retro is due.
# Reads the learnings log of the account that runs Flow (FLOW_LEARNINGS overrides the path) and retros/.cutoff.
log=${FLOW_LEARNINGS:-/Users/claudebot/.flow/learnings.jsonl}
here=$(cd "$(dirname "$0")/../../.." && pwd)
[ -r "$log" ] || exit 0
cutoff=$(cat "$here/retros/.cutoff" 2>/dev/null)
read -r new notes <<< "$(python3 -I - "$log" "$cutoff" <<'PY'
import json, sys
log, cutoff = sys.argv[1], sys.argv[2]
n = notes = 0
for line in open(log, errors="replace"):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if e.get("ts", "") > cutoff:
        n += 1
        notes += e.get("source") == "session_note"
print(n, notes)
PY
)"
last=$(ls "$here"/retros/2*.md 2>/dev/null | sort | tail -1)
last=${last:+$(basename "$last" .md)}
if [ -n "$last" ]; then
  days=$(( ( $(date +%s) - $(date -j -f %Y-%m-%d "$last" +%s 2>/dev/null || echo 0) ) / 86400 ))
else
  days=999
fi
if [ "${new:-0}" -gt 0 ] && { [ "$days" -ge 7 ] || [ "$new" -ge 20 ]; }; then
  if [ -n "$last" ]; then since="the last retro ($last, $days days ago)"; else since="the start (no retro yet)"; fi
  echo "skill-retro: $new new learnings entries ($notes session notes) since $since. Run /skill-retro."
fi
exit 0
