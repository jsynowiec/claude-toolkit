---
paths:
  - "plugins/**/hooks/**"
---

# Writing Hook Files

Full spec: https://docs.claude.com/en/docs/claude-code/hooks

## Configuration Format

**Two formats exist — use the right one.** Plugin `hooks/hooks.json` wraps events in a `"hooks"` key: `{"description": "...", "hooks": {"PreToolUse": [...]}}`. User settings (`.claude/settings.json`) put events at the top level directly: `{"PreToolUse": [...]}`. Using the flat format in a plugin `hooks.json` silently does nothing.

**`${CLAUDE_PLUGIN_ROOT}`** — always use this for script paths in plugin hooks. Hardcoded absolute paths break portability across machines and installs.

**Separate declaration from implementation** — put the event config in `hooks/hooks.json` and handler scripts in `scripts/` (or `hooks-handlers/`). Co-locating scripts inside `hooks/` works but muddies the distinction.

## Hook Events

| Event | When | Output key |
|-------|------|-----------|
| PreToolUse | Before tool runs | `hookSpecificOutput.permissionDecision` |
| PostToolUse | After tool completes | `systemMessage` |
| Stop | Agent about to stop | `decision` |
| SubagentStop | Subagent about to stop | `decision` |
| UserPromptSubmit | User submits a prompt | `systemMessage` |
| SessionStart | Session begins | `hookSpecificOutput.additionalContext` |
| SessionEnd | Session ends | — |
| PreCompact | Before context compaction | `systemMessage` |
| Notification | Claude sends a notification | — |

## Hook Types

**Prompt hooks (recommended)** — LLM-driven, context-aware, no bash. Supported only on: Stop, SubagentStop, UserPromptSubmit, PreToolUse. NOT available on PostToolUse, SessionStart, SessionEnd, or PreCompact — use command hooks there.

**Command hooks** — bash commands, deterministic, fast. Available on all events.

**Default timeouts** — command hooks: 60s. Prompt hooks: 30s. Set explicit `timeout` in the hook config when needed.

## Exit Codes (Command Hooks)

**Exit 2 blocks, exit 1 does not.** Only exit code 2 feeds stderr to Claude and blocks tool execution. Exit code 1 is a non-blocking error (shown to user, tool proceeds). Exit 0 allows with stdout in transcript.

**Fail gracefully** — if a hook can't parse its input, `exit 0`. Never block on hook infrastructure errors; only block on real policy violations.

## Hook Input

All hooks receive JSON on stdin:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/project",
  "permission_mode": "ask|allow",
  "hook_event_name": "PreToolUse"
}
```

Event-specific additions: `tool_name` + `tool_input` + `tool_result` (PreToolUse/PostToolUse), `user_prompt` (UserPromptSubmit), `reason` (Stop/SubagentStop).

**Command hook boilerplate:**

```bash
#!/bin/bash
set -euo pipefail
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')
```

Always quote variables (`"$var"`, not `$var`) — unquoted jq output is a shell injection risk.

## Hook Output by Event

**PreToolUse:**

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",
    "updatedInput": {"field": "modified_value"}
  },
  "systemMessage": "Explanation for Claude"
}
```

`updatedInput` rewrites tool input fields before the tool runs. `permissionDecision: "ask"` prompts the user interactively.

**Stop / SubagentStop:**

```json
{
  "decision": "approve|block",
  "reason": "Explanation (fed back as next prompt when blocking)",
  "systemMessage": "Additional context"
}
```

Note: Stop uses `decision: "approve|block"` with string values — not `"allow"/"deny"` like PreToolUse.

**SessionStart context injection:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Instructions injected into every session..."
  }
}
```

**`$CLAUDE_ENV_FILE`** — SessionStart only. Write `export KEY=VALUE` lines here to persist env vars into the session. Not available in any other event.

## Matchers

Matchers are **regex, case-sensitive**. `*` matches all tools. `|` separates alternatives. MCP tools follow the pattern `mcp__<server>__<tool>`.

```
"matcher": "Write"                    // exact
"matcher": "Read|Write|Edit"          // multiple
"matcher": "*"                        // all tools
"matcher": "mcp__.*__delete.*"        // all MCP delete tools
```

Omitting `matcher` on a Stop hook defaults to matching all (same as `"*"`).

## Parallel Execution

**All matching hooks run in parallel** — no ordering guarantee, and hooks cannot read each other's output. Design each hook to be independent. Don't use multiple hooks to form a pipeline.

## Session Isolation

**Hooks fire in every Claude Code session open in that project.** If you store state (loop flags, warning history, iteration counts), always key it by `session_id` from the hook input. Without this, a second terminal window in the same project will interfere with the first session's state.

State storage patterns: `~/.claude/<plugin>_state_<session_id>.json` (cross-project), `.claude/<plugin>.local.md` with YAML frontmatter checked against `session_id`.

## Lifecycle

**No hot reload** — hooks load once at session start. Edits to `hooks.json` or scripts take effect only after restarting Claude Code. Use `/hooks` inside a session to inspect what is currently loaded.

Hook JSON is validated at startup. Invalid JSON in `hooks.json` causes the plugin's hooks to fail silently. Test with `claude --debug` to see loading errors.

## Plugin Restrictions

**Plugin agents cannot declare hooks** — security restriction, cannot be overridden. Hooks must be declared at the plugin level in `hooks/hooks.json`.

**Skills CAN have scoped hooks** — declare in SKILL.md frontmatter under `hooks:`. These fire only while the skill is active, not globally.
