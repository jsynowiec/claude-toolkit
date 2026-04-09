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
    fetch_json "https://nodejs.org/dist/index.json" \
      | jq -r 2>/dev/null '
          (.[0] | "latest_current=\(.version)\nlatest_current_date=\(.date)"),
          (map(select(.lts != false)) | .[0] | "latest_lts=\(.version)\nlatest_lts_codename=\(.lts)\nlatest_lts_date=\(.date)")
        ' \
      || { echo "error: unexpected response from https://nodejs.org/dist/index.json"; exit 1; }
    ;;

  nodejs-eol)
    fetch_json "https://endoflife.date/api/nodejs.json" \
      | jq -r --argjson all "$( [ "${2:-}" = "--all" ] && echo true || echo false )" 2>/dev/null '
          def is_supported:
            (.eol == false) or ((.eol | type) == "string" and .eol > (now | strftime("%Y-%m-%d")));
          .[] | select($all or is_supported)
          | "cycle=\(.cycle)\neol=\(.eol)\nlts=\(.lts)\nlatest=\(.latest)\n---"
        ' \
      || { echo "error: unexpected response from https://endoflife.date/api/nodejs.json"; exit 1; }
    ;;

  python-releases)
    fetch_json "https://endoflife.date/api/python.json" \
      | jq -r 2>/dev/null '
          (now | strftime("%Y-%m-%d")) as $today
          | [.[] | select(
              (.support == false) or ((.support | type) == "string" and .support > $today)
            )]
          | (.[0] | "latest_current=\(.latest)"),
            (.[1] | "latest_lts=\(.latest)")
        ' \
      || { echo "error: unexpected response from https://endoflife.date/api/python.json"; exit 1; }
    ;;

  python-eol)
    fetch_json "https://endoflife.date/api/python.json" \
      | jq -r --argjson all "$( [ "${2:-}" = "--all" ] && echo true || echo false )" 2>/dev/null '
          def is_supported:
            (.eol == false) or ((.eol | type) == "string" and .eol > (now | strftime("%Y-%m-%d")));
          .[] | select($all or is_supported)
          | "cycle=\(.cycle)\neol=\(.eol)\nlatest=\(.latest)\n---"
        ' \
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
      | jq -r --arg component "$COMPONENT" --arg version "$VERSION" 2>/dev/null '
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
        ') \
      || { echo "error: unexpected response from $VSCODE_URL"; exit 1; }
    if [ -z "$OUTPUT" ]; then
      echo "error: no VS Code version found bundling $COMPONENT ${VERSION}.x"
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
    echo "  vscode-compat <c> <ver>  Oldest VS Code version bundling a component version"
    exit 1
    ;;
esac
