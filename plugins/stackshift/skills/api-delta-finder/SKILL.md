---
name: api-delta-finder
description: Use when moving between major framework, library, or runtime versions to identify removed, renamed, or behavior-changing APIs. Use after fetching release notes to analyze the actual API surface changes and classify their risk.
user-invocable: false
allowed-tools: Read, Glob, Grep, Bash
---

**REQUIRED SUB-SKILL:** Use stackshift:release-notes-retriever to fetch upstream documentation before running this analysis.

Given a source version and a target version of a framework, library, or runtime, identify every API that was removed, renamed, or changed in behavior between the two versions. Produce a classified inventory that the migration plan can act on directly.

## Input

Collect before starting:
- Package or runtime name (e.g., `react`, `express`, `node`)
- Source version (currently in use)
- Target version (upgrading to)
- Changelogs, migration guides, and release notes (fetched by release-notes-retriever)

## Analysis Methods

Use both methods together. Neither is sufficient alone.

### 1. Doc-based analysis

Parse the changelogs and migration guides retrieved by release-notes-retriever.

- Look for sections titled BREAKING CHANGES, Breaking, Deprecations, Removed, or Migration.
- Extract every entry that describes an API removal, rename, signature change, default value change, or semantic change.
- Pay attention to entries that mention "no longer", "removed", "renamed to", "now defaults to", "returns X instead of Y", or "throws instead of".
- Do not skip entries that seem minor. A changed default is a behavior change.

### 2. Type-definition diffing

When `@types/<package>` or built-in `.d.ts` files exist for both versions:

1. Generate a unique run ID (e.g., a short random hex string) to avoid collisions with concurrent runs.
2. Install the type definitions for both versions into separate temporary directories, using the run ID to keep them isolated. Use the project's package manager and install into `/tmp/types-old-<run-id>` and `/tmp/types-new-<run-id>` respectively. Install only the `@types/<package>` (or equivalent built-in type package) at the source-compatible and target-compatible versions — no other dependencies needed.
3. Diff the exported `.d.ts` files between the two directories.
4. Identify every export that was removed, every function whose signature changed, every interface whose properties changed, and every type alias that was redefined.
5. Cross-reference diff results with the doc-based findings. The diff catches changes that changelogs omit; the docs explain intent that diffs cannot convey.

If type packages do not exist for the relevant versions, skip this method and note the gap.

## Severity Classification

Classify every finding into exactly one level:

| Severity | Meaning | Typical action |
|---|---|---|
| `removed` | API deleted, no drop-in replacement exists | Rewrite the call site using the recommended alternative or a custom solution |
| `renamed` | API moved to a different name or import path | Mechanical find-and-replace across the codebase |
| `behavior` | Same signature but different semantics (changed defaults, different return values, altered side effects) | Review every call site; verify assumptions still hold; may need code or test changes |
| `deprecated` | Still works in target version but marked for future removal | Plan the fix; not blocking but should not be deferred indefinitely |

When in doubt between `behavior` and `renamed`, choose `behavior` — it demands more scrutiny.

## Codebase Cross-Reference

After building the findings list, search the local codebase for usage of each affected API:

- Grep for the API name in source files (imports, function calls, property accesses).
- Record which files and approximate line numbers use the API.
- If an API has zero local usage, still include it in the findings but mark usage as "none found".

This step turns a generic changelog summary into a project-specific impact assessment.

## Output Format

Follow the shared output convention exactly.

### Summary

1-2 sentence overview: how many breaking changes found, how many affect this codebase.

### Findings

Present as a table:

| Severity | API | Change | Action | Local usage |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

Sort by severity: `removed` first, then `behavior`, then `renamed`, then `deprecated`.

### Recommendations

Actionable next steps: which changes to address first, which can be batched as mechanical replacements, and which require careful review or user decisions.

## Example Output

```
## Summary

Found 14 breaking changes between Express 4.x and Express 5.x. 6 affect this codebase.

## Findings

| Severity | API | Change | Action | Local usage |
|---|---|---|---|---|
| removed | `app.del()` | Removed. Use `app.delete()` instead. | Replace all `app.del(` calls with `app.delete(`. | src/routes/users.ts:42, src/routes/admin.ts:18 |
| behavior | `req.query` | Now returns a getter that re-parses on each access instead of a cached plain object. | Review any code that mutates or caches `req.query`. | src/middleware/search.ts:15, src/controllers/api.ts:88 |
| renamed | `req.host` | Renamed to `req.hostname`. | Find-and-replace `req.host` with `req.hostname`. | src/middleware/cors.ts:7 |
| deprecated | `res.json(status, body)` | Two-argument form deprecated. Use `res.status(status).json(body)`. | Refactor to chained form. Not urgent but plan it. | none found |

## Recommendations

1. Address the `removed` finding first — `app.del()` calls will throw at runtime.
2. Review the `behavior` change to `req.query` carefully — `src/middleware/search.ts` mutates the query object, which may break under the new getter semantics.
3. Batch the `renamed` change as a single find-and-replace commit.
4. Schedule `deprecated` items for a follow-up pass.
```
