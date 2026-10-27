#!/usr/bin/env bash
# dozy-infra 검증. 가능한 검사를 모두 돌리고, 도구가 없어 건너뛴 항목은 숨기지 않고 출력한다.
# 검사 대상 파일이 있는데 필요한 도구가 없으면 실패로 처리한다.
set -uo pipefail

cd "$(dirname "$0")/.."
fail=0
skipped=()

step() { printf '\n== %s\n' "$1"; }
ng() { printf 'FAIL: %s\n' "$1"; fail=1; }

step "셸 스크립트 문법"
while IFS= read -r f; do
  bash -n "$f" || ng "$f"
done < <(find scripts -name '*.sh' -type f)

step "feature_list.json"
if command -v python3 >/dev/null; then
  python3 -I - <<'PY' || ng "feature_list.json 형식 오류"
import json, sys
tasks = json.load(open("feature_list.json"))
ids = {t["id"] for t in tasks}
status = {"pending", "in_progress", "completed"}
for t in tasks:
    for k in ("id", "name", "description", "status", "dependencies"):
        assert k in t, f"{t.get('id')}: {k} 없음"
    assert t["status"] in status, f"{t['id']}: status 값 오류"
    assert set(t["dependencies"]) <= ids, f"{t['id']}: 없는 의존 id"
print(f"{len(tasks)}개 작업 확인")
PY
else
  ng "python3 필요"
fi

step "terraform"
if find terraform -name '*.tf' -type f 2>/dev/null | grep -q .; then
  if command -v terraform >/dev/null; then
    terraform fmt -check -recursive terraform || ng "terraform fmt"
    while IFS= read -r d; do
      (cd "$d" && terraform init -backend=false -input=false >/dev/null && terraform validate) || ng "terraform validate: $d"
    done < <(find terraform/stacks -mindepth 1 -maxdepth 1 -type d)
    # 모듈 테스트(mock provider라 GCP 자격 증명이 필요 없다)
    while IFS= read -r t; do
      d="$(dirname "$(dirname "$t")")"
      (cd "$d" && terraform init -backend=false -input=false >/dev/null && terraform test) || ng "terraform test: $d"
    done < <(find terraform/modules -path '*/tests/*.tftest.hcl' -type f)
  else
    ng "terraform 파일이 있는데 terraform이 설치되어 있지 않다"
  fi
else
  skipped+=("terraform: .tf 파일 없음")
fi

step "helm"
if find charts -name Chart.yaml -type f 2>/dev/null | grep -q .; then
  if command -v helm >/dev/null; then
    while IFS= read -r c; do
      d="$(dirname "$c")"
      helm lint "$d" || ng "helm lint: $d"
    done < <(find charts -name Chart.yaml -type f)
    # 차트 테스트: helm template을 렌더링해서 검증한다(ruby 필요, 클러스터는 필요 없다)
    if find charts -path '*/tests/*_test.rb' -type f | grep -q .; then
      if command -v ruby >/dev/null; then
        while IFS= read -r t; do
          ruby "$t" || ng "차트 테스트: $t"
        done < <(find charts -path '*/tests/*_test.rb' -type f)
      else
        ng "차트 테스트가 있는데 ruby가 설치되어 있지 않다"
      fi
    fi
    # releases/ 전체를 가짜 generated 값으로 렌더링하고(deploy.sh --dry-run), 클라우드에서 쓰면 안 되는 local 프로필을 막는다
    if [ -d charts/dozy-service ] && [ -f releases/index.yaml ]; then
      if command -v ruby >/dev/null; then
        out="$(scripts/deploy.sh --dry-run --generated charts/dozy-service/tests/fixtures/generated)" || ng "deploy.sh --dry-run"
        if grep -A1 'SPRING_PROFILES_ACTIVE' <<<"$out" | grep -Eq 'value: "?local"?'; then
          ng "local 프로필 사용 금지(releases/)"
        fi
      else
        ng "releases가 있는데 ruby가 설치되어 있지 않다"
      fi
    fi
  else
    ng "차트가 있는데 helm이 설치되어 있지 않다"
  fi
else
  skipped+=("helm: 차트 없음")
fi

printf '\n== 건너뛴 항목\n'
if [ ${#skipped[@]} -eq 0 ]; then echo "없음"; else printf ' - %s\n' "${skipped[@]}"; fi

if [ "$fail" -ne 0 ]; then printf '\nverify 실패\n'; exit 1; fi
printf '\nverify 통과\n'
