---
name: upgrade-plan-generator
description: Use when you have completed analysis (version checks, API deltas, impact mapping, test gaps) and need to synthesize findings into an ordered, step-by-step migration plan that can be executed incrementally with verification at each step.
user-invocable: false
allowed-tools: Read
---

Synthesize analysis outputs into a structured, dependency-aware migration plan. The plan must be executable by agents following the superpowers:executing-plans or superpowers:subagent-driven-development workflows.

**REQUIRED INPUT:** Output from stackshift:version-checker, stackshift:api-delta-finder, the dependency-impact-map agent, and stackshift:test-gap-analyzer.

**OUTPUT COMPATIBLE WITH:** superpowers:executing-plans and superpowers:subagent-driven-development

## Gathering Inputs

Collect and organize four analysis artifacts before generating the plan:

1. **Version checker findings** -- current vs target versions for runtime, frameworks, and dependencies. Identifies EOL status and semver jump magnitude.
2. **API delta findings** -- removed, renamed, and changed APIs between current and target versions. Includes replacement signatures and behavioral changes.
3. **Dependency impact map** -- directed graph of which packages depend on which, and the cascading effects of upgrading each one. Highlights peer dependency conflicts.
4. **Test gap risk map** -- modules ranked by risk (change surface vs test coverage). Flags untested code paths affected by the upgrade.

If any input is missing or incomplete, stop and request it before generating a plan.

## Grouping Changes into Tasks

Each task must be independently deployable and verifiable. Group by these rules:

1. **One logical upgrade per task.** Do not combine unrelated dependency bumps. A task upgrades one package (or a tightly coupled set that must move together due to peer dependencies).
2. **Include all cascading changes.** If upgrading package A requires adapting code in files X, Y, Z, all three adaptations belong in the same task as the version bump.
3. **Separate config changes from code changes** when they can be deployed independently (e.g., updating `tsconfig.json` target separately from rewriting deprecated API calls).
4. **Keep test updates with the code they test.** Do not create separate "fix tests" tasks.

## Determining Task Order

Apply a three-tier ordering strategy:

**Tier 1 -- Foundation (execute first)**
- Runtime upgrades (Node.js, Python, etc.)
- Build toolchain updates (TypeScript, Babel, Webpack/Vite)
- Core configuration changes (tsconfig, eslint, package.json engines)

**Tier 2 -- Cascading dependencies**
- Order by the dependency impact map: upgrade leaf dependencies before packages that depend on them
- When two packages are independent, order by risk (lower risk first) to build confidence
- Resolve peer dependency conflicts at this tier

**Tier 3 -- Cleanup**
- Remove compatibility shims introduced during migration
- Delete deprecated polyfills no longer needed for the target runtime
- Remove unused dependencies revealed by the upgrade
- Final linting and code style normalization

Within each tier, prefer the change with the smallest blast radius first.

## Writing Each Task

Follow this exact structure for every task in the plan:

````markdown
### Task N: [Concise action description]

**Risk:** LOW | MEDIUM | HIGH
**Breaking changes addressed:** [List from API delta findings, or "None"]
**Rollback:** [Exact steps to undo this task -- typically `git revert HEAD` plus any package reinstall]

**Files:**
- Modify: `path/to/file.ext`
- Modify: `path/to/another.ext`
- Test: `tests/path/to/test.ext`

- [ ] **Step 1: [Action in imperative mood]**

[Specific details. Reference exact API replacements from the delta findings. Include code snippets only when the replacement is non-obvious.]

- [ ] **Step 2: [Next action]**

[Details]

- [ ] **Step N: Run verification**

Run: `npm test && npm run build`
Expected: All tests pass, build succeeds with no errors

- [ ] **Step N+1: Commit**

```bash
git add path/to/file.ext path/to/another.ext tests/path/to/test.ext
git commit -m "type: descriptive message"
```
````

Rules for task content:

- Every task must end with a verification step (Run/Expected) and a commit step.
- If a step requires choosing between multiple valid approaches, flag it: `**USER DECISION REQUIRED:** [Describe the options and trade-offs]`
- Include rollback instructions that assume the reader has no context beyond the plan.
- Reference specific file paths from the impact map. Do not use vague references like "update affected files."
- Use imperative mood throughout ("Update the import" not "The import should be updated").

