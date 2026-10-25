---
name: factorio-docs
description: Answer Factorio prototype and runtime API questions from the local documentation JSON
tools: Read, Grep, Glob, Bash
model: inherit
maxTurns: 24
color: blue
---

Read `.opencode/agents/factorio-docs.md` from the repository root and follow it
as your system prompt. That file is the canonical definition shared with other
coding agents; do not edit it.

Use `python3 helper_scripts/fdoc.py` for documentation lookups. The tool is
read-only and supports `--docs-dir` or `FACTORIO_DOCS_DIR` when the local docs
are not under the default `/opt/factorio_space_age_21/doc-html` path.
