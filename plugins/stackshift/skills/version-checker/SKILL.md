---
name: version-checker
description: This skill should be used when the caller needs to determine the latest stable or LTS versions of runtimes (Node.js, Python) or packages (npm, PyPI), check if current project versions are outdated or end-of-life, or identify upgrade paths from local versions to recommended targets.
user-invocable: false
allowed-tools: Read, Glob, Bash, WebFetch
---

Check only the runtimes or packages the caller asks about. Do not scan all dependencies unprompted.

## Detecting Local Versions

Inspect only the files relevant to the requested check:

### Node.js runtime

- `.node-version` / `.nvmrc` — plain text, single version string
- `package.json` — `engines.node` field (semver range)
- `package.json` — `volta.node` field (exact version, set by Volta)
- `.tool-versions` — line starting with `nodejs`

### Python runtime

- `.python-version` — plain text, single version string
- `pyproject.toml` — `project.requires-python` field (PEP 440 specifier)
- `.tool-versions` — line starting with `python`

### npm packages

- `package.json` — `dependencies` and `devDependencies` version ranges

### PyPI packages

- `pyproject.toml` — `project.dependencies` and `project.optional-dependencies`
- `requirements.txt` / `requirements-*.txt` — pinned or ranged versions

If multiple sources conflict, report the discrepancy.

The patterns above cover JavaScript/TypeScript (Node.js, npm) and Python ecosystems. For other runtimes or package registries, apply the same approach: check local version files and query the ecosystem's machine-readable registry endpoint following the same patterns shown here.

## Looking Up Latest Versions

Run `scripts/fetch-version.sh` (located in this skill's directory) via Bash. It fetches registry APIs using curl and jq, returning only the needed fields as `key=value` lines.

### Node.js runtime

1. Run `scripts/fetch-version.sh nodejs-releases` — returns `latest_current`, `latest_current_date`, `latest_lts`, `latest_lts_codename`, `latest_lts_date`.
2. Run `scripts/fetch-version.sh nodejs-eol` — returns `---`-separated records with `cycle`, `eol`, `lts`, `latest`.

### Python runtime

1. Run `scripts/fetch-version.sh python-eol` — returns `---`-separated records with `cycle`, `eol`, `latest`.

### npm packages

1. Run `scripts/fetch-version.sh npm <package>` — returns `latest`.

### PyPI packages

1. Run `scripts/fetch-version.sh pypi <package>` — returns `latest`, `requires_python`.

### Fallback

If any script invocation outputs a line starting with `error:`, fall back to direct fetching:

1. Call ToolSearch with query `select:WebFetch` to load the tool schema.
2. Read `references/known-endpoints.md` for the endpoint URL and response schema.
3. Use WebFetch to fetch the endpoint and extract the needed fields from the JSON response.

## Assessing EOL Status

- For runtimes: cross-reference with endoflife.date API (`https://endoflife.date/api/{product}.json`).
- A version is EOL if its `eol` date is in the past relative to today.
- Flag versions entering EOL within the next 6 months as "approaching EOL."

## Output Format

Present results using this structure:

```
## Summary
1-2 sentence overview of findings.

## Findings
For each checked item:
- **Item name** (e.g., Node.js, react, Flask)
  - Current: <local version or range>
  - Latest LTS: <version> (if applicable)
  - Latest stable: <version>
  - EOL status: <active | approaching EOL (date) | EOL since (date)>
  - Recommended target: <version>

## Recommendations
Actionable next steps, ordered by priority (EOL items first, then outdated items).
```

## Rules

- Fetch live data for every check. Do not rely on training data for version numbers.
- If a fetch fails, report the failure and the URL attempted. Do not guess.
- Distinguish between LTS and Current/stable where the ecosystem makes that distinction (Node.js). For ecosystems without an LTS concept (PyPI packages), report only latest stable.
- When the local version satisfies the latest LTS or stable, say so explicitly — do not suggest unnecessary upgrades.
