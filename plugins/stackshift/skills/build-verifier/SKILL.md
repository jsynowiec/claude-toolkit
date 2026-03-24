---
name: build-verifier
description: Use when you need to run a repository's build pipeline (lint, typecheck, tests, build) in a standardized order, classify any failures, or establish a baseline before making changes to detect regressions introduced by upgrades.
---

Run a repository's build pipeline in a standardized order, classify failures, and detect regressions by diffing against a baseline.

**REQUIRED SUB-SKILL:** Use stackshift:toolchain-discovery to identify available tooling before running verification.

## Pipeline Stages

Execute stages in this order. Skip any stage where toolchain-discovery found no available command.

| Order | Stage | Typical command |
|-------|-------|-----------------|
| 1 | install | `npm install`, `yarn install`, `pnpm install` |
| 2 | lint | `npm run lint`, `eslint .`, `biome check .` |
| 3 | typecheck | `npx tsc --noEmit`, `npm run typecheck` |
| 4 | unit tests | `npm test`, `jest`, `vitest run` |
| 5 | integration tests | `npm run test:integration`, `npm run test:e2e` |
| 6 | build | `npm run build`, `vite build`, `tsc` |

Use the exact commands reported by toolchain-discovery. The table above shows JavaScript/TypeScript examples. For other ecosystems (Python, Go, etc.), follow the same stage ordering with equivalent commands as reported by toolchain-discovery.

## Running the Pipeline

### Full Run (default)

Run all 6 stages in order. Capture stdout and stderr from every stage. Record the exit code.

If a stage fails, continue to the next stage. Do not abort early. The goal is a complete picture of the repo's health.

### Partial Run

When the calling agent requests specific stages (e.g., "only lint and typecheck"), run only those stages in their standard order. Report only those results.

## Cascade Attribution

When a foundational stage fails, subsequent stage failures are often caused by the same root problem rather than independent issues. Apply this rule:

- If **install** fails, all subsequent stage failures are cascading. Mark them `Result: FAIL (cascading from install)` rather than classifying their errors independently.
- If any other stage produces a failure that blocks the next stage (e.g., a syntax error in the output that prevents parsing), apply the same cascade attribution.

Only count a cascading failure as a distinct regression if its error output clearly points to a different root cause unrelated to the upstream failure.

In baseline+diff mode, cascading failures from a cascading root cause are still compared against baseline: if the root stage was already failing in the baseline, the cascading failures are pre-existing too.

## Baseline and Diff Mode

### Capture Baseline

Run the full pipeline BEFORE making any changes. Store results as the baseline:

- For each stage: pass or fail
- For each failure: the classified error (see Failure Classification below)
- Keep the raw output available for re-parsing if needed

### Diff Against Baseline

After each upgrade step, run the pipeline again and compare:

1. Any failure that matches a baseline failure (same stage, same classification, same file) is **pre-existing**. Do not report it as a regression.
2. Any failure that appears only in the post-change run is **new**. Report it as a regression.
3. Any baseline failure that disappears in the post-change run is **fixed**. Note it as a positive outcome.

## Failure Classification

Classify every failure into exactly one category by matching error output against these patterns.

| Category | Key patterns |
|----------|-------------|
| `syntax` | "SyntaxError", "Parsing error", "Unexpected token", "Unterminated string" |
| `type` | "TS\d{4}:", "Type .* is not assignable", "Property .* does not exist", "type error", mypy error codes |
| `test-assertion` | "expect(", "AssertionError", "Expected .* to", "toBe", "toEqual", "received" vs "expected" |
| `test-runtime` | "ReferenceError", "TypeError" in test output, "Cannot find module" in test, "TIMEOUT", unhandled rejection in test |
| `build` | "Build failed", "bundle error", "Entry module not found", "Could not resolve", rollup/webpack/vite errors |
| `dependency` | "ERESOLVE", "peer dep", "Could not resolve dependency", "Module not found" outside test context, "No matching version" |

When a failure could match multiple categories, prefer the more specific one. `dependency` over `build` when the build fails due to a missing package. `test-assertion` over `test-runtime` when a test has an assertion diff.

## Output Format

Structure all output as follows.

### Summary

1-2 sentence overview of findings.

### Findings

Per-stage results with classified failures:

```
Stage: <stage-name>
Result: PASS | FAIL
Failures:
  - classification: <category>
    file: <file-path>:<line>
    message: <first meaningful line of error>
    status: new | pre-existing | fixed
```

Omit the `Failures` block for stages that pass. Omit the `status` field when running without a baseline.

### Recommendations

Actionable next steps based on the failures. Group by classification category. Prioritize `dependency` and `syntax` errors first (they often cascade into other failures).

## Example Output

```
## Summary
Build pipeline completed: 4 of 6 stages passed. 2 new failures detected after upgrading react from v17 to v18.

## Findings
Stage: install
Result: PASS

Stage: lint
Result: PASS

Stage: typecheck
Result: FAIL
Failures:
  - classification: type
    file: src/components/App.tsx:42
    message: "TS2769: No overload matches this call. Type 'ReactNode' is not assignable to type 'ReactElement'."
    status: new

Stage: unit tests
Result: FAIL
Failures:
  - classification: test-assertion
    file: src/components/App.test.tsx:18
    message: "Expected container to have textContent 'Welcome' but received ''"
    status: new
  - classification: test-runtime
    file: src/utils/legacy.test.ts:7
    message: "ReferenceError: shallow is not defined"
    status: pre-existing

Stage: integration tests
Result: PASS

Stage: build
Result: PASS

## Recommendations
1. [type] Fix the ReactNode/ReactElement mismatch in App.tsx:42. React 18 narrowed the return type of FC. Wrap the return in a Fragment or update the type annotation.
2. [test-assertion] The empty textContent in App.test.tsx:18 suggests a rendering change in React 18's createRoot. Update the test to use createRoot instead of ReactDOM.render.
3. [test-runtime] The shallow import error in legacy.test.ts:7 is pre-existing and unrelated to this upgrade. Address separately.
```
