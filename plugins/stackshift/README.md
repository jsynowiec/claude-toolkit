# stackshift

A Claude Code plugin for modernizing legacy codebases — upgrade runtimes, migrate frameworks, manage dependencies, and reduce technical debt.

## Language & Runtime Support

stackshift was designed and tested primarily with **Node.js** (JavaScript/TypeScript/npm/yarn/pnpm) and **Python** (pip/PyPI/uv) projects in mind. It should work with other languages and runtimes — Go, Rust, Java, Ruby, and others — but the agents and skills are optimized for the ecosystems above, so results may be less precise or require more manual guidance outside of them.

## Requirements

- [jq](https://jqlang.github.io/jq/) — used by the version-checker and release-notes-retriever skills for efficient JSON parsing. The skills fall back to direct fetching if jq is unavailable, but performance is significantly better with it installed. Install with `brew install jq` (macOS) or `apt-get install jq` (Linux).

## Agents

- **modernization-engineer** — Orchestrates modernization workflows. Assesses the current state, plans upgrades, executes them incrementally, and verifies results. Delegates procedural work to specialized skills.
- **dependency-impact-map** — Scans lockfiles, manifests, and import graphs to model the blast radius of dependency upgrades. Reports per-package impact scores, peer conflicts, and transitive dependency chains.

## Skills

| Skill | Purpose |
|-------|---------|
| **release-notes-retriever** | Fetches and distills upstream changelogs, deprecation notices, and migration guides for a specific version range |
| **version-checker** | Identifies latest stable/LTS versions of runtimes and packages, detects EOL status, and recommends upgrade targets |
| **api-delta-finder** | Compares API surfaces between versions to find removed, renamed, and behavior-changing APIs with severity classification |
| **toolchain-discovery** | Auto-detects build, test, lint, type-check, and formatting tooling in a repository (monorepo-aware) |
| **build-verifier** | Runs the build pipeline in standardized order, classifies failures, and diffs against a baseline to isolate regressions |
| **test-gap-analyzer** | Maps upgraded components to test coverage and produces a per-file risk map |
| **upgrade-plan-generator** | Synthesizes analysis findings into an ordered migration plan in standard Claude Code plan format |

## Data Flow

```
version-checker ─────────────────────────────────────────────────────────┐
                                                                        │
release-notes-retriever ──> api-delta-finder ──┐                        │
                                               │                        v
dependency-impact-map ─────────────────────────┼──> test-gap-analyzer ──> upgrade-plan-generator
                                               │
toolchain-discovery ──> build-verifier ────────┘
```

The modernization-engineer agent orchestrates this flow, using judgment to decide which skills are needed and in what order.

## License

[MIT](../../LICENSE)
