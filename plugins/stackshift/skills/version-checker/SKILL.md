---
name: version-checker
description: Use when you need to determine the latest stable or LTS versions of runtimes (Node.js, Python) or packages (npm, PyPI), check if current project versions are outdated or end-of-life, or identify upgrade paths from local versions to recommended targets.
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

Use WebFetch against the endpoints documented in `known-endpoints.md` (located alongside this file). Parse the JSON responses to extract version data.

### Node.js runtime

1. Fetch the Node.js release index.
2. Identify the latest LTS release: first entry where `lts` is a non-false string.
3. Identify the latest Current release: the very first entry in the array.
4. Determine EOL status by checking the endoflife.date API for Node.js or by comparing against the known LTS schedule.

### Python runtime

1. Fetch the endoflife.date Python endpoint for a concise view of all releases with EOL dates.
2. Latest stable: the highest version where `eol` date is in the future.
3. EOL status: compare the project's Python version against the `eol` field.

### npm packages

1. Fetch the registry endpoint for the specific package.
2. `dist-tags.latest` gives the latest published version.
3. Check `time` object for release dates if age matters.

### PyPI packages

1. Fetch the PyPI JSON endpoint for the specific package.
2. `info.version` gives the latest stable version.
3. Filter out pre-releases by ignoring versions containing `a`, `b`, `rc`, or `dev` suffixes in `releases` keys.

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
