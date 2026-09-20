#!/usr/bin/env bash
# デプロイ定義をダミーのイメージでレンダリングして表示する (クラウドには接続しない)。
# CI とローカルの両方から使う。
#
#   scripts/render.sh <service> <env>
set -euo pipefail

service="${1:?usage: $0 <service> <env>}"
env_name="${2:?usage: $0 <service> <env>}"
svc="services/${service}/service.yaml"
env_dir="services/${service}/${env_name}"
envf="${env_dir}/env.yaml"

[ -f "$svc" ] || { echo "unknown service: ${service}" >&2; exit 1; }
[ -f "$envf" ] || { echo "environment ${env_name} not defined for ${service} (${envf} not found)" >&2; exit 1; }

kind=$(yq '.kind' "$svc")
export ENV="$env_name"
export IMAGE="$(yq '.image.registry' "$svc")/$(yq '.image.repository' "$svc"):sha-dummy"
export AWS_REGION="$(yq '.aws.region // "ap-northeast-1"' "$envf")"
export AWS_ACCOUNT_ID="$(yq '.aws.account_id // "000000000000"' "$envf")"
# 認証情報がなくても render できるようダミーを入れる
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-dummy}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-dummy}"

# env.yaml の vars (任意) を環境変数に展開する
while IFS='=' read -r k v; do
  [ -n "$k" ] && export "$k=$v"
done < <(yq '.vars // {} | to_entries[] | .key + "=" + (.value | tostring)' "$envf")

echo "==> ${service} (${kind}) / ${env_name} / ${IMAGE}"
case "$kind" in
  ecs)
    ecspresso render --config "${env_dir}/ecspresso/config.yaml" config
    ecspresso render --config "${env_dir}/ecspresso/config.yaml" task-definition
    ecspresso render --config "${env_dir}/ecspresso/config.yaml" service-definition
    ;;
  lambda)
    lambroll render --function "${env_dir}/lambroll/function.json"
    ;;
  cloudrun)
    envsubst < "${env_dir}/cloudrun/service.yaml" | tee /dev/stderr | yq -e '.spec.template.spec.containers[0].image' >/dev/null
    ;;
  *)
    echo "unsupported kind: ${kind}" >&2; exit 1
    ;;
esac
