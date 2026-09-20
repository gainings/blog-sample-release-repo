#!/usr/bin/env bash
# 環境ディレクトリの .env にあるイメージを差し替える。アプリリポジトリの CI がこのスクリプトを呼んで PR を作る。
#
#   scripts/set-image.sh <service> <env> <registry/repository:tag> [<registry/repository:tag> ...]
#
# .env の中で「値が同じリポジトリ (registry/repository) を指している変数」をすべて書き換える。
# 変数名は問わない (IMAGE, IMAGE_NGINX, IMAGE_LOG_ROUTER など)。サイドカーのように 1 つの環境に複数の
# イメージがあっても、呼び出し側は自分がビルドしたイメージを渡すだけでよく、他のイメージには触れない。
# 渡したイメージのリポジトリを参照する変数が 1 つもなければエラーにする (別サービスへの誤投入を防ぐ)。
set -euo pipefail
service="${1:?usage: $0 <service> <env> <image>...}"
env_name="${2:?usage: $0 <service> <env> <image>...}"
shift 2
[ "$#" -ge 1 ] || { echo "usage: $0 <service> <env> <image>..." >&2; exit 1; }
f="services/${service}/${env_name}/.env"
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
diff "$f" "$work" | sed -n 's/^> /  /p'
cat "$work" > "$f"
echo "${f}: updated"
