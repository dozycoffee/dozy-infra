#!/usr/bin/env bash
# releases/index.yaml 순서(wave)대로 서비스를 helm upgrade --install 한다.
# 값 우선순위: common.yaml < <서비스>.yaml < generated/common.yaml < generated/<서비스>.yaml
#
#   scripts/deploy.sh                 전체 배포
#   scripts/deploy.sh --only auth     한 서비스만
#   scripts/deploy.sh --dry-run       helm template으로 렌더링만(클러스터 불필요)
#   scripts/deploy.sh --generated DIR generated 값 위치(기본 releases/generated)
set -euo pipefail

cd "$(dirname "$0")/.."

only=""
dry=0
generated=releases/generated
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only="${2:?--only 뒤에 서비스 이름이 필요하다}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --generated) generated="${2:?--generated 뒤에 폴더가 필요하다}"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

command -v helm >/dev/null || { echo "helm이 필요하다" >&2; exit 1; }
command -v ruby >/dev/null || { echo "ruby가 필요하다" >&2; exit 1; }

# index.yaml에서 "namespace chart" 한 줄과 "wave 이름" 줄들(wave 오름차순)을 읽는다
plan="$(ruby -ryaml -e '
  idx = YAML.load_file("releases/index.yaml")
  puts "#{idx["namespace"]} #{idx["chart"]}"
  idx["services"].sort_by { |s| [s["wave"], s["name"]] }.each { |s| puts "#{s["wave"]} #{s["name"]}" }
')"
read -r namespace chart <<<"$(head -1 <<<"$plan")"
services="$(tail -n +2 <<<"$plan")"

[ -f "$generated/common.yaml" ] || { echo "$generated/common.yaml이 없다. scripts/render-config.sh를 먼저 실행한다" >&2; exit 1; }

if [ -n "$only" ] && ! grep -q " $only\$" <<<"$services"; then
  echo "index.yaml에 없는 서비스: $only" >&2
  exit 1
fi

values_args() { # <서비스>
  printf -- '-f releases/common.yaml -f releases/%s.yaml -f %s/common.yaml -f %s/%s.yaml' "$1" "$generated" "$generated" "$1"
}

while read -r wave svc; do
  [ -z "$only" ] || [ "$svc" = "$only" ] || continue
  [ -f "releases/$svc.yaml" ] || { echo "releases/$svc.yaml이 없다" >&2; exit 1; }
  [ -f "$generated/$svc.yaml" ] || { echo "$generated/$svc.yaml이 없다. scripts/render-config.sh를 먼저 실행한다" >&2; exit 1; }
  # shellcheck disable=SC2046
  if [ "$dry" = 1 ]; then
    echo "# --- $svc (wave $wave)"
    helm template "$svc" "$chart" -n "$namespace" $(values_args "$svc")
  else
    # 서비스 하나가 Ready가 될 때까지 기다린 뒤 다음으로 넘어간다(auth가 먼저 떠야 한다)
    echo "== $svc (wave $wave)"
    helm upgrade --install "$svc" "$chart" -n "$namespace" --create-namespace $(values_args "$svc") --wait --timeout 10m
  fi
done <<<"$services"
