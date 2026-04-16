# hj Hand-Skill Replacement Todo List

## Goal

Replace the shell/plumbing portions of the `atelier:hand*` skills with `hj` where that is already safe, and isolate the remaining gaps that still require skill-side logic.

## Phase 1 — Safe Replacements

- [ ] Update `skills/handup/SKILL.md` to use `hj handup` as the default implementation for:
  - HANDOFF sweep
  - TODO/FIXME sweep
  - `HANDUP.json` generation
  - SQLite checkpointing
  - summary rendering
- [ ] Update `skills/handon/SKILL.md` to use `hj detect` for handoff discovery instead of shell-first path resolution.
- [ ] Update `skills/handon/SKILL.md` to use `hj handoff-db query` for SQLite status lookup.
- [ ] Update `skills/handoff/SKILL.md` to use `hj detect` for file resolution and migration preflight.
- [ ] Update `skills/handoff/SKILL.md` to use `hj close` for:
  - writing `HANDOFF.yaml`
  - writing `.state.yaml`
  - rendering `.ctx/HANDOFF.md`
  - syncing SQLite
- [ ] Update `skills/handoff/SKILL.md` to use `hj refresh` for `.ctx` bootstrap and managed `.gitignore` setup.
- [ ] Update agent prompt variants under `skills/hand*/agents/` so they reference `hj` commands instead of shell snippets where applicable.

## Phase 2 — Keep In Skill

- [ ] Keep `handon` triage logic in the skill for now:
  - P0 validation and stop points
  - P1 autonomous execution policy
  - P2 delegation rules
  - review-on-wake handling for unreviewed `human-edit` entries
- [ ] Keep `handoff` decision logic in the skill for now:
  - deciding current build/test status
  - applying immutability rules to `items`
  - deciding what belongs in `log`
  - commit policy
- [ ] Keep `handdown` fully skill-side until `hj` has explicit support for:
  - cross-project annotation write-back
  - `extra` entry append rules
  - per-repo commit flow
- [ ] Keep `handover` fully skill-side until `hj` has explicit support for:
  - prose report generation
  - Mermaid diagrams
  - `.ctx/HANDOVER.md` output

## Phase 3 — Required Fixes Before Broader Replacement

- [ ] Fix `hj` SQLite upsert pruning so removed handoff items no longer linger in the local DB.
- [ ] Decide whether `skills/handoff/SKILL.md` should continue to require `handoff-reconcile` or switch policy to `hj reconcile`.
- [ ] If `hj reconcile` becomes the default, verify parity with the Valerie bridge for:
  - capture behavior
  - orphan detection
  - closed-upstream handling
  - failure semantics
- [ ] Add a stable install/update path for the `handoff-*` and `handup` shims so PATH and workspace binaries do not drift.

## Definition of Done

- [ ] `handup`, `handon`, and `handoff` docs point at `hj` for all safe plumbing operations.
- [ ] No skill doc claims behavior that the backing command does not implement.
- [ ] `hj` SQLite state matches structured handoff state after item removal.
- [ ] Reconcile policy is explicit: either Valerie bridge remains authoritative or `hj reconcile` is approved as the replacement.
- [ ] All affected skill agent prompts are updated to match the new command paths.
