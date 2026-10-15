# Output templates

Flow shows these texts on its cards, or posts them to GitHub under the name of the person who runs Flow. This file gives the shape of each output. The language and the tone are in `.flow/writing.md`. Where a template in `.flow/writing.md` and this file differ, this file applies.

Rules for all templates:

- Leave out a section that has no content. Never write "None" under a heading.
- A text that goes to GitHub (sections 1, 2, 5 and 7) never writes about Flow, Claude, agents, reviewers, sessions, rules or the working files (`.flow/`). The person posts it as their own words.
- Write `n/a: <reason>` for a check that did not run. Never write that a check passed without a summary line that you read.
- Severities: `must` (the PR must not merge with it), `should` (fix before merge, or in a follow-up commit), `nit` (optional), `question` (needs an answer before anyone acts; it does not change a verdict). The tech lead's words for the same ladder: blocker, minor, suggestion, question.
- Categories for a finding: `root-cause`, `requirements`, `correctness`, `reuse`, `layering`, `data-integrity`, `cleanup`, `tests`, `security`, `scalability`, `naming`, `frontend`.

## 1. Review summary

`review.json`, `summary`. Markdown. The person reads the verdict first and posts the review under their own name. The summary says only what needs to happen: the verdict, the findings, the questions and the follow-ups. It does not list the acceptance criteria that are met, the checks, what was examined without a finding, or the deviations that need no action. The counts of findings, the rejected findings and the triage stay in `.flow/work/triage.md`; they are not part of the summary. A clean PR gets the verdict line only.

Verdict words: `approve` = "LGTM", `comment` = "Minor changes required", `request_changes` = "Changes required".

```markdown
## Verdict: Changes required
<One line with the reason: "The write paths still accept a property outside the user's scope." For a clean PR: "LGTM. The fix is in the service, the test fails on main, and every sibling path is covered.">

## Must fix
1. [root-cause] `src/properties/services/x.py:142`: <one line>.
2. [requirements] `src/properties/api/views.py:60`: "<the acceptance line, quoted>" is not met: <what the code does instead, one line>.

## Should fix
1. [cleanup] `src/frontend/components/x.jsx:88`: <one line>.

## Questions
- <The question>? (<who answers: the author | the product owner>)

## Follow-ups (not in this PR)
**CAUTION:** `path:line`: <a security hole that existed before the PR>. Make a work item before the release.
- `path:line`: <a problem that existed before the PR, one line>.

## Warnings
- <the warning, as a fact about the diff: "`src/x.ts` has hidden bidirectional Unicode." Only when there is one.>
```

Each line under Must fix and Should fix has a category in brackets and points at an inline comment on that line.

An acceptance criterion that the code does not meet is a `must` finding with the category `requirements`: one line under Must fix that quotes the criterion, and one inline comment. A criterion that is met gets no line and no comment. A criterion that the code cannot show (a manual step, a screen this review cannot run) is a `question` only when someone has to act on it. A PR with no work item, or a diff that does something the work item and the PR body do not say, is a `question` to the author when it needs an answer; otherwise it is not in the summary.

## 2. Inline review comment

`review.json`, `comments[].body`. Markdown. One comment for each kept finding and for each acceptance criterion that the code does not meet; nothing else gets an inline comment. No severity prefix: the verb gives the severity.

- `must`: the problem and its consequence in one or two sentences, then the fix as an instruction. "Please" is fine. "This is not correct" is fine.
- `should` and `nit`: "I'd recommend ..." or "How about ...?".
- `question`: ask it, with a question mark. Do not make a claim that you cannot show in the code.
- A requirements gap: "Confirm with the product owner: ...". Never bake in a guess.
- Show code when the alternative shape is shorter than a description of it. A one-line fix goes in a `suggestion` block.
- Quote the acceptance line from the work item. Do not give its number. A criterion with no code that attempts it: put the comment on the line where the code should handle it (the view, the service or the form that the criterion names).
- One finding in several files: one comment on the first location, with the list of the other locations.
- Three sentences maximum, plus the code block.

Examples in the tone of the tech lead:

```
`get_or_create` returns `(obj, created)`, so `device.name` raises here. Unpack the tuple.
```

