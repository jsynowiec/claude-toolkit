---
name: release-notes-retriever
description: Fetches upstream release notes, changelogs, deprecation notices, and migration guides for a library or runtime version range. Use before analyzing API changes or planning upgrades.
user-invocable: false
allowed-tools: Read, Bash, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs
---

Accept as input: package name, source repository URL (if known), current version, and target version. Distill findings into only migration-relevant content — skip bug fixes and internal refactors unless they affect the upgrade path.

## Retrieval Strategy

Run `scripts/fetch-release-notes.sh` (located in this skill's directory) via Bash to fetch repository URLs and release notes. The script uses curl and jq to return only the needed fields, keeping token use low. If the script is unavailable or returns an `error:` line, fall back to direct fetching as described in the **Fallback** section below.

### 1. Resolve the source repository

If the caller provides a repository URL, skip to step 2.

For npm packages, run:
```
scripts/fetch-release-notes.sh npm-repo <package>
```
Returns `repository_url=<url>`.

For PyPI packages, run:
```
scripts/fetch-release-notes.sh pypi-repo <package>
```
Returns `repository_url=<url>`.

Parse the URL to extract `<owner>` and `<repo>` from the GitHub path (`github.com/<owner>/<repo>`).

### 2. GitHub Releases (preferred)

Fetch release notes for the version range using:
```
scripts/fetch-release-notes.sh github-releases <owner> <repo> <from_version> <to_version>
```

The script returns only releases where `from_version < release <= to_version`. Output is clean markdown:

```
## v5.0.0

Release body text...

---
## v4.9.0

Release body text...
```

If the output contains a `warning:` line about 100 releases, the version range may span more releases than were fetched. In that case fall back to WebFetch with pagination (see **Fallback** below).

### 3. context7 MCP tool (fallback)

If GitHub releases are unavailable or empty:

1. Call `mcp__context7__resolve-library-id` with the package name to get the library identifier.
2. Call `mcp__context7__query-docs` with that identifier and a query like `"changelog migration breaking changes between {current_version} and {target_version}"`.
3. Extract version-relevant sections from the returned documentation.

### 4. Raw CHANGELOG parsing (last resort)

Fetch the raw CHANGELOG.md (or HISTORY.md, CHANGES.md, NEWS.md) from the repository's default branch:

```
https://raw.githubusercontent.com/{owner}/{repo}/HEAD/CHANGELOG.md
```

Before making web requests, call ToolSearch with query `select:WebFetch` to load the tool schema.

Parse headings to identify version boundaries. Extract only the sections between current and target versions.

### Fallback

If any `scripts/fetch-release-notes.sh` invocation outputs a line starting with `error:`:

1. Call ToolSearch with query `select:WebFetch` to load the tool schema.
2. For repository URL resolution: use WebFetch against `https://registry.npmjs.org/{package}` (read `repository.url`) or `https://pypi.org/pypi/{package}/json` (read `info.project_urls` or `info.home_page`).
3. For release notes: use WebFetch against `https://api.github.com/repos/{owner}/{repo}/releases?per_page=100`. If `GITHUB_TOKEN` is available, include it as a `Bearer` token in the `Authorization` header. Paginate if needed.

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
