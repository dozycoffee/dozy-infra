# 올리고 내리는 스택. DNS 존과 인증서는 오래 두는 stacks/dns가 맡는다(내려도 네임서버가 바뀌지 않게).
# 이후 gke, cloudsql, iam, secrets 모듈이 이 파일에 추가된다.

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  region     = var.region
}
