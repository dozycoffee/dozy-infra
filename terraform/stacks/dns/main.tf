# 오래 두는 스택: 서브도메인 DNS 존과 와일드카드 인증서만 만든다.
# 올리고 내리는 스택(stacks/gcp)과 상태를 분리해, 내려도 네임서버와 인증서가 바뀌지 않게 한다.

module "dns" {
  source = "../../modules/dns"

  project_id = var.project_id
  domain     = var.domain
}
