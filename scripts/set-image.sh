#!/usr/bin/env bash
# 環境ディレクトリの .env にある IMAGE を差し替える。アプリリポジトリの CI がこのスクリプトを呼んで PR を作る。
# デプロイ方式によらず .env の 1 行を書き換えるだけ。安全のため、同じリポジトリ (registry/repository) への更新だけを受け付ける。
#   scripts/set-image.sh <service> <env> <registry/repository:tag>
set -euo pipefail
service="${1:?usage: $0 <service> <env> <image>}"
env_name="${2:?usage: $0 <service> <env> <image>}"
image="${3:?usage: $0 <service> <env> <image>}"
f="services/${service}/${env_name}/.env"
[ -f "$f" ] || { echo "no such environment: ${f}" >&2; exit 1; }

current=$(sed -n 's/^IMAGE=//p' "$f" | tail -n 1)
[ -n "$current" ] || { echo "${f}: IMAGE= line not found" >&2; exit 1; }
if [ "${current%:*}" != "${image%:*}" ]; then
  echo "${f}: repository mismatch (current: ${current%:*}, new: ${image%:*}); nothing changed" >&2
  exit 1
fi
if [ "$current" = "$image" ]; then
  echo "${f}: already ${image}"
  exit 0
fi
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
IMG="$image" awk 'BEGIN{img=ENVIRON["IMG"]} /^IMAGE=/{print "IMAGE=" img; next} {print}' "$f" > "$tmp"
cat "$tmp" > "$f"
echo "${f}: ${current} -> ${image}"
