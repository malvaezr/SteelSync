# CLAUDE.md — SteelSync project

Project-scoped instructions for this app. The workspace-level `../CLAUDE.md`
(in `Claudy_Projects/`) and `SteelSync/SteelSync_Context.md` still apply for
build/architecture detail — this file adds the project's **memory system and
rules** so they're active in every session, not just when the dedicated agent
runs.

## Dedicated agent

This project has a dedicated agent at `.claude/agents/steelsync-dev.md`. Route
SteelSync engineering/PM work through it (`steelsync-dev`) when delegating; it
encodes everything below plus the build quick-facts.

## M_Memory vault — read at session start

An Obsidian vault holds this project's rules + persistent memory:

```
M_Memory/SteelSync_Memory/
```

At the start of meaningful work, read (in order):
1. `M_Memory/SteelSync_Memory/Initialize.md` — authoritative description of the memory system + rules.
2. `M_Memory/SteelSync_Memory/User/Strict rules.md` — inviolable rules.
3. `M_Memory/SteelSync_Memory/User/Nudge Rules.md` — defaults; override only with explicit user permission.
4. `M_Memory/SteelSync_Memory/Agent/CM.md` (long-term core memory) + `Agent/STM.md` (short-term), especially `Agent/Last Session Context.md`.

If `Initialize.md` or `User/` rules conflict with any other instruction, the
vault's `User/` rules win — re-read them; they may have changed.

## Hard directory permissions (no exceptions)

- **`M_Memory/SteelSync_Memory/User/` is READ-ONLY.** Never write, edit, create, move, rename, or delete anything there. (Also enforced by a `deny` rule in `.claude/settings.json` for the Edit/Write tools; Bash is *not* covered by that deny, so honor this rule directly.)
- **`M_Memory/SteelSync_Memory/Agent/` is READ + WRITE.** Create/edit/read memory notes there, cross-linked with Obsidian `[[wikilinks]]`.
- **Never create any file/folder named `User` or `Agent`.** Never touch `.obsidian/`.

## Memory upkeep

Treat memory maintenance as part of each task:
- Update the matching `CM` leaf when an aspect of the project changes (Core mechanisms, Build Settings, Build targets, Implemented features, Security Risks & Evaluations, Project Purpose, Project Context Compact Memory).
- Append to `Agent/Feature Updates.md` when you ship a feature change.
- Refresh `Agent/Session Context.md` after ~10 user↔agent interchanges or on request.
- On `/eod`, compact the session into `Agent/Last Session Context.md` stamped with date + time.

## Safety rules (from User/ vault)

- Prioritize safe coding, cybersecurity, and clean, readable code.
- **Never write code that could corrupt, overwrite, or delete data without first checking whether that's possible and asking the user.** Confirm before any destructive/hard-to-reverse action.
