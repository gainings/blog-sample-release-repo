#!/usr/bin/env bash
set -euo pipefail
service="${1:?usage: $0 <service> <env>}"
env_name="${2:?usage: $0 <service> <env>}"
dir="services/${service}/${env_name}"
[ -d "$dir" ] || { echo "no such environment: ${dir}" >&2; exit 1; }
kind=$("$(dirname "$0")/kind.sh" "$dir")

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-dummy}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-dummy}"
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"

echo "==> ${service} / ${env_name} (${kind})"
case "$kind" in
  ecs)
    ecspresso --envfile "${dir}/.env" --config "${dir}/ecspresso.yml" render config
    ecspresso --envfile "${dir}/.env" --config "${dir}/ecspresso.yml" render task-definition
    ecspresso --envfile "${dir}/.env" --config "${dir}/ecspresso.yml" render service-definition
    ;;
  lambda)
    lambroll --envfile "${dir}/.env" render --function "${dir}/function.json"
    ;;
  cloudrun)
    set -a; . "${dir}/.env"; set +a
    envsubst < "${dir}/service.yaml" | tee /dev/stderr | yq -e '.spec.template.spec.containers[0].image | test(":")' >/dev/null
    ;;
esac
