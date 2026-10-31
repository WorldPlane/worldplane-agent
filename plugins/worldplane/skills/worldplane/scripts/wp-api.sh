#!/usr/bin/env bash
# Calls the WorldPlane control plane's API without showing the token.
#
#   wp-api.sh METHOD PATH [JSON_BODY]
#   wp-api.sh GET /v1/me
#   wp-api.sh POST /v1/tenants/mystudio/projects/mygame/environments/test/deploy '{"build":"<id>"}'
#   wp-api.sh -o WorldPlane.zip GET /v1/tenants/mystudio/downloads/unreal-plugin
#
# The URL and token come from WORLDPLANE_URL and WORLDPLANE_KEY (an API key or a
# session token), else from the session `worldplane login` kept. The URL defaults
# to https://app.worldplane.net. Prints the answer's body, or with -o saves it to
# that file (for downloads); exits 1 on an HTTP error, printing its status and
# message to stderr. Don't send secret values through this: use
# `worldplane env secret set`, which reads them unshown.
set -euo pipefail

out=
if [ "${1:-}" = "-o" ]; then
  out=${2:-}
  shift 2 || true
fi
if [ $# -lt 2 ]; then
  echo "usage: wp-api.sh [-o FILE] METHOD PATH [JSON_BODY]" >&2
  exit 2
fi
method=$1
path=$2
body=${3:-}

session_file() {
  if [ -n "${WORLDPLANE_CONFIG_DIR:-}" ]; then
    printf '%s/session.json' "$WORLDPLANE_CONFIG_DIR"
  elif [ -n "${APPDATA:-}" ]; then
    local dir=$APPDATA
    command -v cygpath >/dev/null 2>&1 && dir=$(cygpath -u "$APPDATA")
    printf '%s/worldplane/session.json' "$dir"
  elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s/worldplane/session.json' "$XDG_CONFIG_HOME"
  else
    printf '%s/.config/worldplane/session.json' "$HOME"
  fi
}

# One JSON string field of the session file (written one field to a line).
session_field() {
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\(.*\)\"[[:space:]]*,\{0,1\}[[:space:]]*\$/\1/p" "$2" | head -n 1
}

url=${WORLDPLANE_URL:-}
token=${WORLDPLANE_KEY:-}
if [ -z "$token" ]; then
  file=$(session_file)
  if [ ! -f "$file" ]; then
    echo "not signed in: run 'worldplane login --url https://app.worldplane.net --email <you>', or set WORLDPLANE_KEY" >&2
    exit 1
  fi
  token=$(session_field token "$file")
  [ -z "$url" ] && url=$(session_field url "$file")
fi
url=${url:-https://app.worldplane.net}
url=${url%/}
case "$path" in /*) ;; *) path="/$path" ;; esac

# The token goes to curl on standard input, as a config line, so it is in no
# command line and no output.
args=(-sS -X "$method" -K - -w '\n%{http_code}' "$url$path")
if [ -n "$body" ]; then
  args+=(-H 'Content-Type: application/json' --data-binary "$body")
fi
if [ -n "$out" ]; then
  # The body goes to the file; on an error it is the message, shown and removed.
  status=$(printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl -sS -X "$method" -K - -o "$out" -w '%{http_code}' "$url$path") || {
    echo "the control plane at $url did not answer" >&2
    exit 1
  }
  if [ "$status" -ge 400 ] 2>/dev/null; then
    echo "HTTP $status: $(cat "$out")" >&2
    rm -f "$out"
    exit 1
  fi
  echo "saved $out"
  exit 0
fi
answer=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl "${args[@]}") || {
  echo "the control plane at $url did not answer" >&2
  exit 1
}
status=${answer##*$'\n'}
content=${answer%$'\n'*}
if [ "$status" -ge 400 ] 2>/dev/null; then
  echo "HTTP $status: $content" >&2
  exit 1
fi
[ -n "$content" ] && printf '%s\n' "$content"
exit 0
