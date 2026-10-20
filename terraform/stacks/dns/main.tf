# 오래 두는 스택: 도메인(dozy.kr)의 DNS 존, 기존 기록, 와일드카드 인증서를 만든다.
# 올리고 내리는 스택(stacks/gcp)과 상태를 분리해, 내려도 네임서버와 인증서가 바뀌지 않게 한다.

module "dns" {
  source = "../../modules/dns"

  project_id = var.project_id
  domain     = var.domain
  records    = local.records
}