```
This loop runs one query for each property. Please move the lookup before the loop, or add `prefetch_related("devices")` to the queryset.
```

```
I'd recommend `update_or_create` here: the row can exist with changed data, and `get_or_create` then keeps the old values.
```

```
Is this lookup correct? It checks `properties` against profiles. Should it not be `profile_properties`?
```

```
The acceptance line says "A user with view-only access cannot save". This path still saves for that user. Also apply the check in `perform_update`: `src/accounts/api/viewsets.py:212`, `src/accounts/api/viewsets.py:240`.
```

## 3. Triage

`.flow/work/triage.md`. Markdown. The orchestrator writes it after it reads the reviewer files, before it writes the review or corrects the code.

```markdown
# Triage: PR <n> | <change>

Kept <n> must, <n> should, <n> nit, <n> questions. Verdict: <verdict>.

## Kept
1. must [root-cause] `path:line`: <one line> (bug 3, security 1).
2. should [layering] `path:line`: <one line> (security must 2, downgraded: a convention, not a defect).

## Rejected
- bug 5: <reason: wrong premise | the guide permits it | not in the diff>.

## Moved to follow-ups
- security 4: existed before the PR.
```

## 4. Reviewer findings file

`.flow/work/review-<reviewer>.md`. Markdown. Each reviewer writes one file. The first line after the title gives the counts, so that the caller can read them without the rest.

```markdown
# Review: PR <n> | <change>, by <reviewer>

Result: <n> must, <n> should, <n> nit, <n> questions.

## Findings
1. **must** [<category>] `path:line`
   - Scenario: <input or state> -> <wrong result>.
   - Fix: <instruction>.
   - Rule: <guide section, when a guide rule applies>.
   - Also at: `path:line`, `path:line` (when the same finding occurs in more places).
2. **should** [<category>] `path:line`
   - Problem: <one line>.
   - Fix: <instruction>.

## Questions
1. `path:line`: <question>? (<who can answer>)

## Acceptance criteria
- [x] "<criterion>": `path:line`.
- [ ] "<criterion>": finding <n>.
- [?] "<criterion>": <why the code cannot show it>.

## Checked, no finding
- <path or rule>: <what was examined, one line>. (five lines maximum)
```

## 5. PR body

`result.json`, `pr.body`. Markdown. `pr-writer` writes it from the working notes. Flow adds `AB#<id>` when it is missing.

The repository uses "Squash and merge": this body becomes the commit body on `main`, and semantic-release reads it. The footers at the end must each start a paragraph (a blank line before them). `Implements:` gives the tickets to the developer release notes. `Audience: internal` (only for a `feat`, `fix` or `perf` that users cannot see) keeps the change out of the user changelog. Do not start a paragraph or a list item with a type and a colon (`fix: …`): semantic-release reads it as one more change.

```markdown
## Problem
<What the user saw. Descriptive, simple present.>

## Cause
<Bugs only. Simple past: what the code did, and why the symptom occurred, with `file:line`.>

## Change
<What the code does now. One paragraph, or a list with one change per item.>

## Acceptance
| Criterion | Proof | Result |
|---|---|---|
| <the line from the work item> | `<test file>::<test name>` | passes; fails on the base branch |
| inferred: <criterion> (<evidence>) | `<test file>::<test name>` | passes; fails on the base branch |
| <a visual change> | Test procedure, step <n> | not verified |

## Test procedure
<Only when a criterion has no automated proof. Preliminary requirements first. Then numbered steps with one action each. Then the expected result.>

## Checks
- Tests: `<command>`: "<summary line>" | n/a: <reason>.
- Lint and format: `<command>`: <ok> | n/a: <reason>.
- Migrations: `makemigrations --check`: <ok> | n/a: <reason>.
- Not verified: <mobile layout | loading, empty and error states | the visual result>: <why>.

## Decisions
- <Question> -> <choice>. <Reason and evidence>. (one line for each `assume` item and each inferred criterion)

## Follow-ups (not in this PR)
- `path:line`: <a problem found outside the scope, one line>.

## Notices
**CAUTION:** <a migration that cannot be reversed | a data change | a breaking change>, and what to do before the release.
**NOTE:** <information that the reviewer or the release needs>.

Implements: AB#<id>, AB#<id>
Audience: internal   <- only when users cannot see the change
```

