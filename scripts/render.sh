#!/usr/bin/env bash
# デプロイ定義をダミーのイメージでレンダリングして表示する (クラウドには接続しない)。
# CI とローカルの両方から使う。
#
#   scripts/render.sh <service> <env>
set -euo pipefail

service="${1:?usage: $0 <service> <env>}"
env_name="${2:?usage: $0 <service> <env>}"
dir="services/${service}"
m="${dir}/service.yaml"

[ -f "$m" ] || { echo "unknown service: ${service}" >&2; exit 1; }
[ "$(yq ".environments.${env_name} != null" "$m")" = "true" ] || { echo "environment ${env_name} not defined in ${m}" >&2; exit 1; }

kind=$(yq '.kind' "$m")
export ENV="$env_name"
export IMAGE="$(yq '.image.registry' "$m")/$(yq '.image.repository' "$m"):sha-dummy"
export AWS_REGION="$(yq ".environments.${env_name}.aws.region // \"ap-northeast-1\"" "$m")"
export AWS_ACCOUNT_ID="$(yq ".environments.${env_name}.aws.account_id // \"000000000000\"" "$m")"
# 認証情報がなくても render できるようダミーを入れる
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-dummy}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-dummy}"

# environments.<env>.vars を環境変数に展開する
while IFS='=' read -r k v; do
  [ -n "$k" ] && export "$k=$v"
done < <(yq ".environments.${env_name}.vars // {} | to_entries[] | .key + \"=\" + (.value | tostring)" "$m")

echo "==> ${service} (${kind}) / ${env_name} / ${IMAGE}"
case "$kind" in
  ecs)
    ecspresso render --config "${dir}/ecspresso/config.yaml" config
    ecspresso render --config "${dir}/ecspresso/config.yaml" task-definition
    ecspresso render --config "${dir}/ecspresso/config.yaml" service-definition
    ;;
  lambda)
    lambroll render --function "${dir}/lambroll/function.json"
    ;;
  cloudrun)
    envsubst < "${dir}/cloudrun/service.yaml" | tee /dev/stderr | yq -e '.spec.template.spec.containers[0].image' >/dev/null
    ;;
  *)
    echo "unsupported kind: ${kind}" >&2; exit 1
    ;;
esac
