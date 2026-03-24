---
name: test-gap-analyzer
description: Use when planning an upgrade or migration to identify which affected components lack test coverage, helping prioritize where to focus attention and flag risky untested paths before making changes.
---

Map upgraded components to existing test coverage and identify risky untested paths. Combine change severity (from breaking change analysis) with coverage data to produce a per-file risk map that guides where to invest testing effort before executing a migration.

**REQUIRED INPUT:** Output from stackshift:api-delta-finder and/or the dependency-impact-map agent.

## Step 1: Collect Affected Files

Extract the list of affected source files from the input:
- From api-delta-finder output: every file containing a removed, renamed, or behavior-changed API
- From dependency-impact-map output: every source file that imports or re-exports an affected dependency

Deduplicate the list. Each entry should include the file path and the highest severity change affecting it (`removed` > `behavior` > `renamed` > `deprecated`).

## Step 2: Find Existing Tests (Heuristic Analysis)

For each affected source file, search for corresponding test files using common naming conventions:

**JavaScript/TypeScript:**
- `foo.test.ts`, `foo.test.tsx`, `foo.spec.ts`, `foo.spec.tsx`
- `__tests__/foo.ts`, `__tests__/foo.test.ts`

**Python:**
- `test_foo.py`, `tests/test_foo.py`
- `foo_test.py`, `tests/foo_test.py`

**Go:**
- `foo_test.go` (same directory)

**General strategy:**
- Check the same directory for `<name>.test.*` and `<name>.spec.*` variants
- Check sibling `__tests__/`, `tests/`, `test/` directories
- Check project root `tests/` directory with mirrored path structure

If no direct test file exists, trace imports: search all test files for import statements that reference the affected source file. A test file that imports the affected module counts as indirect coverage.

## Step 3: Parse Coverage Reports (When Available)

Check for coverage report files in the project:

**istanbul/c8 (JavaScript/TypeScript):**
- `coverage/coverage-final.json`
- Look up each affected file path in the JSON keys
- Extract `statements.pct`, `branches.pct`, `functions.pct`, `lines.pct`
- Consider a file "covered" if line coverage exceeds 60%

**coverage.py (Python):**
- `coverage.json`, `htmlcov/status.json`
- Look up each affected file in the `files` map
- Compute line coverage from `summary.percent_covered` or from executed/missing line counts

If no coverage reports exist, rely entirely on the heuristic analysis from Step 2. Note the absence in the summary.

## Step 4: Compute Risk Score

For each affected file, combine change severity with coverage to assign a risk level:

| Change Severity | No Test Coverage | Partial Coverage | Comprehensive Coverage |
|---|---|---|---|
| `removed` / breaking API | **high** | **medium** | **low** |
| `behavior` change | **high** | **medium** | **low** |
| `renamed` API | **medium** | **low** | **low** |
| `deprecated` | **medium** | **low** | **low** |

Definitions:
- **No test coverage**: no test file found AND no coverage data (or 0% line coverage)
- **Partial coverage**: test file exists but does not import the affected API directly, OR line coverage is between 1-60%
- **Comprehensive coverage**: test file directly exercises the affected API, OR line coverage exceeds 60%

If the project defines a coverage minimum in its configuration (e.g., istanbul `check-coverage` threshold, pytest `--cov-fail-under`), use that project-specific value instead of 60% to determine the partial/comprehensive boundary.

## Step 5: Produce the Risk Map

Sort results by risk level (high first, then medium, then low). Present using the shared output format.

## Output Format

```
## Summary
Analyzed N affected files. X high-risk, Y medium-risk, Z low-risk.
Coverage reports: [available (istanbul/c8/coverage.py) | not found — results based on heuristic analysis only].

## Findings

### High Risk
| File | Change | Test Coverage | Reason |
|------|--------|---------------|--------|
| src/api/auth.ts | removed: `validateToken()` | none | No test file found, no coverage data |
| src/db/queries.ts | behavior: `findAll()` return type changed | partial (38% lines) | Tests exist but do not cover `findAll()` |

### Medium Risk
| File | Change | Test Coverage | Reason |
|------|--------|---------------|--------|
| src/utils/format.ts | renamed: `formatDate` -> `formatISO` | partial | Test file exists, imports `formatDate` directly |

### Low Risk
| File | Change | Test Coverage | Reason |
|------|--------|---------------|--------|
| src/core/config.ts | deprecated: `loadSync()` | comprehensive (92% lines) | Directly tested in config.test.ts |

## Recommendations
- Write tests for all high-risk files before proceeding with the migration.
- For medium-risk files, verify that existing tests cover the specific changed APIs. Add targeted test cases where they do not.
- Low-risk files can proceed but should still be verified after the migration completes.
- [If no coverage reports found]: Configure a coverage reporter (c8, istanbul, or coverage.py) to get precise data for future analysis.
```

Adjust table contents to match the actual project. Omit empty risk sections.
