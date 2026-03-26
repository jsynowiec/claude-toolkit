#!/usr/bin/env bash
# ABOUTME: Fetches version data from registry APIs and outputs key=value pairs.
# ABOUTME: Used by the version-checker skill to avoid loading large JSON into context.

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "error: jq is required but not found in PATH. Install with: brew install jq (macOS) or apt-get install jq (Linux)"
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
  nodejs-releases)
    fetch_json "https://nodejs.org/dist/index.json" \
      | jq -r 2>/dev/null '
          (.[0] | "latest_current=\(.version)\nlatest_current_date=\(.date)"),
          (map(select(.lts != false)) | .[0] | "latest_lts=\(.version)\nlatest_lts_codename=\(.lts)\nlatest_lts_date=\(.date)")
        ' \
      || { echo "error: unexpected response from https://nodejs.org/dist/index.json"; exit 1; }
    ;;

  nodejs-eol)
    fetch_json "https://endoflife.date/api/nodejs.json" \
      | jq -r 2>/dev/null '.[] | "cycle=\(.cycle)\neol=\(.eol)\nlts=\(.lts)\nlatest=\(.latest)\n---"' \
      || { echo "error: unexpected response from https://endoflife.date/api/nodejs.json"; exit 1; }
    ;;

  python-eol)
    fetch_json "https://endoflife.date/api/python.json" \
      | jq -r 2>/dev/null '.[] | "cycle=\(.cycle)\neol=\(.eol)\nlatest=\(.latest)\n---"' \
      || { echo "error: unexpected response from https://endoflife.date/api/python.json"; exit 1; }
    ;;

  npm)
    PKG="${2:-}"
    if [ -z "$PKG" ]; then
      echo "error: npm subcommand requires a package name (e.g., fetch-version.sh npm express)"
      exit 1
    fi
    fetch_json "https://registry.npmjs.org/$PKG" \
      -H "Accept: application/vnd.npm.install-v1+json" \
      | jq -r 2>/dev/null '"latest=\(.["dist-tags"].latest)"' \
      || { echo "error: unexpected response from https://registry.npmjs.org/$PKG"; exit 1; }
    ;;

  pypi)
    PKG="${2:-}"
    if [ -z "$PKG" ]; then
      echo "error: pypi subcommand requires a package name (e.g., fetch-version.sh pypi flask)"
      exit 1
    fi
    fetch_json "https://pypi.org/pypi/$PKG/json" \
      | jq -r 2>/dev/null '"latest=\(.info.version)\nrequires_python=\(.info.requires_python // "none")"' \
      || { echo "error: unexpected response from https://pypi.org/pypi/$PKG/json"; exit 1; }
    ;;

  *)
    echo "usage: fetch-version.sh <subcommand> [args]"
    echo ""
    echo "subcommands:"
    echo "  nodejs-releases      Latest Node.js Current and LTS versions"
    echo "  nodejs-eol           Node.js release cycle EOL dates"
    echo "  python-eol           Python release cycle EOL dates"
    echo "  npm <package>        Latest npm package version"
    echo "  pypi <package>       Latest PyPI package version"
    exit 1
    ;;
esac
