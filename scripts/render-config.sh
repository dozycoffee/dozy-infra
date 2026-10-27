#!/usr/bin/env bash
# terraform output(stacks/gcp)과 도메인을 읽어 releases/generated/ 값 파일을 만든다.
#   releases/generated/common.yaml     도메인, Kafka 주소, auth 주소, 비밀값 접두사
#   releases/generated/<서비스>.yaml    서비스별 DB 접속 정보(비밀번호 제외)
# 생성 파일은 커밋하지 않는다(.gitignore). deploy.sh가 마지막에 겹쳐 준다.
#
# 입력(환경변수, 모두 선택)
#   DOZY_DOMAIN       도메인. 없으면 terraform/stacks/dns/terraform.tfvars의 domain
#   DOZY_OWNER_EMAIL  auth의 첫 owner 이메일(BOOTSTRAP_OWNER_EMAIL). 개인 정보라 저장소에 두지 않는다
#   KAFKA_MODE        self(기본). managed는 아직 지원하지 않는다
#   DOZY_GENERATED_DIR 출력 폴더(기본 releases/generated)
set -euo pipefail

cd "$(dirname "$0")/.."
out="${DOZY_GENERATED_DIR:-releases/generated}"
stack=terraform/stacks/gcp

die() { echo "오류: $*" >&2; exit 1; }
command -v terraform >/dev/null || die "terraform이 필요하다"
command -v ruby >/dev/null || die "ruby가 필요하다"

domain="${DOZY_DOMAIN:-}"
if [ -z "$domain" ] && [ -f terraform/stacks/dns/terraform.tfvars ]; then
  domain="$(sed -n 's/^[[:space:]]*domain[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' terraform/stacks/dns/terraform.tfvars | head -1)"
fi
[ -n "$domain" ] || die "도메인을 알 수 없다. DOZY_DOMAIN을 지정하거나 terraform/stacks/dns/terraform.tfvars에 domain을 둔다"

kafka_mode="${KAFKA_MODE:-self}"
[ "$kafka_mode" = self ] || die "KAFKA_MODE=$kafka_mode는 아직 지원하지 않는다(매니지드 Kafka는 infra-10)"

tf_json="$(terraform -chdir="$stack" output -json)" || die "terraform output 실패. 스택을 올렸는지(init, apply) 확인한다"
[ "$tf_json" != "{}" ] || die "terraform output이 비어 있다. 스택이 올라가 있지 않다"

mkdir -p "$out"
TF_JSON="$tf_json" DOMAIN="$domain" OWNER_EMAIL="${DOZY_OWNER_EMAIL:-}" OUT="$out" ruby -E UTF-8:UTF-8 -rjson -ryaml -e '# encoding: utf-8
  tf = JSON.parse(ENV["TF_JSON"])
  value = ->(k) { (tf[k] || abort("오류: terraform output에 #{k}가 없다"))["value"] }
  domain = ENV["DOMAIN"]

  # Secret Manager 항목 ID는 <접두사>-<서비스>-<이름>이다. 키(<서비스>/<이름>)를 떼어 접두사를 구한다
  secret_ids = value.("secret_ids")
  abort "오류: secret_ids가 비어 있다" if secret_ids.empty?
  prefixes = secret_ids.map { |key, id| id.delete_suffix("-" + key.tr("/", "-")) }.uniq
  abort "오류: 비밀값 접두사가 하나로 정해지지 않는다: #{prefixes}" unless prefixes.size == 1

  common = {
    "domain" => domain,
    "kafka" => { "bootstrapServers" => "kafka-0.kafka-headless.kafka.svc.cluster.local:9092" },
    "auth" => { "issuerBaseUri" => "https://auth.#{domain}", "bootstrapOwnerEmail" => ENV["OWNER_EMAIL"] },
    "externalSecret" => { "secretPrefix" => prefixes.first },
  }
  File.write(File.join(ENV["OUT"], "common.yaml"), "# render-config.sh가 만든 파일. 커밋하지 않는다.\n" + common.to_yaml)

  value.("database_connections").each do |svc, d|
    db = { "db" => { "engine" => d["engine"], "host" => d["host"], "port" => d["port"], "name" => d["name"], "user" => d["user"] } }
    File.write(File.join(ENV["OUT"], "#{svc}.yaml"), "# render-config.sh가 만든 파일. 커밋하지 않는다.\n" + db.to_yaml)
  end
'
echo "생성: $out/"
ls "$out"
