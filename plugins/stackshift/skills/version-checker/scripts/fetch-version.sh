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
  curl -fsSL --proto =https --max-redirs 3 --max-time 15 "$@" "$url" 2>/dev/null || {
    echo "error: failed to fetch $url"
    exit 1
  }
}

CMD="${1:-}"

case "$CMD" in
  nodejs-releases)
    NODEJS_URL="https://nodejs.org/dist/index.json"
    fetch_json "$NODEJS_URL" \
      | jq -r '
          (.[0] | "latest_current=\(.version)\nlatest_current_date=\(.date)"),
          (map(select(.lts != false)) | .[0] | "latest_lts=\(.version)\nlatest_lts_codename=\(.lts)\nlatest_lts_date=\(.date)")
        ' 2>/dev/null \
      || { echo "error: unexpected response from $NODEJS_URL"; exit 1; }
    ;;

  nodejs-eol)
    NODEJS_EOL_URL="https://endoflife.date/api/nodejs.json"
    fetch_json "$NODEJS_EOL_URL" \
      | jq -r --argjson all "$( [ "${2:-}" = "--all" ] && echo true || echo false )" '
          def is_supported:
            (.eol == false) or ((.eol | type) == "string" and .eol > (now | strftime("%Y-%m-%d")));
          .[] | select($all or is_supported)
          | "cycle=\(.cycle)\neol=\(.eol)\nlts=\(.lts)\nlatest=\(.latest)\n---"
        ' 2>/dev/null \
      || { echo "error: unexpected response from $NODEJS_EOL_URL"; exit 1; }
    ;;

  python-releases)
    PYTHON_URL="https://endoflife.date/api/python.json"
    fetch_json "$PYTHON_URL" \
      | jq -r '
          (now | strftime("%Y-%m-%d")) as $today
          | [.[] | select(
              (.support == false) or ((.support | type) == "string" and .support > $today)
            )]
          | (.[0] | "latest_current=\(.latest)"),
            (if .[1] then .[1] | "latest_lts=\(.latest)" else empty end)
        ' 2>/dev/null \
      || { echo "error: unexpected response from $PYTHON_URL"; exit 1; }
    ;;

  python-eol)
    PYTHON_EOL_URL="https://endoflife.date/api/python.json"
    fetch_json "$PYTHON_EOL_URL" \
      | jq -r --argjson all "$( [ "${2:-}" = "--all" ] && echo true || echo false )" '
          def is_supported:
            (.eol == false) or ((.eol | type) == "string" and .eol > (now | strftime("%Y-%m-%d")));
          .[] | select($all or is_supported)
          | "cycle=\(.cycle)\neol=\(.eol)\nlatest=\(.latest)\n---"
        ' 2>/dev/null \
      || { echo "error: unexpected response from $PYTHON_EOL_URL"; exit 1; }
    ;;

  npm)
    PKG="${2:-}"
    if [ -z "$PKG" ]; then
      echo "error: npm subcommand requires a package name (e.g., fetch-version.sh npm express)"
      exit 1
    fi
    if [[ ! "$PKG" =~ ^(@[a-zA-Z0-9._-]+/)?[a-zA-Z0-9._-]+$ ]]; then
      echo "error: invalid npm package name \"$PKG\""
      exit 1
    fi
    NPM_URL="https://registry.npmjs.org/$PKG"
    fetch_json "$NPM_URL" \
      -H "Accept: application/vnd.npm.install-v1+json" \
      | jq -r '"latest=\(.["dist-tags"].latest)"' 2>/dev/null \
      || { echo "error: unexpected response from $NPM_URL"; exit 1; }
    ;;

  pypi)
    PKG="${2:-}"
    if [ -z "$PKG" ]; then
      echo "error: pypi subcommand requires a package name (e.g., fetch-version.sh pypi flask)"
      exit 1
    fi
    if [[ ! "$PKG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
      echo "error: invalid PyPI package name \"$PKG\""
      exit 1
    fi
    PYPI_URL="https://pypi.org/pypi/$PKG/json"
    fetch_json "$PYPI_URL" \
      | jq -r '"latest=\(.info.version)\nrequires_python=\(.info.requires_python // "none")"' 2>/dev/null \
      || { echo "error: unexpected response from $PYPI_URL"; exit 1; }
    ;;

  vscode-compat)
    COMPONENT="${2:-}"
    VERSION="${3:-}"
    if [ -z "$COMPONENT" ] || [ -z "$VERSION" ]; then
      echo "error: vscode-compat requires a component and version (e.g., fetch-version.sh vscode-compat node 22)"
      exit 1
    fi
    case "$COMPONENT" in
      node|electron|chromium) ;;
      *)
        echo "error: unknown component \"$COMPONENT\" — must be one of: node, electron, chromium"
        exit 1
        ;;
    esac
    VERSION="${VERSION#v}"
    VSCODE_URL="https://raw.githubusercontent.com/ewanharris/vscode-versions/main/versions.json"
    OUTPUT=$(fetch_json "$VSCODE_URL" \
      | jq -r --arg component "$COMPONENT" --arg version "$VERSION" '
          ($version | split(".") | length) as $depth
          | [.[] | select(
              .[$component] | split(".")[0:$depth] | join(".")
              | . == $version
            )]
          | if length == 0 then empty
            else
              "oldest_vscode=\(.[-1].version)",
              "oldest_vscode_\($component)=\(.[-1][$component])",
              "oldest_vscode_created_at=\(.[-1].created_at)",
              "newest_vscode=\(.[0].version)"
            end
        ' 2>/dev/null) \
      || { echo "error: unexpected response from $VSCODE_URL"; exit 1; }
    if [ -z "$OUTPUT" ]; then
      echo "error: no VS Code version found bundling $COMPONENT $VERSION"
      exit 1
    fi
    echo "$OUTPUT"
    ;;

  *)
    echo "usage: fetch-version.sh <subcommand> [args]"
    echo ""
    echo "subcommands:"
    echo "  nodejs-releases          Latest Node.js Current and LTS versions"
    echo "  nodejs-eol [--all]       Node.js release cycle EOL dates (default: supported only)"
    echo "  python-releases          Latest Python current and stable versions"
    echo "  python-eol [--all]       Python release cycle EOL dates (default: supported only)"
    echo "  npm <package>            Latest npm package version"
    echo "  pypi <package>           Latest PyPI package version"
    echo "  vscode-compat <component> <ver>  Oldest VS Code version bundling a component version"
    exit 1
    ;;
esac
