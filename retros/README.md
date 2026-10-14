# Skill retros

One file per retro (`YYYY-MM-DD.md`): the patterns in the learnings log, the proposals, and what was applied. `.cutoff` holds the `ts` of the last log entry that a retro read.

The raw log is `~/.flow/learnings.jsonl` of the account that runs Flow. Sessions add their own notes to it (decisions, drifts, diversions, questions, rejected findings, items not verified) through `.flow/retro.jsonl` and Flow's hook (templates section 9). People add corrections through the Flow dashboard (review edits, PR edits, follow-up edits, session input, card actions).

Run `/skill-retro` in this repository about one time each week. The SessionStart hook of this repository says when a retro is due.
