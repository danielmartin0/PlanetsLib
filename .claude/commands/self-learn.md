---
description: Run a self-learning retrospective and have the primary agent implement the highest-value helpers
argument-hint: "[focus]"
---

Read `.opencode/commands/self-learn.md` from the repository root and use its
Markdown body as this command's prompt template.

- Replace the canonical template's `$ARGUMENTS` with the arguments passed to
  this command: $ARGUMENTS
- Run each `!` shell block in the canonical template and substitute its output.
- Delegate the retrospective to the `self-learn` subagent.
- Follow the canonical command's analysis-only and implementation branches.

Do not modify the canonical `.opencode` files.
