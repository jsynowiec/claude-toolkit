---
name: toolchain-discovery
description: Use when you need to identify what build, test, lint, type-check, and formatting tooling exists in a repository before running verification steps or assessing a project's development setup.
---

Detect all build, test, lint, type-check, and formatting tooling in a repository. Produce a structured toolchain manifest covering every workspace.

## Procedure

### 1. Detect Project Structure

Check for monorepo indicators at the repository root:

- `package.json` — look for `workspaces` field (npm/yarn workspaces)
- `pnpm-workspace.yaml` — pnpm workspaces
- `lerna.json` — Lerna monorepo
- `nx.json` — Nx monorepo
- `turbo.json` — Turborepo monorepo

Check for Python project structure:

- `pyproject.toml` — look for `[tool.*]` sections
- `tox.ini` — tox test environments
- `setup.cfg` — setuptools configuration

If workspace patterns are found, resolve them to concrete directories. Each workspace directory is analyzed independently. If no workspace patterns exist, treat the root as a single workspace.

### 2. Detect Package Manager

For each workspace, identify the package manager:

**JavaScript/TypeScript:**
- `pnpm-lock.yaml` — pnpm
- `yarn.lock` — yarn
- `bun.lockb` or `bun.lock` — bun
- `package-lock.json` — npm

**Python:**
- `uv.lock` — uv
- `poetry.lock` — poetry
- `requirements.txt` or `setup.py` — pip

### 3. Scan for Tool Configuration

For each workspace, scan for configuration files in these categories:

**Lint:**
- `.eslintrc.*`, `eslint.config.*` (ESLint)
- `ruff.toml`, `pyproject.toml` with `[tool.ruff.lint]` (Ruff)
- `.flake8` (Flake8)
- `.pylintrc`, `pylintrc`, `pyproject.toml` with `[tool.pylint]` (Pylint)
- `biome.json`, `biome.jsonc` (Biome)

**Type-check:**
- `tsconfig.json` (TypeScript)
- `mypy.ini`, `pyproject.toml` with `[tool.mypy]` (mypy)
- `pyrightconfig.json`, `pyproject.toml` with `[tool.pyright]` (Pyright)

**Test:**
- `jest.config.*` (Jest)
- `vitest.config.*` (Vitest)
- `pytest.ini`, `pyproject.toml` with `[tool.pytest]` (pytest)
- `playwright.config.*` (Playwright — e2e)
- `cypress.config.*` (Cypress — e2e)

**Build:**
- `webpack.config.*` (Webpack)
- `vite.config.*` (Vite)
- `rollup.config.*` (Rollup)
- `next.config.*` (Next.js)
- `tsup.config.*` (tsup)
- `pyproject.toml` with `[build-system]` (Python build)

**Format:**
- `.prettierrc.*`, `prettier.config.*` (Prettier)
- `biome.json`, `biome.jsonc` (Biome)
- `pyproject.toml` with `[tool.black]` (Black)
- `pyproject.toml` with `[tool.ruff.format]` (Ruff formatter)

The lists above cover common JavaScript/TypeScript and Python tooling. For other ecosystems, scan for equivalent configuration files following the same category structure (lint, typecheck, test, build, format).

### 4. Extract Runnable Commands

Identify how each detected tool is invoked:

- **package.json scripts** — read `scripts` object, match keys like `lint`, `test`, `test:unit`, `test:e2e`, `test:integration`, `build`, `typecheck`, `type-check`, `format`, `check`
- **Makefile targets** — parse target names for `lint`, `test`, `build`, `format`, `typecheck` patterns
- **tox environments** — parse `[tox] envlist` for test/lint environments
- **pyproject.toml scripts** — check `[project.scripts]` and `[tool.poetry.scripts]`

Prefer explicit script aliases (e.g., `npm run lint`) over direct binary invocation (e.g., `npx eslint .`). Fall back to direct invocation only when no script alias exists.

### 5. Produce Output

Format findings using the shared output convention.

## Output Format

```
## Summary
Brief description of the repository structure and tooling detected.

## Findings

### Workspace: <workspace-name> (<path>)

**Package manager:** <name>

| Category    | Tool       | Config file              | Run command              |
|-------------|------------|--------------------------|--------------------------|
| lint        | ESLint     | eslint.config.js         | npm run lint             |
| typecheck   | TypeScript | tsconfig.json            | npm run typecheck        |
| test:unit   | Vitest     | vitest.config.ts         | npm run test             |
| test:e2e    | Playwright | playwright.config.ts     | npm run test:e2e         |
| build       | tsup       | tsup.config.ts           | npm run build            |
| format      | Prettier   | .prettierrc.json         | npm run format           |

### Workspace: <next-workspace> (<path>)
...

## Recommendations
Actionable next steps — flag missing categories, suggest additions, note inconsistencies across workspaces.
```

## Example

For a TypeScript monorepo with two packages:

```
## Summary
Monorepo with pnpm workspaces containing 2 packages. Both use TypeScript with Vitest for testing. Linting is configured at root only.

## Findings

### Workspace: root (.)

**Package manager:** pnpm

| Category    | Tool       | Config file              | Run command              |
|-------------|------------|--------------------------|--------------------------|
| lint        | ESLint     | eslint.config.js         | pnpm run lint            |
| format      | Prettier   | .prettierrc.json         | pnpm run format          |

### Workspace: packages/core (packages/core)

**Package manager:** pnpm

| Category    | Tool       | Config file              | Run command              |
|-------------|------------|--------------------------|--------------------------|
| typecheck   | TypeScript | tsconfig.json            | pnpm run typecheck       |
| test:unit   | Vitest     | vitest.config.ts         | pnpm run test            |
| build       | tsup       | tsup.config.ts           | pnpm run build           |

### Workspace: packages/cli (packages/cli)

**Package manager:** pnpm

| Category    | Tool       | Config file              | Run command              |
|-------------|------------|--------------------------|--------------------------|
| typecheck   | TypeScript | tsconfig.json            | pnpm run typecheck       |
| test:unit   | Vitest     | vitest.config.ts         | pnpm run test            |
| build       | tsup       | tsup.config.ts           | pnpm run build           |

## Recommendations
- packages/core and packages/cli have no local lint config. Verify root ESLint config covers them.
- No e2e or integration tests detected in any workspace.
- No formatting config in individual packages. Confirm root Prettier config applies workspace-wide.
```
