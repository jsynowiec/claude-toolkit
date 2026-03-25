---
paths:
  - "plugins/**/SKILL.md"
---

# Writing SKILL.md Files

Full spec: https://code.claude.com/docs/en/skills

## Frontmatter

**`user-invocable: false`** — only Claude can invoke (internal/background skills). Default allows both.

**`disable-model-invocation: true`** — only the user can invoke (side-effect-heavy skills: deploy, commit). Default allows both.

These are NOT opposites — a skill with neither set can be invoked by both.

**`allowed-tools`** — restricts tools while the skill is active. Minimum necessary. Same concept as `tools` in agent frontmatter — different key name.

**`context: fork`** — runs the skill in an isolated subagent with its own context window. Pair with the `agent` field to specify the subagent type (e.g. `agent: Explore`). Use for long-context tasks or when isolated execution is required.

**`name`** — defaults to the directory name. Only set explicitly if you need a different display name.

**`argument-hint`** — autocomplete hint shown in the slash command palette (e.g. `argument-hint: "[issue-number]"`). Useful for user-invocable skills that take arguments.

**`hooks`** — scoped lifecycle hooks that fire only while this skill is active. Useful for skill-specific pre/post behavior.

**`model` and `effort`** — valid fields, rarely needed. Only tune if the skill consistently requires a specific model or compute level.

## Description

**Avoid overlap:** Trigger phrases that match multiple skills in the same plugin cause ambiguous triggering. Pick phrases specific to this skill's scope.

**Self-contained:** A session that hasn't invoked the skill sees only the description. It must be sufficient on its own to trigger correctly.

## Body

**Don't restate the description** in the body — it's already in context.

**Recommended ending sections** (strong recommendation, not a requirement):
- **Output format** — exact template with field names, not a prose description
- **Rules** — hard invariants the skill must not violate ("Never guess at version numbers — fetch live data")

## Progressive Disclosure

**`SKILL.md` must explicitly reference its supporting files** — Claude won't discover them automatically. Name the file path in prose: "Use the endpoint catalog in `references/known-endpoints.md` to look up...". When `references/` has multiple files, tell Claude which file covers which topic.
