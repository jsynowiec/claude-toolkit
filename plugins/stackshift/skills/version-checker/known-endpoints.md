# Known Endpoints

Machine-readable registry URLs for version lookups. Used by the version-checker skill.

## Node.js Releases

**URL:** `https://nodejs.org/dist/index.json`

Returns a JSON array of all releases, newest first.

```json
[
  {
    "version": "v22.5.1",
    "date": "2024-07-19",
    "lts": false,
    "security": false
  },
  {
    "version": "v22.4.0",
    "date": "2024-07-08",
    "lts": false,
    "security": false
  },
  {
    "version": "v20.16.0",
    "date": "2024-07-24",
    "lts": "Iron",
    "security": false
  }
]
```

**Key fields:**

- `version` — semver prefixed with `v`
- `lts` — `false` for Current releases, a codename string (e.g., `"Iron"`) for LTS releases
- `date` — release date

**Extract:** First entry = latest Current. First entry where `lts` is not `false` = latest LTS.

## Node.js EOL Schedule

**URL:** `https://endoflife.date/api/nodejs.json`

```json
[
  {
    "cycle": "22",
    "releaseDate": "2024-04-24",
    "eol": "2027-04-30",
    "lts": "2024-10-29",
    "latest": "22.5.1"
  }
]
```

**Key fields:**

- `cycle` — major version number
- `eol` — end-of-life date (ISO 8601)
- `lts` — date LTS began, or `false` if not an LTS line

## Python Versions

**URL:** `https://endoflife.date/api/python.json`

Preferred for version checks. Concise and consistent format.

```json
[
  {
    "cycle": "3.12",
    "releaseDate": "2023-10-02",
    "eol": "2028-10-02",
    "latest": "3.12.5",
    "lts": false
  },
  {
    "cycle": "3.8",
    "releaseDate": "2019-10-14",
    "eol": "2024-10-07",
    "latest": "3.8.20",
    "lts": false
  }
]
```

**Key fields:**

- `cycle` — minor version series (e.g., `3.12`)
- `eol` — end-of-life date
- `latest` — latest patch release in this series

**Extract:** Highest `cycle` where `eol` is in the future = latest stable series. Compare project version's `cycle` against `eol` for EOL status.

**Alternate URL:** `https://www.python.org/api/v2/downloads/release/`

Returns all CPython releases. Heavier response; prefer endoflife.date for version/EOL checks.

## npm Registry

**URL:** `https://registry.npmjs.org/{package}`

Replace `{package}` with the package name (e.g., `express`, `@types/node`). For scoped packages, the `@` and `/` are used as-is in the URL.

```json
{
  "name": "express",
  "dist-tags": {
    "latest": "4.19.2",
    "next": "5.0.0-beta.3"
  },
  "time": {
    "4.19.2": "2024-03-25T00:00:00.000Z",
    "5.0.0-beta.3": "2024-02-01T00:00:00.000Z"
  },
  "versions": { }
}
```

**Key fields:**

- `dist-tags.latest` — current stable release
- `dist-tags` — may include `next`, `canary`, or other tagged pre-releases
- `time` — map of version to publish timestamp

**Extract:** `dist-tags.latest` for the recommended stable version. Ignore `next`/`canary` tags unless explicitly asked.

**Tip:** Add `Accept: application/vnd.npm.install-v1+json` header to get an abbreviated response if full metadata is not needed.

## PyPI Registry

**URL:** `https://pypi.org/pypi/{package}/json`

Replace `{package}` with the package name (e.g., `flask`, `django`).

```json
{
  "info": {
    "name": "Flask",
    "version": "3.0.3",
    "requires_python": ">=3.8"
  },
  "releases": {
    "3.0.3": [ { "packagetype": "sdist" } ],
    "3.1.0a1": [ { "packagetype": "sdist" } ],
    "2.3.3": [ { "packagetype": "sdist" } ]
  }
}
```

**Key fields:**

- `info.version` — latest stable version
- `info.requires_python` — minimum Python version
- `releases` — all published versions (keys are version strings)

**Extract:** `info.version` for latest stable. To filter pre-releases from `releases`, skip keys containing `a`, `b`, `rc`, or `.dev`.
