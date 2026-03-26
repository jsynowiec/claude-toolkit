#!/usr/bin/env bash
# ABOUTME: Fetches repository URLs and release notes from registry/GitHub APIs.
# ABOUTME: Used by the release-notes-retriever skill to avoid loading large JSON into context.

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "error: jq is required but not found in PATH. Install with: brew install jq (macOS) or apt-get install jq (Linux)"
  exit 1
fi

if ! sort -V /dev/null 2>/dev/null; then
  echo "error: sort -V is required but not available. Install GNU coreutils: brew install coreutils (macOS)"
  exit 1
fi

# Fetch JSON from a URL. Extra args (e.g. -H headers) are passed to curl.
fetch_json() {
  local url="$1"
  shift
  curl -fsSL --max-time 15 "$@" "$url" 2>/dev/null || {
    echo "error: failed to fetch $url"
    exit 1
  }
}

CMD="${1:-}"

case "$CMD" in
  npm-repo)
    PKG="${2:-}"
    if [ -z "$PKG" ]; then
      echo "error: npm-repo subcommand requires a package name (e.g., fetch-release-notes.sh npm-repo express)"
      exit 1
    fi
    # URL-encode scoped packages: @scope/pkg -> @scope%2fpkg
    ENCODED_PKG=$(printf '%s' "$PKG" | sed 's|^\(@[^/]*\)/|\1%2f|')
    TMPFILE=$(mktemp)
    trap 'rm -f "$TMPFILE"' EXIT
    fetch_json "https://registry.npmjs.org/$ENCODED_PKG/latest" \
      | jq -r 2>/dev/null '.repository.url // empty' \
      > "$TMPFILE" \
      || { echo "error: failed to parse response from https://registry.npmjs.org/$ENCODED_PKG/latest"; exit 1; }
    REPO_URL=$(cat "$TMPFILE")
    if [ -z "$REPO_URL" ]; then
      echo "error: no repository URL found for npm package $PKG"
      exit 1
    fi
    REPO_URL=$(printf '%s' "$REPO_URL" \
      | sed \
          -e 's#^git\+##' \
          -e 's#^git://github\.com/#https://github.com/#' \
          -e 's#^ssh://git@github\.com/#https://github.com/#' \
          -e 's#^git@github\.com:#https://github.com/#' \
          -e 's#\.git$##')
    printf 'repository_url=%s\n' "$REPO_URL"
    ;;

  pypi-repo)
    PKG="${2:-}"
    if [ -z "$PKG" ]; then
      echo "error: pypi-repo subcommand requires a package name (e.g., fetch-release-notes.sh pypi-repo flask)"
      exit 1
    fi
    TMPFILE=$(mktemp)
    trap 'rm -f "$TMPFILE"' EXIT
    fetch_json "https://pypi.org/pypi/$PKG/json" \
      | jq -r 2>/dev/null '
          [
            (.info.project_urls["Source"] // empty),
            (.info.project_urls["Repository"] // empty),
            (.info.project_urls["GitHub"] // empty),
            (.info.project_urls["Source Code"] // empty),
            (.info.project_urls["Code"] // empty),
            (.info.project_urls["Homepage"] // empty),
            (.info.home_page // empty)
          ]
          | map(select(type == "string" and test("github\\.com|gitlab\\.com|bitbucket\\.org")))
          | first // empty
        ' \
      > "$TMPFILE" \
      || { echo "error: failed to parse response from https://pypi.org/pypi/$PKG/json"; exit 1; }
    REPO_URL=$(cat "$TMPFILE")
    if [ -z "$REPO_URL" ]; then
      echo "error: no repository URL found for PyPI package $PKG"
      exit 1
    fi
    printf 'repository_url=%s\n' "$REPO_URL"
    ;;

  github-releases)
    OWNER="${2:-}"
    REPO="${3:-}"
    FROM_VER="${4:-}"
    TO_VER="${5:-}"
    if [ -z "$OWNER" ] || [ -z "$REPO" ] || [ -z "$FROM_VER" ] || [ -z "$TO_VER" ]; then
      echo "error: github-releases subcommand requires: <owner> <repo> <from_version> <to_version>"
      exit 1
    fi

    # Build auth args array - safe expansion under set -u
    AUTH_ARGS=()
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      AUTH_ARGS=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi

    TMPFILE=$(mktemp)
    trap 'rm -f "$TMPFILE"' EXIT

    # Fetch releases once; reuse raw JSON for both filtering and body lookup
    RAW_JSON=$(fetch_json "https://api.github.com/repos/$OWNER/$REPO/releases?per_page=100" \
      -H "Accept: application/vnd.github+json" \
      ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}) \
      || { echo "error: failed to fetch releases from https://api.github.com/repos/$OWNER/$REPO/releases"; exit 1; }

    # Extract ver<TAB>tag per line for range filtering (no body, no jq in loop)
    printf '%s' "$RAW_JSON" | jq -r 2>/dev/null '
        def normalize_version:
          # Handle monorepo tags like @scope/pkg@1.2.3 - take version after last @
          if test("@[^@]*$") then split("@") | last
          else . end
          | ltrimstr("v");
        .[] | "\(.tag_name | normalize_version)\t\(.tag_name)"
      ' > "$TMPFILE" || { echo "error: failed to parse releases JSON from $OWNER/$REPO"; exit 1; }

    TOTAL=$(wc -l < "$TMPFILE")

    FROM_NORM="${FROM_VER#v}"
    TO_NORM="${TO_VER#v}"

    FIRST_OUTPUT=true
    while IFS= read -r line; do
      VER="${line%%$'\t'*}"
      TAG="${line#*$'\t'}"

      # Skip empty versions
      [ -z "$VER" ] && continue

      # Skip the from-version itself (we want strictly after from)
      [ "$VER" = "$FROM_NORM" ] && continue

      # Check: from <= ver <= to using sort -V
      # Sort the triple; if from is first and to is last, ver is in range
      SORTED=$(printf '%s\n%s\n%s\n' "$FROM_NORM" "$VER" "$TO_NORM" | sort -V)
      FIRST="${SORTED%%$'\n'*}"
      LAST="${SORTED##*$'\n'}"

      # ver is in range if from sorts first and to sorts last
      if [ "$FIRST" = "$FROM_NORM" ] && [ "$LAST" = "$TO_NORM" ]; then
        BODY=$(printf '%s' "$RAW_JSON" | jq -r --arg tag "$TAG" '.[] | select(.tag_name == $tag) | .body // ""')
        if [ "$FIRST_OUTPUT" = true ]; then
          FIRST_OUTPUT=false
        else
          printf '\n---\n\n'
        fi
        printf '## %s\n\n%s\n' "$TAG" "$BODY"
      fi
    done < "$TMPFILE"

    if [ "$TOTAL" -ge 100 ]; then
      echo ""
      echo "warning: fetched 100 releases (API maximum per page); older releases may be missing. If the from-version is not found, fall back to WebFetch with pagination."
    fi
    ;;

  *)
    printf 'usage: fetch-release-notes.sh <subcommand> [args]\n\n'
    printf 'subcommands:\n'
    printf '  npm-repo <package>                               Repository URL for an npm package\n'
    printf '  pypi-repo <package>                              Repository URL for a PyPI package\n'
    printf '  github-releases <owner> <repo> <from> <to>      Release notes between versions (from < version <= to)\n'
    exit 1
    ;;
esac
