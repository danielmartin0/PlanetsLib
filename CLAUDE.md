@AGENTS.md

> **Never modify `CLAUDE.md`.** It is a thin Claude Code compatibility shim.
> Redirect every instruction change to `AGENTS.md` instead.

## Claude Code compatibility

This repository keeps one shared instruction set in `AGENTS.md`; the import above
loads it without duplicating the text.

The canonical self-learning definitions live outside Claude Code's config
directories:

- Agent: `.opencode/agents/self-learn.md`
- Command template: `.opencode/commands/self-learn.md`

Claude Code adapters are in `.claude/agents/self-learn.md` and
`.claude/commands/self-learn.md`. They point at the canonical files and do not
copy the prompts.

Helper-script usage is documented in `helper_scripts/README.md`:

@helper_scripts/README.md
