#!/usr/bin/env bash
# 環境ディレクトリに置かれた定義ファイルからデプロイ方式を判定する。
#   scripts/kind.sh services/<service>/<env>   → ecs | lambda | cloudrun
set -euo pipefail
dir="${1:?usage: $0 <dir>}"
found=()
[ -f "$dir/ecspresso.yml" ] && found+=(ecs)
[ -f "$dir/function.json" ] && found+=(lambda)
[ -f "$dir/service.yaml" ] && found+=(cloudrun)
if [ "${#found[@]}" -ne 1 ]; then
  echo "cannot determine kind for ${dir}: found [${found[*]:-none}] (expect exactly one of ecspresso.yml / function.json / service.yaml)" >&2
  exit 1
fi
echo "${found[0]}"
