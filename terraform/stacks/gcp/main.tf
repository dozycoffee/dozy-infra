# 올리고 내리는 스택. DNS 존과 인증서는 오래 두는 stacks/dns가 맡는다(내려도 네임서버가 바뀌지 않게).

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  region     = var.region
}

module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id

  # 비밀값 주입 방식이 External Secrets Operator라는 전제다(설계 문서 미결정 #16). CSI 드라이버로 바꾸면 이 항목을 고친다.
  workload_identities = {
    eso = {
      namespace = "external-secrets"
      ksa_name  = "external-secrets"
      roles     = ["roles/secretmanager.secretAccessor"]
    }
  }
}

module "cloudsql" {
  source = "../../modules/cloudsql"

  project_id        = var.project_id
  region            = var.region
  network_self_link = module.network.network_self_link
  psa_connection_id = module.network.psa_connection_id

  databases = { for name, s in var.services : name => s.db if s.db != null }
}

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.project_id

  secrets = { for name, s in var.services : name => s.secrets }

  # DB 비밀번호는 테라폼이 만든 값을 그대로 넣는다. 나머지(SMTP, 서명 키 등)는 껍데기만 만들고 직접 넣는다.
  secret_versions = { for name, password in module.cloudsql.database_passwords : "${name}/db-password" => password }
}

module "gke" {
  source = "../../modules/gke"

  project_id                 = var.project_id
  region                     = var.region
  network_self_link          = module.network.network_self_link
  subnet_self_link           = module.network.gke_subnet_self_link
  pods_range_name            = module.network.pods_range_name
  services_range_name        = module.network.services_range_name
  master_authorized_cidrs    = var.master_authorized_cidrs
  node_service_account_email = module.iam.node_service_account_email
}
