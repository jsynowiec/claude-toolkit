---
paths:
  - "plugins/**/agents/*.md"
---

# Writing Agent Files

Full spec: https://code.claude.com/docs/en/sub-agents

## Frontmatter

`---` YAML delimiters are required. Both `color` and `model` are required fields — the two most commonly forgotten.

**`skills`** — optional. Array of skill names to preload into the agent's context at startup. Namespaced as `pluginname:skillname` (e.g. `skills: [stackshift:version-checker]`).

## Description Format

**YAML format:** Always use a literal block scalar (`|`) for multi-line descriptions. Never double-quoted strings — `user: "..."` lines inside examples require `\"` escaping in double-quoted strings, making them unreadable. Blank lines inside `|` blocks are safe. `model`, `color`, `tools` go *after* the description block (valid YAML — they are parsed as new keys at the same indent level).

**Existing agents:** If the description is already a double-quoted string, convert it to `|` before adding `<example>` blocks.

**Cover these three trigger types** (2-4 examples, max 6):
- **Explicit**: user directly names the task ("review my skill", "create an agent")
- **Proactive**: Claude detects a situation without being asked (skill just created → trigger review agent)
- **Implicit**: user describes an outcome without naming the method ("is my agent description good?")

**`<commentary>`:** Explain *why* this situation warrants the agent — the reasoning, not a restatement of what the user said. This shapes Claude's triggering judgment.

**Character budget:** Each `<example>` block is ~150-300 chars. Four examples + preamble ≈ 700-1,500 chars. Total limit is 5,000 — verbose examples consume it fast.

## System Prompt

The system prompt body goes after the closing `---` delimiter — it is not part of frontmatter.

**Four output categories** — these describe output style, not a rigid taxonomy; real agents may blend them:
- **Analysis**: Examine code/docs/PRs → categorized findings with `file:line` references
- **Generation**: Create code/tests/docs → follow project conventions, validate output before returning
- **Validation**: Verify criteria → pass/fail determination with violation locations
- **Orchestration**: Coordinate multi-step workflows → phase tracking, dependency management

**Edge cases** belong in the system prompt, not the description.

**`skills` field:** Preloads named skills into the agent's context at startup — use for domain knowledge the agent always needs. See Frontmatter for syntax.

## Tool Restrictions

**Allowlist (`tools`) vs denylist (`disallowedTools`):** Use an allowlist when the agent needs a small, known set of tools. Use a denylist when the agent needs most tools but a few must be blocked. `disallowedTools` is additive to whatever the parent session already blocks.

**Note:** `tools` in agent frontmatter and `allowed-tools` in SKILL.md frontmatter are the same concept under different key names.

**Plugin-level restrictions** (security — cannot be overridden): agents in plugins cannot use `hooks`, `mcpServers`, or `permissionMode`.

**No nesting:** Subagents cannot spawn other subagents. Design orchestration at the parent level — the parent session dispatches agents, not agents dispatching agents.

## Optional Fields

**`memory`** — scope for agent memory files. Recommend `user` for agents that build knowledge across projects. Options: `user` (home dir, cross-project), `project` (version-controlled, `.claude/`), `local` (gitignored, machine-local).

**`context: fork`** — runs the agent in an isolated subagent with its own context window. Use when the task may consume significant context or needs a clean slate.

**`background: true`** — agent runs without blocking the parent session. Use for long-running or fire-and-forget tasks.

**`isolation: worktree`** — agent works in a temporary git worktree. Use for agents that make file changes that shouldn't affect the current workspace.

**`effort`** — compute/token budget (`low`, `medium`, `high`, `max`). Only tune if the agent is consistently over- or under-spending.

**`maxTurns`** — caps the number of turns. Useful for preventing runaway orchestration agents.