## 6. Result summary

`result.json`, `summary` of a first session. Plain text, no Markdown, 4 to 6 lines. Flow shows it on the card.

```
<What was wrong and what the change does. One or two lines.>
Size <S|M|L>. Review rounds: <n>. Must findings corrected: <n>.
Checks: tests <"Ran N tests, OK" | n/a: reason>; lint <ok | n/a: reason>; migrations <ok | n/a: reason>.
Not verified: <list | none>.
Open: <follow-ups, assume items, deferred items | none>.
```

## 7. Follow-up summary

`result.json`, `summary` of a feedback session. Markdown. Flow posts it as a PR comment under "Changes for the review comments:". One item for each comment and each failed check, in the sequence of the feedback.

```markdown
1. **<author>, `path:line`**: "<first sentence of the comment>"
   Done: <what changed>, <sha>.
2. **<author>, `path:line`**: "<first sentence of the comment>"
   Not changed: <reason>.
3. **<author>, conversation**: "<first sentence of the comment>"
   Question: <what is not clear>?
4. **CI `<check>`**: <what failed>
   Done: <the fix>, <sha>.

Checks: tests <"Ran N tests, OK" | n/a: reason>; lint <ok | n/a: reason>.
```

## 8. Dependency PR body

`result.json`, `pr.body` of a dependency session. Markdown.

```markdown
## Change
This PR fixes these Dependabot alerts for `<package>`:
- #<n> <GHSA id> (<severity>): <summary>

Method: <direct version change | parent update | override>. `<manifest>` changes `<package>` from <old> to <new>.

## Behavior changes
<From the changelog between the two versions: each removed or changed API and each changed default value that the code uses, with `file:line`. Or: "None found in <where you looked>.">

## Checks
- Tests: `<command>`: "<summary line>" | n/a: <reason>.
- Build: `<command>`: <ok> | n/a: <reason>.

**NOTE:** <a requirement of the new version, for example a Python version>.

Audience: internal
```

`Audience: internal` stays: a dependency change is not a user-facing change, and the footer keeps it out of the user changelog. The release notes still show it.

## 9. Retro notes

`.flow/retro.jsonl` in the worktree. One JSON object per line. Flow's hook moves the lines into the learnings log (`~/.flow/learnings.jsonl` of the account that runs Flow, `source: "session_note"`) when the session stops, and the weekly skill retro reads them. Write a line for each item of these kinds, when it occurs. The session writes it; the agents do not.

| `note` | When | `text` |
|---|---|---|
| `decision` | the evidence settled a question: an `assume` item, an inferred criterion, a severity that you downgraded | the question, the choice, the evidence |
| `drift` | a guide or a skill says one thing, and the code or the repository does another | the rule, what the code does, which one is right |
| `diversion` | you did not do a step of the skill as written, or an agent did not do what its definition says | the step or the agent, what happened instead, why (a denied command, a missing environment, a contradiction in the text) |
| `question` | a question that you could not settle: a reviewer question, a `blocked` question | the question, and who must answer |
| `rejected` | a reviewer finding that you rejected | the finding, the reason |
| `not_verified` | a check or a criterion that this session could not verify | the item, the reason |

Fields: `note`, `ref` (`PR <n>` or `AB#<id>`), `where` (`file:line`, or the skill step, or the agent), `text` (one to three sentences).

```json
{"note": "diversion", "ref": "PR 1467", "where": "pr-review step 3, bug-reviewer", "text": "The reviewer returned its findings in the chat and did not write review-bug-reviewer.md. It read the instruction not to change files as a rule for its output file too."}
{"note": "drift", "ref": "AB#4576", "where": "backend-style-guide.md section 5", "text": "The guide says that public endpoints get a scoped throttle. The contact form endpoint had none, and the fix added one. The guide is right."}
{"note": "decision", "ref": "AB#4576", "where": "context.md, assume 1", "text": "The item does not say who gets the email. The existing support address in settings.DEFAULT_SUPPORT_EMAIL is the only candidate, so the email goes there."}
```
