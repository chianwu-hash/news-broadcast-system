# Codex Project Rules

This file defines how Codex should work in this repo. It is intentionally file-based so Codex, Claude Code, and the user do not need to rely on chat history.

## Project Working Principles

- Read existing project SOPs, `README.md`, `CLAUDE.md`, `SHARED.md`, and relevant `docs/` files before making non-trivial changes.
- Do not guess the current code state from memory or prior chat. Treat the actual files in the repo as the source of truth.
- Verify claims by reading files, running focused commands, or inspecting git state.
- Before editing, understand the existing architecture, shared modules, data flow, and validation path.
- Prefer small, scoped changes that match the current project structure.
- Do not modify business code when the task is only about documentation, handoff, or coordination rules.

## Codex Working Rules

- Use `rg`, `git status`, `git diff`, and direct file reads to verify Claude Code's claims.
- Do not rely only on natural-language summaries. Read the referenced files, functions, or commands.
- Do not overwrite changes from Claude Code, another agent, or the user.
- If a file is already modified, inspect it before editing and preserve unrelated changes.
- If a conflict or suspicious state is found, document the evidence in `docs/development/agent-handoff.md` before proceeding.
- When disagreeing with Claude Code's conclusion, respond with file paths, command output, or concrete code evidence.
- Keep runtime outputs, credentials, `.env`, browser sessions, generated media, and unrelated local files out of commits.

## Collaboration With Claude Code

- Use `docs/development/agent-handoff.md` as the single handoff channel between Codex, Claude Code, and the user.
- Do not require Claude Code to read chat history.
- Before taking over a task, read:
  - `docs/development/agent-handoff.md`
  - `CLAUDE.md`
  - `SHARED.md`
  - any task-specific README, SOP, or docs referenced in the handoff
- Every formal handoff should list:
  - Goal
  - Changed files
  - Files intentionally not touched
  - Validation done
  - Validation still needed
  - Risks or open questions
  - Requested next action
- If Codex and Claude Code may work at the same time, register File Ownership in `docs/development/agent-handoff.md` before editing.
- Do not edit files owned by Claude Code or the user unless the handoff explicitly asks Codex to take over.

## Git Rules

- Stage only files related to the current task.
- Do not stage unrelated untracked files.
- Do not revert user changes or another agent's changes unless the user explicitly asks for it.
- Do not amend commits unless the user explicitly requests it.
- Before commit, run `git status -sb` and inspect the staged diff.
- Commit messages should describe the actual scope of the change.
- Do not push unless the user explicitly asks for push or the task includes push.

## Evidence Standards

When reporting completion or disagreement, include evidence such as:

- File paths
- Relevant function or command names
- Focused command results
- Validation commands and outcomes
- Git status or diff summary

If something is inferred rather than verified, mark it as `待驗證`.
