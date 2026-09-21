#!/usr/bin/env bash
set -euo pipefail
dir="${1:?usage: $0 <service>/<env> <image>...}"
shift
[ "$#" -ge 1 ] || { echo "usage: $0 <service>/<env> <image>..." >&2; exit 1; }
f="${dir%/}/.env"
[ -f "$f" ] || { echo "no such environment: ${f}" >&2; exit 1; }

work=$(mktemp); next=$(mktemp); trap 'rm -f "$work" "$next"' EXIT
cp "$f" "$work"
for image in "$@"; do
  repo="${image%:*}"
  REPO="$repo" IMG="$image" awk '
    BEGIN { repo = ENVIRON["REPO"]; img = ENVIRON["IMG"] }
    /^[A-Za-z_][A-Za-z0-9_]*=/ {
      key = $0; sub(/=.*/, "", key)
      val = $0; sub(/^[^=]*=/, "", val)
      r = val; sub(/:[^:\/]*$/, "", r)
      if (r == repo) { print key "=" img; next }
    }
    { print }
  ' "$work" > "$next"
  if ! grep -Eq "^[A-Za-z_][A-Za-z0-9_]*=${repo//./\\.}:" "$next"; then
    echo "${f}: no variable references repository ${repo}; nothing changed for ${image}" >&2
    exit 1
  fi
  mv "$next" "$work"
done

if cmp -s "$f" "$work"; then
  echo "${f}: no changes"
  exit 0
fi
{ diff "$f" "$work" || true; } | sed -n 's/^> /  /p'
cat "$work" > "$f"
echo "${f}: updated"
