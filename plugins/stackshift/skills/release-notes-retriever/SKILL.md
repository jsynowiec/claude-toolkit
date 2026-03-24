---
name: release-notes-retriever
description: "Use when you need to fetch upstream release notes, changelogs, deprecation notices, or migration guides for a specific library or runtime version range. Use this before analyzing API changes or planning upgrades."
---

Fetch and distill upstream release notes, deprecation notices, and migration guides for a specific version range. Accept as input: package name, source repository (if known), current version, and target version.

## Retrieval Strategy

Try sources in this order. Stop as soon as you get structured, version-tagged content covering the requested range.

### 1. GitHub Releases API (preferred)

Use WebFetch to call the GitHub releases endpoint. If a `GITHUB_TOKEN` environment variable is available, include it as a `Bearer` token in the `Authorization` header to avoid the 60 requests/hour unauthenticated rate limit.

```
https://api.github.com/repos/{owner}/{repo}/releases?per_page=100
```

- Paginate if the version range spans more than 100 releases.
- Filter the response to only releases whose `tag_name` falls within the requested range (inclusive of target, exclusive of current). Normalize tag formats — strip leading `v`, handle `@scope/pkg@version` monorepo tags.
- Extract the `body` field from each matching release.

If the repository is unknown, infer it from the package registry:
- npm: fetch `https://registry.npmjs.org/{package}` and read `repository.url`
- PyPI: fetch `https://pypi.org/pypi/{package}/json` and read `info.project_urls` or `info.home_page`

### 2. context7 MCP tool (fallback)

If GitHub releases are unavailable or empty:

1. Call `mcp__context7__resolve-library-id` with the package name to get the library identifier.
2. Call `mcp__context7__query-docs` with that identifier and a query like `"changelog migration breaking changes between {current_version} and {target_version}"`.
3. Extract version-relevant sections from the returned documentation.

### 3. Raw CHANGELOG parsing (last resort)

Fetch the raw CHANGELOG.md (or HISTORY.md, CHANGES.md, NEWS.md) from the repository's default branch:

```
https://raw.githubusercontent.com/{owner}/{repo}/HEAD/CHANGELOG.md
```

Parse headings to identify version boundaries. Extract only the sections between current and target versions.

## Filtering and Distillation

From the raw release notes, extract and categorize:

- **Deprecations**: APIs, options, or behaviors marked deprecated. Note the recommended replacement.
- **Removals**: Previously deprecated items that have been removed.
- **Breaking behavior changes**: Default values changed, argument semantics altered, error handling modified.
- **New APIs**: Additions that serve as replacements for deprecated or removed features.
- **Migration steps**: Explicit instructions from the maintainers on how to upgrade.
- **Minimum runtime requirements**: Changes to required Node.js, Python, or other runtime versions.

Discard bug fixes, performance improvements, and internal refactors that do not affect the public API or migration path, unless they are specifically relevant to the upgrade.

## Output Format

Structure all output as follows:

```
## Summary
1-2 sentence overview: what library/runtime, what version range, and the overall migration complexity (trivial / moderate / significant / major).

## Findings
### Deprecations
- `oldApi()` deprecated in v4.3, removed in v5.0. Use `newApi()` instead.

### Removals
- `legacyOption` removed in v5.0. No direct replacement; refactor to use the configuration object pattern.

### Breaking Changes
- Default timeout changed from 30s to 10s in v4.5.
- `connect()` now returns a Promise instead of accepting a callback (v5.0).

### New APIs
- `createClient()` added in v4.4 as the replacement for the deprecated `Client` constructor.

### Migration Steps
- Update all `Client` constructor calls to `createClient()` before upgrading past v5.0.
- Set explicit timeout values if the application relies on the previous 30s default.

### Runtime Requirements
- Minimum Node.js version raised from 14 to 18 in v5.0.

## Recommendations
- Ordered list of concrete upgrade actions.
- Flag any steps that require user decisions or carry elevated risk.
```

Omit any subsection under Findings that has no entries. Do not fabricate entries — if release notes are sparse or missing for a version, state that explicitly and recommend manual verification.

## Error Handling

- If no source yields usable release notes, report that clearly in the Summary and recommend the user check the project's documentation manually. Provide direct links to the repository and any documentation sites found during lookup.
- If the version range is ambiguous (e.g., no clear semver tags, or the package uses calver), state the assumption made and ask for confirmation before proceeding.