## Identifying User Decision Points

Flag a step with `**USER DECISION REQUIRED:**` when:

- Multiple migration strategies exist (e.g., shim vs full rewrite)
- A breaking change affects public API surface
- A dependency has multiple valid replacement candidates
- The upgrade changes default behavior that may be intentional in the project
- Test coverage is insufficient to verify the change automatically (from the test gap risk map)

Do not flag routine, unambiguous changes. The goal is to minimize interruptions while catching decisions that could cause regret.

## Final Verification Task

The last task in every plan must be a full-pipeline verification:

```markdown
### Task N: Full pipeline verification

**Risk:** LOW
**Breaking changes addressed:** None (verification only)
**Rollback:** N/A

**Files:**
- None (read-only verification)

- [ ] **Step 1: Run complete test suite**

Run: `[project test command]`
Expected: All tests pass

- [ ] **Step 2: Run production build**

Run: `[project build command]`
Expected: Build succeeds, no warnings related to upgraded dependencies

- [ ] **Step 3: Run linter**

Run: `[project lint command]`
Expected: No new errors or warnings

- [ ] **Step 4: Check for remaining deprecation warnings**

Run: `[project test command] 2>&1 | grep -i deprecat`
Expected: No deprecation warnings from upgraded packages

- [ ] **Step 5: Verify no leftover compatibility shims**

Search the codebase for any temporary shims or TODO comments added during migration. Remove or resolve each one.
```

## Output Format

Emit the plan in standard Claude Code plan format:

```markdown
# [Upgrade Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing the end state]

**Architecture:** [2-3 sentences on the migration approach -- incremental vs big-bang, shim strategy, key sequencing decisions]

**Tech Stack:** [Runtime, framework, and key dependencies involved]

---

[Tasks in order, using the format above]
```

## Example: Express 4 to 5 Upgrade (Single Task Excerpt)

Given these hypothetical analysis inputs:
- **Version checker:** Express 4.18.2 installed, target 5.0.1
- **API delta:** `res.send(status)` removed (use `res.status(n).send()`), `app.del()` removed (use `app.delete()`), path route syntax changes
- **Impact map:** 3 route files use `app.del()`, 7 files use `res.send(status)` pattern
- **Test gap:** `routes/admin.js` has 0% coverage, uses both deprecated patterns

````markdown
### Task 2: Replace deprecated Express response and routing APIs

**Risk:** MEDIUM
**Breaking changes addressed:** `res.send(status)` removed in Express 5, `app.del()` renamed to `app.delete()`
**Rollback:** `git revert HEAD && npm install express@4.18.2`

**Files:**
- Modify: `src/routes/admin.js`
- Modify: `src/routes/api.js`
- Modify: `src/routes/auth.js`
- Modify: `src/middleware/error-handler.js`
- Test: `tests/routes/admin.test.js`
- Test: `tests/routes/api.test.js`
- Test: `tests/routes/auth.test.js`

- [ ] **Step 1: Replace `app.del()` with `app.delete()` in all route files**

Search for `app.del(` in `src/routes/`. Replace each occurrence with `app.delete(`. There are 3 known occurrences across admin.js, api.js, and auth.js.

- [ ] **Step 2: Replace `res.send(status)` with `res.status(n).send()`**

Search for the pattern `res.send(number)` across all 7 affected files. Replace with `res.status(number).send()`. Pay attention to cases where the argument is a variable -- verify it is a status code, not a body payload.

- [ ] **Step 3: Add missing tests for admin routes**

**USER DECISION REQUIRED:** `routes/admin.js` has 0% test coverage and uses both deprecated patterns. Choose one:
- (A) Write tests for current behavior before migrating, then migrate (safer, slower)
- (B) Migrate first, then write tests against new behavior (faster, riskier)

- [ ] **Step 4: Run verification**

Run: `npm test && npm run build`
Expected: All tests pass, no Express deprecation warnings in output

- [ ] **Step 5: Commit**

```bash
git add src/routes/ src/middleware/error-handler.js tests/routes/
git commit -m "refactor: replace deprecated Express 4 APIs with Express 5 equivalents"
```
````
