---
description: Run a self-learning retrospective and have the primary agent implement the highest-value helpers
---

Use the `self-learn` subagent to produce a self-learning brief for the work just
completed.

Work summary or focus from the user:

$ARGUMENTS

Call the subagent with that summary and the repository state below. If the
summary is empty, tell the subagent to infer the work from the repository state.
The subagent is read-only; do not ask it to edit files.

Repository state:

Working tree:
!`git status --short --branch`

Recent commits:
!`git log --oneline --decorate -10`

All changes against HEAD (stat):
!`git diff --stat HEAD`

Changed and untracked files:
!`git diff --name-status HEAD; git ls-files --others --exclude-standard`

Latest commit summary:
!`git show --stat --oneline --summary HEAD`

After the subagent returns:

- **Analysis-only mode:** if the focus above asks for analysis only, "report
  only", or "do not implement", print the subagent's brief verbatim and stop.
  Do not edit files.
- **Otherwise:**
  1. Treat its "Prompt for the primary agent" section as your next instruction.
  2. Implement the highest-value helper scripts it recommends, following the
     repository conventions in `AGENTS.md`.
  3. Validate the helpers with the commands in the brief and update the relevant
     documentation.
  4. Report what you implemented and what you deliberately skipped.

Do not stop at summarizing the brief outside analysis-only mode. If the
subagent tool is unavailable, produce the same evidence-based brief yourself
without editing files, then follow the same analysis-only/implementation rule.
